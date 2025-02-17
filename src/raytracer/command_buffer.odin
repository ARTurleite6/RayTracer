package raytracer

import vk "vendor:vulkan"

Command_Buffer :: struct {
	name:   string,
	handle: vk.CommandBuffer,
}

@(require_results)
command_buffer_begin :: proc(command_buffer: Command_Buffer) -> vk.Result {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	return vk.BeginCommandBuffer(command_buffer.handle, &begin_info)
}

command_buffer_end_rendering :: proc(command_buffer: Command_Buffer) {
	vk.CmdEndRendering(command_buffer.handle)
}

command_buffer_begin_rendering :: proc(
	command_buffer: Command_Buffer,
	image_view: vk.ImageView,
	extent: vk.Extent2D,
	clear_color: vk.ClearValue,
) {
	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_color,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(command_buffer.handle, &rendering_info)
}

command_buffer_reset :: proc(command_buffer: Command_Buffer) {
	vk.ResetCommandBuffer(command_buffer.handle, {.RELEASE_RESOURCES})
}
