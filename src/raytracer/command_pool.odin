package raytracer

import vk "vendor:vulkan"

Command_Pool :: struct {
	handle:         vk.CommandPool,
	command_buffer: [MAX_IN_FLIGHT_FRAMES]vk.CommandBuffer,
}

@(require_results)
command_pool_init :: proc(
	command_pool: ^Command_Pool,
	device: Device,
	queue_familiy_index: u32,
) -> vk.Result {
	{ 	// create command pool
		create_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			flags            = {.RESET_COMMAND_BUFFER},
			queueFamilyIndex = queue_familiy_index,
		}

		if result := vk.CreateCommandPool(device, &create_info, nil, &command_pool.handle);
		   result != .SUCCESS {
			return result
		}
	}

	{ 	// create command buffers
		alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = command_pool.handle,
			level              = .PRIMARY,
			commandBufferCount = MAX_IN_FLIGHT_FRAMES,
		}

		return vk.AllocateCommandBuffers(
			device,
			&alloc_info,
			raw_data(command_pool.command_buffer[:]),
		)
	}
}

@(require_results)
command_buffer_start_recording :: proc(command_buffer: vk.CommandBuffer) -> vk.Result {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	vk.ResetCommandBuffer(command_buffer, {})
	return vk.BeginCommandBuffer(command_buffer, &begin_info)
}

command_buffer_start_rendering :: proc(
	command_buffer: vk.CommandBuffer,
	render_pass: vk.RenderPass,
	framebuffer: Framebuffer,
	render_area: vk.Rect2D,
) {
	render_info := vk.RenderPassBeginInfo {
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = render_pass,
		framebuffer     = framebuffer,
		renderArea      = render_area,
		clearValueCount = 1,
		pClearValues    = raw_data(
			[]vk.ClearValue{vk.ClearValue{color = vk.ClearColorValue{float32 = {0, 0, 0, 1}}}},
		),
	}

	vk.CmdBeginRenderPass(command_buffer, &render_info, vk.SubpassContents.INLINE)
}

command_buffer_set_viewport :: proc(command_buffer: vk.CommandBuffer, viewport: vk.Viewport) {
	vk.CmdSetViewport(command_buffer, 0, 1, raw_data([]vk.Viewport{viewport}))
}

command_buffer_set_scissor :: proc(command_buffer: vk.CommandBuffer, scissor: vk.Rect2D) {
	vk.CmdSetScissor(command_buffer, 0, 1, raw_data([]vk.Rect2D{scissor}))
}

command_buffer_set_pipeline :: proc(command_buffer: vk.CommandBuffer, pipeline: Pipeline) {
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline.handle)
}

command_buffer_draw :: proc(
	command_buffer: vk.CommandBuffer,
	vertex_count: u32,
	instance_count: u32,
	first_vertex: u32,
	first_instance: u32,
) {
	vk.CmdDraw(command_buffer, vertex_count, instance_count, first_vertex, first_instance)
}

command_buffer_submit :: proc(
	command_buffer: ^vk.CommandBuffer,
	queue: vk.Queue,
	wait_semaphores: []Semaphore,
	wait_stages: []vk.PipelineStageFlags,
	signal_semaphores: []Semaphore,
	fence: vk.Fence,
) -> vk.Result {
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = u32(len(wait_semaphores)),
		pWaitSemaphores      = raw_data(wait_semaphores),
		pWaitDstStageMask    = raw_data(wait_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = command_buffer,
		signalSemaphoreCount = u32(len(signal_semaphores)),
		pSignalSemaphores    = raw_data(signal_semaphores),
	}

	return vk.QueueSubmit(queue, 1, &submit_info, fence)
}

command_buffer_stop_rendering :: proc(command_buffer: vk.CommandBuffer) {
	vk.CmdEndRenderPass(command_buffer)
}

@(require_results)
command_buffer_stop_recording :: proc(command_buffer: vk.CommandBuffer) -> vk.Result {
	return vk.EndCommandBuffer(command_buffer)
}

command_pool_destroy :: proc(command_pool: ^Command_Pool, device: Device) {
	vk.FreeCommandBuffers(
		device,
		command_pool.handle,
		MAX_IN_FLIGHT_FRAMES,
		raw_data(command_pool.command_buffer[:]),
	)
	vk.DestroyCommandPool(device, command_pool.handle, nil)
}
