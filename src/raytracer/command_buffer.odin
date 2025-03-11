package raytracer

import vk "vendor:vulkan"

Command_Buffer :: struct {
	buffer: vk.CommandBuffer,
}

command_buffer_bind_pipeline :: proc(
	cmd: ^Command_Buffer,
	bind_point: vk.PipelineBindPoint,
	pipeline: vk.Pipeline,
) {
	vk.CmdBindPipeline(cmd.buffer, bind_point, pipeline)
}

command_buffer_begin_render_pass :: proc(cmd: ^Command_Buffer, rendering_info: ^vk.RenderingInfo) {
	vk.CmdBeginRendering(cmd.buffer, rendering_info)

	viewport := vk.Viewport {
		minDepth = 0,
		maxDepth = 1,
		width    = f32(rendering_info.renderArea.extent.width),
		height   = f32(rendering_info.renderArea.extent.height),
	}

	scissor := vk.Rect2D {
		extent = rendering_info.renderArea.extent,
	}

	vk.CmdSetViewport(cmd.buffer, 0, 1, &viewport)
	vk.CmdSetScissor(cmd.buffer, 0, 1, &scissor)
}

command_buffer_end_render_pass :: proc(cmd: ^Command_Buffer) {
	vk.CmdEndRendering(cmd.buffer)
}
