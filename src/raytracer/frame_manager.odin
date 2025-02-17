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
	device: Device,
	allocator := context.allocator,
) -> (
	frame_manager: Frame_Manager,
	result: vk.Result,
) {
	for &f, i in frame_manager.frames {
		f = make_frame_data(device, i, allocator) or_return
	}

	frame_manager.current_frame = 0

	return
}

frame_manager_get_frame :: proc(manager: ^Frame_Manager) -> ^Per_Frame {
	return &manager.frames[manager.current_frame]
}

frame_manager_begin :: proc(
	manager: ^Frame_Manager,
	device: Device,
	swapchain: Swapchain,
) -> (
	frame: ^Per_Frame,
	should_resize: bool,
	result: vk.Result,
) {
	frame = frame_manager_get_frame(manager)

	frame_wait(frame, device) or_return
	frame_reset(frame, device) or_return

	image := swapchain_acquire_next_image(swapchain, device, frame.image_available) or_return
	frame.image = {
		index  = image.index,
		handle = image.image,
		view   = image.image_view,
	}

	frame_begin_commands(frame, device) or_return

	return frame, should_resize, .SUCCESS
}

frame_manager_advance :: proc(manager: ^Frame_Manager) {
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

make_frame_data :: proc(
	device: Device,
	frame_index: int,
	allocator := context.allocator,
) -> (
	frame: Per_Frame,
	result: vk.Result,
) {
	frame.command_pool = make_command_pool(
		device,
		fmt.tprintf("Frame Command Pool %d", frame_index),
		allocator,
	) or_return

	frame.command_buffer = command_pool_allocate_primary_buffer(
		device,
		&frame.command_pool,
		fmt.tprintf("Frame Command Buffer %d", frame_index),
		allocator,
	) or_return

	frame.in_flight_fence = make_fence(device, signaled = true) or_return
	frame.image_available = make_semaphore(device) or_return
	frame.render_finished = make_semaphore(device) or_return

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

delete_frame_data :: proc(per_frame: Per_Frame, device: Device) {
	delete_command_pool(per_frame.command_pool, device)
	delete_fence(per_frame.in_flight_fence, device)
	delete_semaphore(per_frame.image_available, device)
	delete_semaphore(per_frame.render_finished, device)
}

frame_begin_rendering :: proc(frame: ^Per_Frame, extent: vk.Extent2D, clear_color: vk.ClearValue) {
	// image_transition(frame, {
	//     image = sw
	// })
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
