package raytracer

import vk "vendor:vulkan"

Physical_Device :: vk.PhysicalDevice

@(require_results)
choose_physical_device :: proc(instance: Instance) -> (device: Physical_Device, result: vk.Result) {
    num_devices: u32
    vk.EnumeratePhysicalDevices(instance, &num_devices, nil) or_return
    physical_devices := make([]Physical_Device, num_devices, context.temp_allocator)
    vk.EnumeratePhysicalDevices(instance, &num_devices, raw_data(physical_devices)) or_return

    high_score: u32 = 0

    for d in physical_devices {
        score := rate_device(d)
        if score > high_score {
            device = d
            high_score = score
        }
    }

    assert(high_score > 0, "No suitable device was found")
    return
}

@(private = "file")
rate_device :: proc(
    device: Physical_Device,
) -> u32 {
    return 0
}
