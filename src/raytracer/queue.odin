package raytracer

import vk "vendor:vulkan"

Queue_Family_Index :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
}

find_queue_families :: proc(
	device: PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	result: Queue_Family_Index,
) {
	count: u32 = 0
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	queue_families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(queue_families))

	for family, i in queue_families {
		if .GRAPHICS in family.queueFlags {
			result.graphics = u32(i)
		}

		presentation_support: b32
		if vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &presentation_support) !=
		   .SUCCESS {
			panic("failed to check presentation support")
		}

		if presentation_support {
			result.present = u32(i)
		}
	}

	return result
}

@(private)
is_queue_family_index_complete :: proc(queue: Queue_Family_Index) -> bool {
	_, has_graphics := queue.graphics.?
	_, has_present := queue.present.?
	return has_graphics && has_present
}
