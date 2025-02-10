package raytracer

import vk "vendor:vulkan"

Frame :: struct {
	command_buffer:            vk.CommandBuffer,
	image_index:               u32,
	image_available_semaphore: vk.Semaphore,
	render_finished_semaphore: vk.Semaphore,
	in_flight_fence:           Fence,
}

@(require_results)
frame_init :: proc(frame: ^Frame, device: Device, command_buffer: vk.CommandBuffer) -> vk.Result {

	frame.command_buffer = command_buffer

	if result := semaphore_init(&frame.image_available_semaphore, device); result != .SUCCESS {
		return result
	}

	if result := semaphore_init(&frame.render_finished_semaphore, device); result != .SUCCESS {
		return result
	}

	return fence_init(&frame.in_flight_fence, device)
}

frame_start :: proc(frame: ^Frame, image_index: u32) {
	frame.image_index = image_index
}

frame_destroy :: proc(frame: Frame, device: Device) {
	vk.DestroySemaphore(device, frame.image_available_semaphore, nil)
	vk.DestroySemaphore(device, frame.render_finished_semaphore, nil)
	fence_destroy(frame.in_flight_fence, device)
}
