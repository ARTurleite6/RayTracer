package raytracer

import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"

Swapchain_Manager :: struct {
	device:        ^Device,
	handle:        ^vkb.Swapchain,
	surface:       vk.SurfaceKHR,
	images:        []vk.Image,
	image_views:   []vk.ImageView,
	extent:        vk.Extent2D,
	format:        vk.Format,
	present_mode:  vk.PresentModeKHR,
	current_image: u32,
}

Swapchain_Config :: struct {
	extent:         vk.Extent2D,
	preferred_mode: vk.PresentModeKHR,
	vsync:          bool,
}

Swapchain_Error :: enum {
	None = 0,
	Creation_Failed,
	Image_Acquisition_Failed,
	Image_View_Creation_Failed,
	Invalid_Surface,
	Out_Of_Date,
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

	if create_err := swapchain_init(manager, config, allocator); create_err != .None {
		// TODO: DESTROY swapchain
		return create_err
	}

	return .None
}

@(private)
swapchain_init :: proc(
	manager: ^Swapchain_Manager,
	config: Swapchain_Config,
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

	return .None
}

swapchain_manager_destroy :: proc(manager: ^Swapchain_Manager) {
	vkb.swapchain_destroy_image_views(manager.handle, manager.image_views)
	vkb.destroy_swapchain(manager.handle)
}

swapchain_recreate :: proc(
	manager: ^Swapchain_Manager,
	new_width, new_height: u32,
	allocator := context.allocator,
) -> Swapchain_Error {
	vk.DeviceWaitIdle(manager.device.logical_device.ptr)

	old_swapchain := manager.handle
	defer if old_swapchain != nil {
		vkb.swapchain_destroy_image_views(old_swapchain, manager.image_views)
		delete(manager.images)
		delete(manager.image_views)
		vkb.destroy_swapchain(old_swapchain)
	}

	config := Swapchain_Config {
		extent = {width = new_width, height = new_height},
		preferred_mode = manager.present_mode,
		vsync = manager.present_mode == .FIFO,
	}

	if err := swapchain_init(manager, config, allocator); err != .None {
		return err
	}

	return .None
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
	res := vk.AcquireNextImageKHR(
		manager.device.logical_device.ptr,
		manager.handle.ptr,
		timeout,
		semaphore,
		0,
		&result.image_index,
	)

	#partial switch res {
	case .SUCCESS:
		manager.current_image = result.image_index
		return result, .None
	case .SUBOPTIMAL_KHR:
		result.suboptimal = true
		return result, .None
	case .ERROR_OUT_OF_DATE_KHR:
		return {}, .Out_Of_Date
	case:
		return {}, .Image_Acquisition_Failed
	}

	return
}
