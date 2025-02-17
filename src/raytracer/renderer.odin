package raytracer

import "core:fmt"
import vk "vendor:vulkan"
_ :: fmt

Renderer :: struct {
	ctx:           ^Context,
	frame_manager: Frame_Manager,
	current_frame: ^Per_Frame,
	cmd:           Command_Buffer, // TODO: review this
}

make_renderer :: proc(
	ctx: ^Context,
	allocator := context.allocator,
) -> (
	renderer: Renderer,
	result: vk.Result,
) {
	renderer.ctx = ctx
	renderer.frame_manager = make_frame_manager(ctx.device, allocator) or_return
	return
}

@(require_results)
renderer_begin_frame :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	should_resize: bool
	renderer.current_frame, should_resize = frame_manager_begin(
		&renderer.frame_manager,
		renderer.ctx.device,
		renderer.ctx.swapchain,
	) or_return

	if should_resize {
	}

	renderer.cmd = renderer.current_frame.command_buffer
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
	vk.EndCommandBuffer(renderer.cmd.handle) or_return // TODO: probably clean this

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
