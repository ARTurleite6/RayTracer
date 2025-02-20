package raytracer

import "core:fmt"
import vk "vendor:vulkan"
_ :: fmt

Renderer :: struct {
	ctx:    Context,
	window: ^Window,
	buffer: Buffer, // TODO: Try this out only
	camera: Camera,
}

VERTICES := []Vertex {
	{{0.0, -0.5, 0.0}, {1.0, 0.0, 0.0}},
	{{0.5, 0.5, 0.0}, {0.0, 1.0, 0.0}},
	{{-0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}},
}

renderer_init :: proc(
	renderer: ^Renderer,
	window: ^Window,
	allocator := context.allocator,
) -> (
	ok: bool,
) {
	context_init(&renderer.ctx, window^, allocator) or_return
	renderer.window = window

	renderer.buffer = make_buffer_with_data(
		renderer.ctx.allocator,
		VERTICES,
		{.VERTEX_BUFFER},
		.Auto,
	) or_return

	camera_init(&renderer.camera, aspect = window_aspect_ratio(window^))
	return true
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.ptr)
	delete_buffer(&renderer.buffer)
	delete_context(&renderer.ctx)
}

@(require_results)
renderer_begin_frame :: proc(renderer: ^Renderer, allocator := context.allocator) -> (ok: bool) {
	frame_manager_acquire(&renderer.ctx) or_return


	frame_manager_frame_begin(&renderer.ctx) or_return

	frame_manager_frame_begin_rendering(
		&renderer.ctx,
		renderer.ctx.swapchain.extent,
		vk.ClearValue{color = {float32 = {0, 0, 0, 1}}},
	)

	return true
}

renderer_draw :: proc(renderer: ^Renderer) {
	frame := frame_manager_get_frame(&renderer.ctx.frame_manager) // TODO: Improve this
	cmd_handle := frame.command_buffer.handle

	vk.CmdBindPipeline(cmd_handle, .GRAPHICS, renderer.ctx.pipeline.handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(renderer.ctx.swapchain.extent.width),
		height   = f32(renderer.ctx.swapchain.extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	vk.CmdSetViewport(cmd_handle, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = renderer.ctx.swapchain.extent,
	}

	vk.CmdSetScissor(cmd_handle, 0, 1, &scissor)

	vk.CmdBindVertexBuffers(
		cmd_handle,
		0,
		1,
		raw_data([]vk.Buffer{renderer.buffer.handle}),
		raw_data([]vk.DeviceSize{0}),
	)

	vk.CmdDraw(cmd_handle, u32(len(VERTICES)), 1, 0, 0)
}

@(require_results)
renderer_end_frame :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	frame_manager_frame_end_rendering(&renderer.ctx)

	renderer_flush(renderer) or_return
	frame_manager_advance(&renderer.ctx)
	return
}

@(require_results)
renderer_flush :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	cmd := frame_manager_frame_get_command_buffer(&renderer.ctx)
	vk.EndCommandBuffer(cmd.handle) or_return // TODO: probably clean this

	frame_manager_frame_submit(&renderer.ctx) or_return

	frame_manager_frame_present(&renderer.ctx) or_return

	return
}

renderer_handle_resize :: proc(renderer: ^Renderer, allocator := context.allocator) -> (ok: bool) {
	handle_resize(&renderer.ctx, renderer.window^, allocator) or_return

	renderer.camera.aspect = window_aspect_ratio(renderer.window^)
	camera_update_matrices(&renderer.camera)

	ok = true
	return
}
