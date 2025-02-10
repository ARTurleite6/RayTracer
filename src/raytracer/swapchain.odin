package raytracer

import "core:slice"
import vk "vendor:vulkan"

Swapchain :: struct {
	handle:       vk.SwapchainKHR,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
	framebuffers: []Framebuffer,
	format:       vk.Format,
	extent:       vk.Extent2D,
}

Swapchain_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

swapchain_init :: proc(
	swapchain: ^Swapchain,
	device: vk.Device,
	physical_device: PhysicalDevice,
	surface: vk.SurfaceKHR,
	window: Window,
	graphics_queues_families: Queue_Family_Index,
	allocator := context.allocator,
) -> vk.Result {
	swapchain_support := query_swapchain_support(physical_device, surface, context.temp_allocator)
	assert(
		len(swapchain_support.formats) > 0,
		"Vulkan: Swapchain does not have any available formats",
	)
	assert(
		len(swapchain_support.present_modes) > 0,
		"Vulkan: Swapchain does not have any available present modes",
	)

	selected_format := choose_format(swapchain_support.formats)

	selected_present_mode := choose_present_mode(swapchain_support.present_modes)

	swapchain.format = selected_format.format
	swapchain.extent = choose_extent(swapchain_support.capabilities, window)

	{ 	// creating swapchain
		image_count := swapchain_support.capabilities.minImageCount + 1
		if swapchain_support.capabilities.maxImageCount > 0 {
			image_count = min(image_count, swapchain_support.capabilities.maxImageCount)
		}
		create_info := vk.SwapchainCreateInfoKHR {
			sType            = .SWAPCHAIN_CREATE_INFO_KHR,
			surface          = surface,
			minImageCount    = image_count,
			imageFormat      = selected_format.format,
			imageColorSpace  = selected_format.colorSpace,
			imageExtent      = swapchain.extent,
			imageArrayLayers = 1,
			imageUsage       = {.COLOR_ATTACHMENT},
			preTransform     = swapchain_support.capabilities.currentTransform,
			compositeAlpha   = {.OPAQUE},
			presentMode      = selected_present_mode,
			clipped          = true,
		}


		if graphics_queues_families.graphics.? != graphics_queues_families.present.? {
			create_info.imageSharingMode = .CONCURRENT
			create_info.queueFamilyIndexCount = 2
			create_info.pQueueFamilyIndices = raw_data(
				[]u32{graphics_queues_families.graphics.?, graphics_queues_families.present.?},
			)
		} else {
			create_info.imageSharingMode = .EXCLUSIVE
			create_info.queueFamilyIndexCount = 0
			create_info.pQueueFamilyIndices = nil
		}

		if result := vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain.handle);
		   result != .SUCCESS {
			return result
		}
	}

	{ 	// get images
		count: u32
		vk.GetSwapchainImagesKHR(device, swapchain.handle, &count, nil)
		swapchain.images = make([]vk.Image, count, allocator)
		vk.GetSwapchainImagesKHR(device, swapchain.handle, &count, raw_data(swapchain.images))
	}

	{ 	// create image views
		swapchain.image_views = make([]vk.ImageView, len(swapchain.images), allocator)
		for img, i in swapchain.images {
			create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = img,
				viewType = .D2,
				format = swapchain.format,
				components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
				subresourceRange = {
					aspectMask = {.COLOR},
					baseMipLevel = 0,
					levelCount = 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
			}
			if result := vk.CreateImageView(device, &create_info, nil, &swapchain.image_views[i]);
			   result != .SUCCESS {
				return result
			}
		}
	}

	return .SUCCESS
}

swapchain_init_framebuffers :: proc(
	swapchain: ^Swapchain,
	device: Device,
	render_pass: vk.RenderPass,
	allocator := context.allocator,
) -> vk.Result {
	swapchain.framebuffers = make([]Framebuffer, len(swapchain.image_views), allocator)
	for image, i in swapchain.image_views {
		if result := framebuffer_init(
			&swapchain.framebuffers[i],
			device,
			render_pass,
			swapchain.extent,
			image,
		); result != .SUCCESS {
			return result
		}
	}

	return .SUCCESS
}

swapchain_destroy :: proc(swapchain: Swapchain, device: Device) {
	for framebuffer in swapchain.framebuffers {
		vk.DestroyFramebuffer(device, framebuffer, nil)
	}
	delete(swapchain.framebuffers)

	for image_view in swapchain.image_views {
		vk.DestroyImageView(device, image_view, nil)
	}

	delete(swapchain.image_views)
	delete(swapchain.images)

	vk.DestroySwapchainKHR(device, swapchain.handle, nil)
}

@(require_results)
swapchain_acquire_next_image :: proc(
	swapchain: Swapchain,
	device: Device,
	semaphore: Semaphore,
	fence: Fence = 0,
) -> (
	image_index: u32,
	result: vk.Result,
) {
	result = vk.AcquireNextImageKHR(
		device,
		swapchain.handle,
		max(u64),
		semaphore,
		fence,
		&image_index,
	)

	return
}

@(require_results)
query_swapchain_support :: proc(
	physical_device: PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
) -> (
	details: Swapchain_Support_Details,
) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &details.capabilities)
	{ 	// formats
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, nil)
		details.formats = make([]vk.SurfaceFormatKHR, count, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			physical_device,
			surface,
			&count,
			raw_data(details.formats),
		)
	}

	{ 	// present modes
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, nil)
		details.present_modes = make([]vk.PresentModeKHR, count, allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			physical_device,
			surface,
			&count,
			raw_data(details.present_modes),
		)
	}
	return
}

@(private)
@(require_results)
choose_present_mode :: proc(present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	if selected, found := slice.linear_search(present_modes, vk.PresentModeKHR.MAILBOX); found {
		return present_modes[selected]
	}
	return .FIFO
}

@(private)
@(require_results)
choose_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	result, found := slice.linear_search_proc(formats, proc(format: vk.SurfaceFormatKHR) -> bool {
			return format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR
		})
	assert(found, "Vulkan: No format found")
	return formats[result]
}

@(private)
@(require_results)
choose_extent :: proc(
	capabilites: vk.SurfaceCapabilitiesKHR,
	window: Window,
) -> (
	extent: vk.Extent2D,
) {
	if capabilites.currentExtent.width != max(u32) {
		return capabilites.currentExtent
	}
	width, height := window_get_framebuffer_size(window)

	extent.width = clamp(
		u32(width),
		capabilites.minImageExtent.width,
		capabilites.maxImageExtent.width,
	)
	extent.height = clamp(
		u32(height),
		capabilites.minImageExtent.height,
		capabilites.maxImageExtent.height,
	)

	return
}
