package raytracer

import vma "external:odin-vma"
import vk "vendor:vulkan"

Image :: struct {
	handle:     vk.Image,
	allocation: vma.Allocation,
	format:     vk.Format,
	extent:     vk.Extent2D,
}

image_init :: proc(image: ^Image, ctx: ^Vulkan_Context, format: vk.Format, extent: vk.Extent2D) {
	image^ = {}
	image.format = format
	image.extent = extent

	is_depth := is_depth_format(format)

	usage := vk.ImageUsageFlags{.SAMPLED, .TRANSFER_SRC}
	if is_depth {
		usage |= {.DEPTH_STENCIL_ATTACHMENT}
	} else {
		usage |= {.COLOR_ATTACHMENT, .STORAGE}
	}

	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = image.format,
		extent = {width = extent.width, height = extent.height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}

	alloc_info := vma.Allocation_Create_Info {
		usage          = .Gpu_Only,
		required_flags = {.DEVICE_LOCAL},
	}

	_ = vk_check(
		vma.create_image(
			ctx.device.allocator,
			image_info,
			alloc_info,
			&image.handle,
			&image.allocation,
			nil,
		),
		"Failed to create image",
	)
}

image_destroy :: proc(image: ^Image, ctx: Vulkan_Context) {
	vma.destroy_image(ctx.device.allocator, image.handle, nil)
}

image_view_init :: proc(image_view: ^vk.ImageView, image: Image, ctx: ^Vulkan_Context) {
	is_depth := is_depth_format(image.format)
	aspect_mask := is_depth ? vk.ImageAspectFlags{.DEPTH} : vk.ImageAspectFlags{.COLOR}

	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image.handle,
		viewType = .D2,
		format = image.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		subresourceRange = {
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	_ = vk_check(
		vk.CreateImageView(ctx.device.logical_device.ptr, &create_info, nil, image_view),
		"Failed to create ray tracing image view",
	)
}

image_view_destroy :: proc(img_view: vk.ImageView, ctx: Vulkan_Context) {
	vk.DestroyImageView(ctx.device.logical_device.ptr, img_view, nil)
}

image_transition :: proc {
	image_transition_layout_stage_access,
	image_transition_layout,
}

image_transition_layout :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
) {
	src_stage := get_pipeline_stage_flags(old_layout)
	dst_stage := get_pipeline_stage_flags(new_layout)

	src_access := get_access_flags(old_layout)
	dst_access := get_access_flags(new_layout)

	image_transition(
		cmd,
		image,
		old_layout,
		new_layout,
		src_stage,
		dst_stage,
		src_access,
		dst_access,
	)
}

image_transition_layout_stage_access :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
	src_stage, dst_stage: vk.PipelineStageFlags2,
	src_access, dst_access: vk.AccessFlags2,
	format := vk.Format.UNDEFINED,
) {
	aspect_mask := vk.ImageAspectFlags{.COLOR}
	if is_depth_format(format) {
		aspect_mask = {.DEPTH}
	}
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage,
		srcAccessMask = src_access,
		dstStageMask = dst_stage,
		dstAccessMask = dst_access,
		oldLayout = old_layout,
		newLayout = new_layout,
		image = image,
		subresourceRange = {
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dependency_info)
}

@(require_results)
format_to_aspect_mask :: proc(format: vk.Format) -> vk.ImageAspectFlags {
	#partial switch format {
	case .UNDEFINED:
		return {}
	case .R8_UINT:
		return {.STENCIL}
	case .D16_UNORM_S8_UINT, .D24_UNORM_S8_UINT, .D32_SFLOAT_S8_UINT:
		return {.STENCIL, .DEPTH}
	case .D16_UNORM, .D32_SFLOAT, .X8_D24_UNORM_PACK32:
		return {.DEPTH}
	case:
		return {.COLOR}
	}
}

get_pipeline_stage_flags :: proc(layout: vk.ImageLayout) -> vk.PipelineStageFlags2 {
	#partial switch layout {
	case .UNDEFINED:
		return {.TOP_OF_PIPE}
	case .PREINITIALIZED:
		return {.HOST}
	case .TRANSFER_DST_OPTIMAL:
		fallthrough
	case .TRANSFER_SRC_OPTIMAL:
		return {.TRANSFER}
	case .COLOR_ATTACHMENT_OPTIMAL:
		return {.COLOR_ATTACHMENT_OUTPUT}
	case .DEPTH_ATTACHMENT_OPTIMAL:
		return {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}
	case .FRAGMENT_SHADING_RATE_ATTACHMENT_OPTIMAL_KHR:
		return {.FRAGMENT_SHADING_RATE_ATTACHMENT_KHR}
	case .SHADER_READ_ONLY_OPTIMAL:
		return {.VERTEX_SHADER, .FRAGMENT_SHADER}
	case .PRESENT_SRC_KHR:
		return {.BOTTOM_OF_PIPE}
	case .GENERAL:
		assert(
			false,
			"Don't know how to get a meaningful VkPipelineStageFlags for .GENERAL! Don't use it!",
		)
		return {}
	case:
		assert(false)
		return {}
	}
}

get_access_flags :: proc(layout: vk.ImageLayout) -> vk.AccessFlags2 {
	#partial switch layout {
	case .UNDEFINED:
		fallthrough
	case .PRESENT_SRC_KHR:
		return {}
	case .PREINITIALIZED:
		return {.HOST_WRITE}
	case .COLOR_ATTACHMENT_OPTIMAL:
		return {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE}
	case .DEPTH_ATTACHMENT_OPTIMAL:
		return {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}
	case .FRAGMENT_SHADING_RATE_ATTACHMENT_OPTIMAL_KHR:
		return {.FRAGMENT_SHADING_RATE_ATTACHMENT_READ_KHR}
	case .SHADER_READ_ONLY_OPTIMAL:
		return {.SHADER_READ, .INPUT_ATTACHMENT_READ}
	case .TRANSFER_SRC_OPTIMAL:
		return {.TRANSFER_READ}
	case .TRANSFER_DST_OPTIMAL:
		return {.TRANSFER_WRITE}
	case .GENERAL:
		assert(
			false,
			"Don't know how to get a meaningful VkAccessFlags for .GENERAL! Don't use it!",
		)
		return {}
	case:
		assert(false)
		return {}
	}
}

// Helper function to determine if a format is a depth format
is_depth_format :: proc(format: vk.Format) -> bool {
	#partial switch format {
	case .D16_UNORM, .D32_SFLOAT, .D16_UNORM_S8_UINT, .D24_UNORM_S8_UINT, .D32_SFLOAT_S8_UINT:
		return true
	case:
		return false
	}
}
