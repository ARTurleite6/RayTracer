package raytracer

import "core:fmt"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 1

Frame_Manager :: struct {
	frames:        [MAX_FRAMES_IN_FLIGHT]Per_Frame,
	current_frame: int,
}

@(require_results)
make_frame_manager :: proc(
	ctx: Context,
	allocator := context.allocator,
) -> (
	frame_manager: Frame_Manager,
	result: vk.Result,
) {
	for &f, i in frame_manager.frames {
		f = make_frame_data(ctx, i, allocator) or_return
	}

	frame_manager.current_frame = 0

	return
}

delete_frame_manager :: proc(ctx: ^Context) {
	for &frame in ctx.frame_manager.frames {
		delete_frame_data(ctx^, &frame)
	}
	ctx.frame_manager.current_frame = 0
}

@(require_results)
frame_manager_get_frame :: proc(manager: ^Frame_Manager) -> ^Per_Frame {
	return &manager.frames[manager.current_frame]
}

@(require_results)
frame_manager_acquire :: proc(ctx: ^Context) -> (result: vk.Result) {
	frame := frame_manager_get_frame(&ctx.frame_manager)
	frame_wait(frame, ctx.device) or_return
	image := swapchain_acquire_next_image(
		ctx.swapchain,
		ctx.device,
		frame.image_available,
	) or_return
	frame.image = {
		index  = image.index,
		handle = image.image,
		view   = image.image_view,
	}

	return
}

@(require_results)
frame_manager_frame_begin :: proc(ctx: ^Context) -> vk.Result {
	frame := frame_manager_get_frame(&ctx.frame_manager)

	return frame_begin(frame, ctx.device, ctx.swapchain)
}

// TODO: probably in the future remove this
@(require_results)
frame_manager_frame_get_command_buffer :: proc(ctx: ^Context) -> Command_Buffer {
	return frame_manager_get_frame(&ctx.frame_manager).command_buffer
}

frame_manager_frame_begin_rendering :: proc(
	ctx: ^Context,
	extent: vk.Extent2D,
	clear_color: vk.ClearValue,
) {
	frame := frame_manager_get_frame(&ctx.frame_manager)

	frame_begin_rendering(frame, extent, clear_color)
}

frame_manager_frame_end_rendering :: proc(ctx: ^Context) {
	frame := frame_manager_get_frame(&ctx.frame_manager)
	frame_end_rendering(frame)
}

@(require_results)
frame_manager_frame_submit :: proc(ctx: ^Context) -> vk.Result {
	frame := frame_manager_get_frame(&ctx.frame_manager)

	return frame_submit(frame, ctx.device, ctx.device.graphics_queue)
}

@(require_results)
frame_manager_frame_present :: proc(ctx: ^Context) -> vk.Result {
	frame := frame_manager_get_frame(&ctx.frame_manager)

	return present_frame(frame, ctx.device.presents_queue, &ctx.swapchain)
}

frame_manager_advance :: proc(ctx: ^Context) {
	manager := &ctx.frame_manager
	manager.current_frame = (manager.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}

// TODO: Improve this
frame_manager_update_uniform :: proc(ctx: ^Context, view_proj: Mat4) {
	frame := frame_manager_get_frame(&ctx.frame_manager)

	ubo := Uniform_Buffer_Object {
		view_proj = view_proj,
	}
	buffer_upload_data(ctx^, &frame.uniform_buffer, []Uniform_Buffer_Object{ubo})
}

Per_Frame :: struct {
	command_pool:    Command_Pool,
	command_buffer:  Command_Buffer,
	image:           struct {
		index:  u32,
		handle: vk.Image,
		view:   vk.ImageView,
	},
	in_flight_fence: Fence,
	image_available: Semaphore,
	render_finished: Semaphore,
	uniform_buffer:  Buffer,
	descriptor_set:  vk.DescriptorSet,
}

// TODO: handle this function, only need to create new descriptor sets if the its not from resize(check if this is actually true)
make_frame_data :: proc(
	ctx: Context,
	frame_index: int,
	allocator := context.allocator,
) -> (
	frame: Per_Frame,
	result: vk.Result,
) {
	frame.uniform_buffer = make_buffer(ctx, size_of(Uniform_Buffer_Object), .Uniform) or_return

	descriptor_layout := ctx.pipeline.descriptor_set_layout
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = ctx.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &descriptor_layout,
	}

	vk.AllocateDescriptorSets(ctx.device.handle, &alloc_info, &frame.descriptor_set) or_return

	buffer_info := vk.DescriptorBufferInfo {
		buffer = frame.uniform_buffer.handle,
		offset = 0,
		range  = size_of(Uniform_Buffer_Object),
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = frame.descriptor_set,
		dstBinding      = 0,
		descriptorCount = 1,
		descriptorType  = .UNIFORM_BUFFER,
		pBufferInfo     = &buffer_info,
	}

	vk.UpdateDescriptorSets(ctx.device.handle, 1, &write, 0, nil)

	frame.command_pool = make_command_pool(
		ctx.device,
		fmt.tprintf("Frame Command Pool %d", frame_index),
		allocator,
	) or_return

	frame.command_buffer = command_pool_allocate_primary_buffer(
		ctx.device,
		&frame.command_pool,
		fmt.tprintf("Frame Command Buffer %d", frame_index),
		allocator,
	) or_return

	frame.in_flight_fence = make_fence(ctx.device, signaled = true) or_return
	frame.image_available = make_semaphore(ctx.device) or_return
	frame.render_finished = make_semaphore(ctx.device) or_return

	return
}

frame_begin :: proc(
	frame: ^Per_Frame,
	device: Device,
	swapchain: Swapchain,
) -> (
	result: vk.Result,
) {
	frame_reset(frame, device) or_return
	frame_begin_commands(frame, device) or_return
	return
}

frame_wait :: proc(frame: ^Per_Frame, device: Device) -> (result: vk.Result) {
	return fence_wait(&frame.in_flight_fence, device)
}

frame_reset :: proc(frame: ^Per_Frame, device: Device) -> (result: vk.Result) {
	return fence_reset(&frame.in_flight_fence, device)
}

frame_begin_commands :: proc(frame: ^Per_Frame, device: Device) -> (result: vk.Result) {
	command_pool_reset(frame.command_pool, device) or_return

	return command_buffer_begin(frame.command_buffer)
}

delete_frame_data :: proc(ctx: Context, per_frame: ^Per_Frame) {
	vk.FreeDescriptorSets(ctx.device.handle, ctx.descriptor_pool, 1, &per_frame.descriptor_set)
	delete_buffer(ctx, per_frame.uniform_buffer)
	delete_command_pool(per_frame.command_pool, ctx.device)
	delete_fence(per_frame.in_flight_fence, ctx.device)
	delete_semaphore(per_frame.image_available, ctx.device)
	delete_semaphore(per_frame.render_finished, ctx.device)
}

frame_begin_rendering :: proc(frame: ^Per_Frame, extent: vk.Extent2D, clear_color: vk.ClearValue) {
	image_transition(
		frame.command_buffer,
		{
			image = frame.image.handle,
			old_layout = .UNDEFINED,
			new_layout = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage = {.TOP_OF_PIPE},
			dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
			src_access = {},
			dst_access = {.COLOR_ATTACHMENT_WRITE},
		},
	)

	command_buffer_begin_rendering(frame.command_buffer, frame.image.view, extent, clear_color)
}

frame_end_rendering :: proc(frame: ^Per_Frame) {
	command_buffer_end_rendering(frame.command_buffer)

	image_transition(
		frame.command_buffer,
		{
			image = frame.image.handle,
			old_layout = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout = .PRESENT_SRC_KHR,
			src_stage = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage = {.BOTTOM_OF_PIPE},
			src_access = {.COLOR_ATTACHMENT_WRITE},
			dst_access = {},
		},
	)

}

frame_submit :: proc(frame: ^Per_Frame, device: Device, queue: vk.Queue) -> vk.Result {
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &frame.image_available,
		pWaitDstStageMask    = raw_data([]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}),
		commandBufferCount   = 1,
		pCommandBuffers      = &frame.command_buffer.handle,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &frame.render_finished,
	}

	return vk.QueueSubmit(queue, 1, &submit_info, frame.in_flight_fence)
}

@(require_results)
present_frame :: proc(
	frame: ^Per_Frame,
	queue: vk.Queue,
	swapchain: ^Swapchain,
) -> (
	result: vk.Result,
) {
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.render_finished,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.handle,
		pImageIndices      = &frame.image.index,
	}

	return vk.QueuePresentKHR(queue, &present_info)
}
