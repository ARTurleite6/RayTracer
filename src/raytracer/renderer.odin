package raytracer

import vk "vendor:vulkan"

MAX_IN_FLIGHT_FRAMES :: #config(MAX_IN_FLIGHT_FRAMES, 3)

Renderer :: struct {
	ctx:           ^Context,
	frames:        [MAX_IN_FLIGHT_FRAMES]Frame,
	current_frame: u32,
}

@(require_results)
renderer_init :: proc(renderer: ^Renderer, ctx: ^Context) -> (err: Error) {
	renderer.ctx = ctx
	for &frame, i in renderer.frames {
		frame_init(
			&frame,
			renderer.ctx.device,
			renderer.ctx.command_pool.command_buffer[i],
		) or_return
	}

	return
}

renderer_render :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	ctx := renderer.ctx
	device := ctx.device
	swapchain := ctx.swapchain
	current_frame := renderer.frames[renderer.current_frame]
	defer renderer.current_frame = (renderer.current_frame + 1) % MAX_IN_FLIGHT_FRAMES

	fence_wait(&current_frame.in_flight_fence, device)
	fence_reset(&current_frame.in_flight_fence, device)

	image_index: u32
	if image_index, result = swapchain_acquire_next_image(
		swapchain,
		device,
		current_frame.image_available_semaphore,
	); result != .SUCCESS {
		return result
	}
	frame_start(&current_frame, image_index)

	{ 	// rendering 
		if result = command_buffer_start_recording(current_frame.command_buffer);
		   result != .SUCCESS {
			return
		}

		command_buffer_start_rendering(
			current_frame.command_buffer,
			swapchain.image_views[image_index],
			{offset = {}, extent = swapchain.extent},
		)

		set_pipeline_state(current_frame.command_buffer, ctx.pipeline, ctx.swapchain)

		command_buffer_draw(current_frame.command_buffer, 3, 1, 0, 0)

		command_buffer_stop_rendering(current_frame.command_buffer)

		if result = command_buffer_stop_recording(current_frame.command_buffer);
		   result != .SUCCESS {
			return
		}

		if result = command_buffer_submit(
			command_buffer = &current_frame.command_buffer,
			queue = ctx.graphics_queue,
			wait_semaphores = {current_frame.image_available_semaphore},
			wait_stages = {{.COLOR_ATTACHMENT_OUTPUT}},
			signal_semaphores = {current_frame.render_finished_semaphore},
			fence = current_frame.in_flight_fence,
		); result != .SUCCESS {
			return result
		}

		present_frame(ctx.present_queue, &current_frame, &swapchain)

	}

	return
}

renderer_destroy :: proc(renderer: Renderer) {
	for frame in renderer.frames {
		frame_destroy(frame, renderer.ctx.device)
	}
}

@(private = "file")
set_pipeline_state :: proc(
	command_buffer: vk.CommandBuffer,
	pipeline: Pipeline,
	swapchain: Swapchain,
) {
	command_buffer_set_pipeline(command_buffer, pipeline)
	command_buffer_set_viewport(
		command_buffer,
		{
			x = 0,
			y = 0,
			width = f32(swapchain.extent.width),
			height = f32(swapchain.extent.height),
			maxDepth = 1,
			minDepth = 0,
		},
	)

	command_buffer_set_scissor(command_buffer, {extent = swapchain.extent})

}

@(private = "file")
present_frame :: proc(present_queue: vk.Queue, current_frame: ^Frame, swapchain: ^Swapchain) {
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &current_frame.render_finished_semaphore,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.handle,
		pImageIndices      = &current_frame.image_index,
	}

	vk.QueuePresentKHR(present_queue, &present_info)
}
