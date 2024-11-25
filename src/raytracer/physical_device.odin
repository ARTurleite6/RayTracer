package raytracer

// import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"

PhysicalDevice :: vk.PhysicalDevice

physical_device_init :: proc(
	device: ^PhysicalDevice,
	instance: Instance,
	surface: vk.SurfaceKHR,
	temp_allocator: mem.Allocator,
) {
	num_devices: u32
	vk.EnumeratePhysicalDevices(instance, &num_devices, nil)
	physical_devices := make([]PhysicalDevice, num_devices, temp_allocator)
	vk.EnumeratePhysicalDevices(instance, &num_devices, raw_data(physical_devices))

	high_score: uint = 0
	for d in physical_devices {
		score := rate_device(d, surface, temp_allocator)
		if score > high_score {
			high_score = score
			device^ = d
		}
	}
	assert(high_score > 0, "No suitable device to choose")
}

@(private = "file")
rate_device :: proc(
	device: PhysicalDevice,
	surface: vk.SurfaceKHR,
	temp_allocator: mem.Allocator,
) -> uint {
	features: vk.PhysicalDeviceFeatures
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &properties)
	vk.GetPhysicalDeviceFeatures(device, &features)

	log.infof("vulkan: rating device %s", properties.deviceName)

	family_indexes := find_queue_families(device, surface, temp_allocator)

	swapchain_capabilities := query_swapchain_support(device, surface, temp_allocator)
	if !is_device_suitable(device, family_indexes, swapchain_capabilities, temp_allocator) do return 0

	rate: uint = 0
	switch properties.deviceType {
	case .DISCRETE_GPU:
		rate = 3000
	case .INTEGRATED_GPU:
		rate = 2000
	case .VIRTUAL_GPU:
		rate = 1000
	case .CPU, .OTHER:
		rate = 0
	}

	log.infof(
		"vulkan: device %s received score of %d for being of type %v",
		properties.deviceName,
		rate,
		properties.deviceType,
	)

	log.infof(
		"vulkan: device %s received more %d points for its max image dimension limit",
		properties.deviceName,
		properties.limits.maxImageDimension2D,
	)
	rate += uint(properties.limits.maxImageDimension2D)

	log.infof("vulkan: device %s got total rate count of %d", properties.deviceName, rate)
	return rate
}

@(private)
is_device_suitable :: proc(
	physical_device: PhysicalDevice,
	queue_familiy_index: Queue_Family_Index,
	swapchain_capabilities: Swapchain_Support_Details,
	temp_allocator: mem.Allocator,
) -> bool {
	return(
		is_queue_family_index_complete(queue_familiy_index) &&
		len(swapchain_capabilities.formats) > 0 &&
		len(swapchain_capabilities.present_modes) > 0 &&
		check_device_extension_support(physical_device, temp_allocator) \
	)
}

@(private)
check_device_extension_support :: proc(
	device: PhysicalDevice,
	temp_allocator: mem.Allocator,
) -> bool {
	extension_count: u32 = 0
	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)
	available_extensions := make([]vk.ExtensionProperties, extension_count, temp_allocator)
	vk.EnumerateDeviceExtensionProperties(
		device,
		nil,
		&extension_count,
		raw_data(available_extensions),
	)

	for ext in DEVICE_EXTENSIONS {
		found := false
		for device_ext in available_extensions {
			ext_name := device_ext.extensionName
			if strings.truncate_to_byte(string(ext), 0) ==
			   strings.truncate_to_byte(string(ext_name[:]), 0) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	return true
}
