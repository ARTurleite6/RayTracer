package raytracer

import vk "vendor:vulkan"

Device :: struct {
	handle:         vk.Device,
	graphics_queue: vk.Queue,
	presents_queue: vk.Queue,
}

make_logical_device :: proc(
	physical_device_info: Physical_Device_Info,
) -> (
	device: Device,
	result: vk.Result,
) {
	indices := queue_family_indices(
		physical_device_info.queue_family_indices,
		context.temp_allocator,
	)

	queue_create_infos := make([]vk.DeviceQueueCreateInfo, len(indices), context.temp_allocator)
	for value, i in indices {
		queue_create_infos[i] = vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			pNext            = nil,
			queueFamilyIndex = value,
			queueCount       = 1,
			pQueuePriorities = raw_data([]f32{1}),
		}
	}

	enable_extended_dynamic_state := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType                = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		extendedDynamicState = true,
	}

	enable_vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext            = &enable_extended_dynamic_state,
		synchronization2 = true,
		dynamicRendering = true,
	}

	enable_device_features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &enable_vulkan13_features,
	}

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &enable_device_features2,
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		ppEnabledExtensionNames = raw_data(REQUIRED_EXTENSIONS),
		enabledExtensionCount   = 1,
	}

	vk.CreateDevice(physical_device_info.handle, &create_info, nil, &device.handle) or_return

	vk.load_proc_addresses(device.handle)

	vk.GetDeviceQueue(
		device.handle,
		physical_device_info.queue_family_indices.graphics_family.?,
		0,
		&device.graphics_queue,
	)

	vk.GetDeviceQueue(
		device.handle,
		physical_device_info.queue_family_indices.present_family.?,
		0,
		&device.presents_queue,
	)
	return
}

delete_logical_device :: proc(device: Device) {
	vk.DestroyDevice(device.handle, nil)
}
