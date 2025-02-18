package raytracer

import "core:fmt"
import vk "vendor:vulkan"
_ :: fmt

Renderer :: struct {
	ctx:    Context,
	window: ^Window,
}

make_renderer :: proc(
	window: ^Window,
	allocator := context.allocator,
) -> (
	renderer: Renderer,
	result: Context_Error,
) {
	renderer.ctx = make_context(window^, allocator) or_return
	renderer.window = window
	return
}

delete_renderer :: proc(renderer: ^Renderer) {
	delete_context(&renderer.ctx)
}

@(require_results)
renderer_begin_frame :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> (
	result: vk.Result,
) {
	frame_manager_acquire(&renderer.ctx) or_return

	frame_manager_frame_begin(&renderer.ctx) or_return

	frame_manager_frame_begin_rendering(
		&renderer.ctx,
		renderer.ctx.swapchain.extent,
		vk.ClearValue{color = {float32 = {0, 0, 0, 1}}},
	)

	return
}

renderer_draw :: proc(renderer: ^Renderer) {
	cmd_handle := frame_manager_frame_get_command_buffer(&renderer.ctx).handle

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

	vk.CmdDraw(cmd_handle, 3, 1, 0, 0)
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

renderer_handle_resize :: proc(renderer: ^Renderer, allocator := context.allocator) -> vk.Result {
	return handle_resize(&renderer.ctx, renderer.window^, allocator)
}
