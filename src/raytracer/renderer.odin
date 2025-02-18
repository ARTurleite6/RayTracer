package raytracer

import "core:fmt"
import "core:log"
import vk "vendor:vulkan"
_ :: fmt

Renderer :: struct {
	ctx:                 Context,
	window:              ^Window,
	frame_manager:       Frame_Manager,
	current_frame:       ^Per_Frame,
	framebuffer_resized: bool,
}

make_renderer :: proc(
	window: ^Window,
	allocator := context.allocator,
) -> (
	renderer: Renderer,
	result: Context_Error,
) {
	renderer.ctx = make_context(window^, allocator) or_return
	renderer.frame_manager = make_frame_manager(renderer.ctx.device, allocator) or_return
	renderer.window = window
	return
}

@(require_results)
renderer_begin_frame :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> (
	result: vk.Result,
) {
	renderer.current_frame = frame_manager_acquire(
		&renderer.frame_manager,
		renderer.ctx.device,
		renderer.ctx.swapchain,
	) or_return

	frame_begin(renderer.current_frame, renderer.ctx.device, renderer.ctx.swapchain)

	frame_begin_rendering(
		renderer.current_frame,
		renderer.ctx.swapchain.extent,
		vk.ClearValue{color = {float32 = {0, 0, 0, 1}}},
	)

	return
}

renderer_draw :: proc(renderer: Renderer) {
	cmd := renderer.current_frame.command_buffer

	vk.CmdBindPipeline(cmd.handle, .GRAPHICS, renderer.ctx.pipeline.handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(renderer.ctx.swapchain.extent.width),
		height   = f32(renderer.ctx.swapchain.extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	vk.CmdSetViewport(cmd.handle, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = renderer.ctx.swapchain.extent,
	}

	vk.CmdSetScissor(cmd.handle, 0, 1, &scissor)

	vk.CmdDraw(cmd.handle, 3, 1, 0, 0)
}

@(require_results)
renderer_end_frame :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	frame_end_rendering(renderer.current_frame)

	renderer_flush(renderer) or_return
	frame_manager_advance(&renderer.frame_manager)
	return
}

@(require_results)
renderer_flush :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	vk.EndCommandBuffer(renderer.current_frame.command_buffer.handle) or_return // TODO: probably clean this

	frame_submit(
		renderer.current_frame,
		renderer.ctx.device,
		renderer.ctx.device.graphics_queue,
	) or_return

	present_frame(
		renderer.current_frame,
		renderer.ctx.device.presents_queue,
		&renderer.ctx.swapchain,
	) or_return

	return
}

renderer_handle_resize :: proc(renderer: ^Renderer, allocator := context.allocator) -> vk.Result {
	log.debug("TRIGGERING RESIZE")
	renderer.framebuffer_resized = false
	return handle_resize(&renderer.ctx, renderer.window^, allocator)
}
