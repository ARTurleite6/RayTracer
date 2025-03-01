package raytracer

import "core:fmt"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"
_ :: fmt

Swapchain_Manager :: struct {
	device:       ^Device,
	handle:       ^vkb.Swapchain,
	surface:      vk.SurfaceKHR,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
	extent:       vk.Extent2D,
	format:       vk.Format,
	present_mode: vk.PresentModeKHR,
}

Swapchain_Config :: struct {
	extent:         vk.Extent2D,
	preferred_mode: vk.PresentModeKHR,
	vsync:          bool,
}

Swapchain_Error :: union {
	Swapchain_Specific_Error,
	Frame_Error,
}

Swapchain_Specific_Error :: enum {
	None = 0,
	Creation_Failed,
	Image_Acquisition_Failed,
	Image_View_Creation_Failed,
	Invalid_Surface,
	Out_Of_Date,
	Suboptimal_Surface,
}

Image_Transition :: struct {
	image:      vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	src_stage:  vk.PipelineStageFlags2,
	dst_stage:  vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	dst_access: vk.AccessFlags2,
}

swapchain_manager_init :: proc(
	manager: ^Swapchain_Manager,
	device: ^Device,
	surface: vk.SurfaceKHR,
	config: Swapchain_Config,
	allocator := context.allocator,
) -> (
	err: Swapchain_Error,
) {
	if surface == 0 {
		return .Invalid_Surface
	}

	manager.device = device
	manager.surface = surface

	if create_err := swapchain_init(manager, config, resizing = false, allocator = allocator);
	   create_err != nil {
		// TODO: DESTROY swapchain
		return create_err
	}

	return nil
}

@(private)
swapchain_init :: proc(
	manager: ^Swapchain_Manager,
	config: Swapchain_Config,
	resizing: bool,
	allocator := context.allocator,
) -> Swapchain_Error {
	builder, ok := vkb.init_swapchain_builder(manager.device.logical_device)
	if !ok {
		return .Creation_Failed
	}

	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_old_swapchain(&builder, manager.handle)
	vkb.swapchain_builder_set_desired_extent(&builder, config.extent.width, config.extent.height)
	vkb.swapchain_builder_use_default_format_selection(&builder)

	if config.vsync {
		vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	} else {
		vkb.swapchain_builder_set_present_mode(&builder, config.preferred_mode)
	}

	ok = false
	if manager.handle, ok = vkb.build_swapchain(&builder); !ok {
		return .Creation_Failed
	}

	ok = false

	if manager.images, ok = vkb.swapchain_get_images(manager.handle, allocator = allocator); !ok {
		return .Image_Acquisition_Failed
	}

	if manager.image_views, ok = vkb.swapchain_get_image_views(
		manager.handle,
		allocator = allocator,
	); !ok {
		return .Image_View_Creation_Failed
	}

	manager.extent = manager.handle.extent
	manager.format = manager.handle.image_format
	manager.present_mode = manager.handle.present_mode
	return nil
}

swapchain_manager_destroy :: proc(manager: ^Swapchain_Manager) {
	vkb.swapchain_destroy_image_views(manager.handle, manager.image_views)
	vkb.destroy_swapchain(manager.handle)
	delete(manager.images)
	delete(manager.image_views)

	manager^ = {}
}

swapchain_recreate :: proc(
	manager: ^Swapchain_Manager,
	new_width, new_height: u32,
	allocator := context.allocator,
) -> (
	err: Swapchain_Error,
) {
	old_swapchain := manager.handle
	old_images := manager.images
	old_image_views := manager.image_views
	defer if old_swapchain != nil {
		vkb.swapchain_destroy_image_views(old_swapchain, old_image_views)
		delete(old_images)
		delete(old_image_views)
		vkb.destroy_swapchain(old_swapchain)
	}

	config := Swapchain_Config {
		extent = {width = new_width, height = new_height},
		preferred_mode = manager.present_mode,
		vsync = manager.present_mode == .FIFO,
	}

	if err = swapchain_init(manager, config, resizing = true, allocator = allocator); err != nil {
		return err
	}

	return nil
}

Acquire_Result :: struct {
	image_index: u32,
	suboptimal:  bool,
}

swapchain_acquire_next_image :: proc(
	manager: ^Swapchain_Manager,
	semaphore: vk.Semaphore,
	timeout := max(u64),
) -> (
	result: Acquire_Result,
	err: Swapchain_Error,
) {
	res := vk_check(
		vk.AcquireNextImageKHR(
			manager.device.logical_device.ptr,
			manager.handle.ptr,
			timeout,
			semaphore,
			0,
			&result.image_index,
		),
		"Failed to acquire next image",
	)

	#partial switch res {
	case .SUCCESS:
		return result, nil
	case .SUBOPTIMAL_KHR:
		result.suboptimal = true
		return result, nil
	case .ERROR_OUT_OF_DATE_KHR:
		return {}, .Out_Of_Date
	case:
		return {}, .Image_Acquisition_Failed
	}

	return
}

image_transition :: proc(cmd: vk.CommandBuffer, transition: Image_Transition) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = transition.src_stage,
		srcAccessMask = transition.src_access,
		dstStageMask = transition.dst_stage,
		dstAccessMask = transition.dst_access,
		oldLayout = transition.old_layout,
		newLayout = transition.new_layout,
		image = transition.image,
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
