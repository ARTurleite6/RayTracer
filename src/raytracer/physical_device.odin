package raytracer

import "core:container/small_array"
import "core:log"
import "core:slice"
import vk "vendor:vulkan"

Physical_Device_Info :: struct {
	handle:               vk.PhysicalDevice,
	queue_family_indices: Queue_Family_Indices,
	features:             vk.PhysicalDeviceFeatures,
	properties:           vk.PhysicalDeviceProperties,
}

Queue_Family_Indices :: struct {
	graphics_family: Maybe(u32),
	present_family:  Maybe(u32),
}

Rating_Device_Result :: struct {
	queue_family_indices: Queue_Family_Indices,
	features:             vk.PhysicalDeviceFeatures,
	properties:           vk.PhysicalDeviceProperties,
	rate:                 u32,
}

@(require_results)
choose_physical_device :: proc(
	instance: Instance,
	surface: vk.SurfaceKHR,
) -> (
	device: Physical_Device_Info,
	result: vk.Result,
) {
	num_devices: u32
	vk.EnumeratePhysicalDevices(instance, &num_devices, nil) or_return
	physical_devices := make([]vk.PhysicalDevice, num_devices, context.temp_allocator)
	vk.EnumeratePhysicalDevices(instance, &num_devices, raw_data(physical_devices)) or_return

	high_score: u32 = 0

	for d in physical_devices {
		rate_result := rate_device(d, surface)
		if rate_result.rate > high_score {
			device = Physical_Device_Info {
				handle               = d,
				queue_family_indices = rate_result.queue_family_indices,
				properties           = rate_result.properties,
				features             = rate_result.features,
			}
			high_score = rate_result.rate
		}
	}

	assert(high_score > 0, "No suitable device was found")

	log.infof("Vulkan: device %s selected", device.properties.deviceName)
	return
}

@(private = "file")
@(require_results)
rate_device :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	result: Rating_Device_Result,
) {
	vk.GetPhysicalDeviceFeatures(device, &result.features)
	vk.GetPhysicalDeviceProperties(device, &result.properties)

	log.infof("Vulkan: rating device %s", result.properties.deviceName)

	queue_family_indices, _ := get_queue_family_indices(device, surface)
	if !is_device_suitable(device, queue_family_indices) do return {}
	result.queue_family_indices = queue_family_indices

	switch result.properties.deviceType {
	case .DISCRETE_GPU:
		result.rate = 3000
	case .INTEGRATED_GPU:
		result.rate = 2000
	case .VIRTUAL_GPU:
		result.rate = 1000
	case .CPU, .OTHER:
		result.rate = 0
	}

	log.infof(
		"Vulkan: device %s received score of %d for being of type %v",
		result.properties.deviceName,
		result.rate,
		result.properties.deviceType,
	)

	result.rate += result.properties.limits.maxImageDimension2D

	log.infof(
		"Vulkan: device %s received more %d points for its max image dimension limit",
		result.properties.deviceName,
		result.properties.limits.maxImageDimension2D,
	)

	log.infof(
		"Vulkan: device %s got total rate count of %d",
		result.properties.deviceName,
		result.rate,
	)
	return result
}

@(private = "file")
@(require_results)
get_queue_family_indices :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	queue_families: Queue_Family_Indices,
	result: vk.Result,
) {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)
	queue_families_arr := make(
		[]vk.QueueFamilyProperties,
		queue_family_count,
		context.temp_allocator,
	)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		device,
		&queue_family_count,
		raw_data(queue_families_arr),
	)

	for q, i in queue_families_arr do if !queue_family_indices_complete(queue_families) {
		u32_i := u32(i)
		if .GRAPHICS in q.queueFlags {
			queue_families.graphics_family = u32_i
		}

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32_i, surface, &present_support) or_return
		if present_support {
			queue_families.present_family = u32_i
		}
	}

	return
}

@(require_results)
queue_family_indices :: proc(q: Queue_Family_Indices) -> []u32 {
	arr: small_array.Small_Array(2, u32)

	if value, ok := q.graphics_family.?; ok {
		small_array.append(&arr, value)
	}

	if value, ok := q.present_family.?; ok {
		small_array.append(&arr, value)
	}

	return slice.unique(small_array.slice(&arr))
}

@(private = "file")
@(require_results)
queue_family_indices_complete :: proc(q: Queue_Family_Indices) -> bool {
	return q.graphics_family != nil && q.present_family != nil
}

@(private = "file")
@(require_results)
is_device_suitable :: proc(_device: vk.PhysicalDevice, q: Queue_Family_Indices) -> bool {
	return queue_family_indices_complete(q)
}
