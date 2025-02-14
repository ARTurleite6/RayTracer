package raytracer

import vk "vendor:vulkan"

Instance :: vk.Instance

@(require_results)
make_instance :: proc(
	app_name: cstring,
	required_extensions: []cstring,
	messenger_create_info: ^vk.DebugUtilsMessengerCreateInfoEXT = nil,
) -> (
	instance: Instance,
	result: vk.Result,
) {
	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pNext                   = nil,
		pApplicationInfo        = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pNext = nil,
			pApplicationName = app_name,
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "No Engine",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_4,
		},
		enabledLayerCount       = 0,
		ppEnabledLayerNames     = nil,
		enabledExtensionCount   = u32(len(required_extensions)),
		ppEnabledExtensionNames = raw_data(required_extensions),
	}

	when ODIN_DEBUG {
		create_info.pNext = messenger_create_info
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1
	}

	vk.CreateInstance(&create_info, nil, &instance) or_return

	vk.load_proc_addresses(instance)

	return instance, result
}

delete_instance :: proc(instance: Instance) {
	vk.DestroyInstance(instance, nil)
}
