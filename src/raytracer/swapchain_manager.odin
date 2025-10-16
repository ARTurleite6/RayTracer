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

	manager^ = {}
	manager.device = device
	manager.surface = surface
	return swapchain_init(manager, config, resizing = false, allocator = allocator)
}

@(private)
swapchain_init :: proc(
	manager: ^Swapchain_Manager,
	config: Swapchain_Config,
	resizing: bool,
	allocator := context.allocator,
) -> Swapchain_Error {
	context.allocator = allocator
	builder, ok := vkb.init_swapchain_builder(manager.device.logical_device)
	if !ok {
		return .Creation_Failed
	}
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})
	defer vkb.destroy_swapchain_builder(&builder)

	// Save old swapchain for cleanup
	old_swapchain := manager.handle
	old_images := manager.images
	old_image_views := manager.image_views

	vkb.swapchain_builder_set_old_swapchain(&builder, old_swapchain)
	vkb.swapchain_builder_set_desired_extent(&builder, config.extent.width, config.extent.height)
	vkb.swapchain_builder_use_default_format_selection(&builder)

	if config.vsync {
		vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	} else {
		vkb.swapchain_builder_set_present_mode(&builder, config.preferred_mode)
	}

	// Build new swapchain
	ok = false
	if manager.handle, ok = vkb.build_swapchain(&builder); !ok {
		return .Creation_Failed
	}

	// Get new images and views
	ok = false
	if manager.images, ok = vkb.swapchain_get_images(manager.handle, allocator = allocator); !ok {
		// Clean up the new swapchain we just created
		vkb.destroy_swapchain(manager.handle)
		manager.handle = old_swapchain
		return .Image_Acquisition_Failed
	}

	if manager.image_views, ok = vkb.swapchain_get_image_views(
		manager.handle,
		allocator = allocator,
	); !ok {
		// Clean up what we've created
		delete(manager.images, allocator)
		vkb.destroy_swapchain(manager.handle)
		manager.handle = old_swapchain
		return .Image_View_Creation_Failed
	}

	// Now that new swapchain is successfully created, clean up old resources
	if resizing && old_swapchain != nil {
		vkb.swapchain_destroy_image_views(old_swapchain, old_image_views)
		delete(old_image_views, allocator)
		delete(old_images, allocator)
		vkb.destroy_swapchain(old_swapchain)
	}

	manager.extent = manager.handle.extent
	manager.format = manager.handle.image_format
	manager.present_mode = manager.handle.present_mode

	return nil
}

swapchain_manager_destroy :: proc(manager: ^Swapchain_Manager) {
	vkb.swapchain_destroy_image_views(manager.handle, manager.image_views)
	vkb.destroy_swapchain(manager.handle)

	vk.DestroySurfaceKHR(manager.device.instance.ptr, manager.surface, nil)
	delete(manager.images)
	delete(manager.image_views)
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
