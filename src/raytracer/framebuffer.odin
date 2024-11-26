package raytracer

import vk "vendor:vulkan"

Framebuffer :: vk.Framebuffer

@(require_results)
framebuffer_init :: proc(
	framebuffer: ^Framebuffer,
	device: Device,
	render_pass: vk.RenderPass,
	extent: vk.Extent2D,
	image_view: vk.ImageView,
) -> vk.Result {
	create_info := vk.FramebufferCreateInfo {
		sType           = .FRAMEBUFFER_CREATE_INFO,
		renderPass      = render_pass,
		attachmentCount = 1,
		pAttachments    = raw_data([]vk.ImageView{image_view}),
		width           = extent.width,
		height          = extent.height,
		layers          = 1,
	}

	if result := vk.CreateFramebuffer(device, &create_info, nil, framebuffer); result != .SUCCESS {
		return result
	}

	return .SUCCESS
}

framebuffer_destroy :: proc(framebuffer: Framebuffer, device: Device) {
	vk.DestroyFramebuffer(device, framebuffer, nil)
}
