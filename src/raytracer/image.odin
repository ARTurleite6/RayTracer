package raytracer

import vma "external:odin-vma"
import vk "vendor:vulkan"

Image :: struct {
	handle:     vk.Image,
	allocation: vma.Allocation,
	format:     vk.Format,
}

image_init :: proc(image: ^Image, ctx: ^Vulkan_Context, format: vk.Format, extent: vk.Extent2D) {
	image.format = .B8G8R8A8_UNORM
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = .B8G8R8A8_UNORM,
		extent = {width = extent.width, height = extent.height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = {.STORAGE, .TRANSFER_SRC},
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
	image^ = {}
}

image_view_init :: proc(image_view: ^vk.ImageView, image: Image, ctx: ^Vulkan_Context) {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image.handle,
		viewType = .D2,
		format = image.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		subresourceRange = {
			aspectMask = {.COLOR},
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

	// cmd := device_begin_single_time_commands(ctx.device, ctx.device.command_pool)
	// defer device_end_single_time_commands(ctx.device, ctx.device.command_pool, cmd)

	// image_transition(
	// 	cmd,
	// 	image = image.handle,
	// 	old_layout = .UNDEFINED,
	// 	new_layout = .GENERAL,
	// 	src_access = {},
	// 	dst_access = {},
	// 	src_stage = {.ALL_COMMANDS},
	// 	dst_stage = {.ALL_COMMANDS},
	// )
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
) {
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
			aspectMask = {.COLOR},
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
