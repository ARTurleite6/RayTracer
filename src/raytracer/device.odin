package raytracer

import "core:slice"
import vk "vendor:vulkan"

when ODIN_OS == .Darwin {
	DEVICE_EXTENSIONS :: []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME, "VK_KHR_portability_subset"}
} else {
	DEVICE_EXTENSIONS :: []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
}

Device :: vk.Device

device_init :: proc(
	device: ^Device,
	physical_device: PhysicalDevice,
	surface: vk.SurfaceKHR,
	queues_families: Queue_Family_Index,
) -> (
	result: vk.Result,
) {
	indices := []u32{queues_families.graphics.?, queues_families.present.?}
	unique_indices := slice.unique(indices)
	queue_create_infos := make(
		[]vk.DeviceQueueCreateInfo,
		len(unique_indices),
		context.temp_allocator,
	)

	for indice, i in unique_indices {
		queue_create_infos[i] = vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = indice,
			queueCount       = 1,
			pQueuePriorities = raw_data([]f32{1}),
		}
	}


	query_vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}

	query_device_features := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &query_vulkan13_features,
	}

	vk.GetPhysicalDeviceFeatures2(physical_device, &query_device_features)

	assert(
		bool(query_vulkan13_features.dynamicRendering),
		"Vulkan: GPU does not support dynamic rendering",
	)

	vk13_features := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
	}

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		pNext                   = &vk13_features,
	}

	return vk.CreateDevice(physical_device, &create_info, nil, device)
}

device_destroy :: proc(device: Device) {
	vk.DestroyDevice(device, nil)
}
