package raytracer

import "core:fmt"
import vkb "external:odin-vk-bootstrap"
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
	ok: bool,
) {
	for &f, i in frame_manager.frames {
		f = make_frame_data(ctx, i, allocator) or_return
	}

	frame_manager.current_frame = 0

	ok = true
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
	image := swapchain_acquire_next_image(ctx.swapchain, frame.image_available) or_return
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

	return frame_submit(frame, ctx.graphics_queue)
}

@(require_results)
frame_manager_frame_present :: proc(ctx: ^Context) -> vk.Result {
	frame := frame_manager_get_frame(&ctx.frame_manager)

	return present_frame(frame, ctx.present_queue, &ctx.swapchain)
}

frame_manager_advance :: proc(ctx: ^Context) {
	manager := &ctx.frame_manager
	manager.current_frame = (manager.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
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
}

// TODO: handle this function, only need to create new descriptor sets if the its not from resize(check if this is actually true)
make_frame_data :: proc(
	ctx: Context,
	frame_index: int,
	allocator := context.allocator,
) -> (
	frame: Per_Frame,
	ok: bool,
) {
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
	fmt.println("OLA")
	frame.render_finished = make_semaphore(ctx.device) or_return

	ok = true
	return
}

frame_begin :: proc(
	frame: ^Per_Frame,
	device: ^vkb.Device,
	swapchain: ^vkb.Swapchain,
) -> (
	result: vk.Result,
) {
	frame_reset(frame, device) or_return
	frame_begin_commands(frame, device) or_return
	return
}

frame_wait :: proc(frame: ^Per_Frame, device: ^vkb.Device) -> (result: vk.Result) {
	return fence_wait(&frame.in_flight_fence)
}

frame_reset :: proc(frame: ^Per_Frame, device: ^vkb.Device) -> (result: vk.Result) {
	return fence_reset(&frame.in_flight_fence)
}

frame_begin_commands :: proc(frame: ^Per_Frame, device: ^vkb.Device) -> (result: vk.Result) {
	command_pool_reset(frame.command_pool, device) or_return

	return command_buffer_begin(frame.command_buffer)
}

delete_frame_data :: proc(ctx: Context, per_frame: ^Per_Frame) {
	delete_command_pool(per_frame.command_pool, ctx.device)
	delete_fence(per_frame.in_flight_fence)
	delete_semaphore(per_frame.image_available)
	delete_semaphore(per_frame.render_finished)
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

frame_submit :: proc(frame: ^Per_Frame, queue: vk.Queue) -> vk.Result {
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &frame.image_available.ptr,
		pWaitDstStageMask    = raw_data([]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}),
		commandBufferCount   = 1,
		pCommandBuffers      = &frame.command_buffer.handle,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &frame.render_finished.ptr,
	}

	return vk.QueueSubmit(queue, 1, &submit_info, frame.in_flight_fence.ptr)
}

@(require_results)
present_frame :: proc(
	frame: ^Per_Frame,
	queue: vk.Queue,
	swapchain: ^vkb.Swapchain,
) -> (
	result: vk.Result,
) {
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.render_finished.ptr,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.ptr,
		pImageIndices      = &frame.image.index,
	}

	return vk.QueuePresentKHR(queue, &present_info)
}

@(private = "file")
Image_Acquisition_Result :: struct {
	index:      u32,
	image:      vk.Image,
	image_view: vk.ImageView,
	extent:     vk.Extent2D,
}

@(private = "file")
@(require_results)
swapchain_acquire_next_image :: proc(
	swapchain: Swapchain,
	semaphore: Semaphore,
) -> (
	result: Image_Acquisition_Result,
	err: vk.Result,
) {
	vk.AcquireNextImageKHR(
		swapchain.device.ptr,
		swapchain.ptr,
		max(u64),
		semaphore.ptr,
		0,
		&result.index,
	) or_return
	result.image = swapchain.images[result.index]
	result.image_view = swapchain.image_views[result.index]
	result.extent = swapchain.extent

	return
}
