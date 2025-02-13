package raytracer

import vk "vendor:vulkan"

Device :: vk.Device

make_logical_device :: proc(
	physical_device_info: Physical_Device_Info,
) -> (
	device: Device,
	result: vk.Result,
) {
	indices := queue_family_indices(physical_device_info.queue_family_indices)

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

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = nil, // TODO: add vulkan new features from 1.3
		queueCreateInfoCount    = u32(len(queue_create_infos)),
		pQueueCreateInfos       = raw_data(queue_create_infos),
		ppEnabledExtensionNames = raw_data([]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}),
		enabledExtensionCount   = 1,
	}

	result = vk.CreateDevice(physical_device_info.handle, &create_info, nil, &device)

	return
}
