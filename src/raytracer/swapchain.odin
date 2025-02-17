package raytracer

import vk "vendor:vulkan"

Swapchain :: struct {
	handle:      vk.SwapchainKHR,
	images:      []vk.Image,
	image_views: []vk.ImageView,
	format:      vk.SurfaceFormatKHR,
	extent:      vk.Extent2D,
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
	allocator := context.allocator,
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

	vk.CreateSwapchainKHR(device.handle, &create_info, nil, &swapchain.handle) or_return

	{ 	// get swapchain images
		count: u32
		vk.GetSwapchainImagesKHR(device.handle, swapchain.handle, &count, nil) or_return
		swapchain.images = make([]vk.Image, count, allocator)
		vk.GetSwapchainImagesKHR(
			device.handle,
			swapchain.handle,
			&count,
			raw_data(swapchain.images),
		) or_return
	}

	swapchain.image_views = make_image_views(
		device,
		swapchain.images,
		swapchain.format.format,
		allocator,
	) or_return

	return
}

delete_swapchain :: proc(swapchain: Swapchain, device: Device) {
	for img in swapchain.image_views {
		vk.DestroyImageView(device.handle, img, nil)
	}

	vk.DestroySwapchainKHR(device.handle, swapchain.handle, nil)
}

@(private = "file")
@(require_results)
make_image_views :: proc(
	device: Device,
	images: []vk.Image,
	format: vk.Format,
	allocator := context.allocator,
) -> (
	image_views: []vk.ImageView,
	result: vk.Result,
) {
	image_views = make([]vk.ImageView, len(images), allocator)

	for img, i in images {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = img,
			viewType = .D2,
			format = format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		vk.CreateImageView(device.handle, &create_info, nil, &image_views[i]) or_return
	}

	return
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
