package raytracer

import vk "vendor:vulkan"

Swapchain :: struct {
	handle: vk.SwapchainKHR,
	format: vk.SurfaceFormatKHR,
	extent: vk.Extent2D,
}

Swapchain_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

make_swapchain :: proc(
	device: Device,
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	window: Window,
) -> (
	swapchain: Swapchain,
	result: vk.Result,
) {
	swapchain_support_info := get_swapchain_support_details(
		physical_device,
		surface,
		context.temp_allocator,
	)

	capabilities := swapchain_support_info.capabilities

	swapchain.format = choose_format(swapchain_support_info.formats)
	swapchain.extent = choose_extent(capabilities, window)

	image_count := capabilities.minImageCount + 1
	if capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount {
		image_count = capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = image_count,
		imageFormat      = swapchain.format.format,
		imageColorSpace  = swapchain.format.colorSpace,
		imageExtent      = swapchain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT}, // TODO: Assumming that queues are the same
		imageSharingMode = .EXCLUSIVE,
		preTransform     = capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = choose_present_mode(swapchain_support_info.present_modes),
		clipped          = true,
		oldSwapchain     = 0, // TODO: for resizing in here I need to set the old swapchain
	}


	result = vk.CreateSwapchainKHR(device.handle, &create_info, nil, &swapchain.handle)
	return
}

delete_swapchain :: proc(device: Device, swapchain: Swapchain) {
	vk.DestroySwapchainKHR(device.handle, swapchain.handle, nil)
}

@(private = "file")
@(require_results)
get_swapchain_support_details :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
) -> (
	swapchain_support: Swapchain_Support_Details,
) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physical_device,
		surface,
		&swapchain_support.capabilities,
	)

	{ 	// formats
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, nil)
		swapchain_support.formats = make([]vk.SurfaceFormatKHR, int(count), allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			physical_device,
			surface,
			&count,
			raw_data(swapchain_support.formats),
		)
	}

	{ 	// present_modes
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, nil)
		swapchain_support.present_modes = make([]vk.PresentModeKHR, int(count), allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			physical_device,
			surface,
			&count,
			raw_data(swapchain_support.present_modes),
		)
	}

	return
}

@(private = "file")
@(require_results)
choose_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for f in formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			return f
		}
	}
	return formats[0]
}

@(private = "file")
@(require_results)
choose_extent :: proc(capabilities: vk.SurfaceCapabilitiesKHR, window: Window) -> vk.Extent2D {
	if capabilities.currentExtent.height != max(u32) {
		return capabilities.currentExtent
	}

	width, height := window_get_framebuffer_size(window)

	return {
		width = clamp(
			u32(width),
			capabilities.minImageExtent.width,
			capabilities.maxImageExtent.width,
		),
		height = clamp(
			u32(height),
			capabilities.minImageExtent.height,
			capabilities.maxImageExtent.height,
		),
	}
}


@(private = "file")
@(require_results)
choose_present_mode :: proc(present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	for p in present_modes {
		if p == .MAILBOX {
			return p
		}
	}

	return .FIFO
}
