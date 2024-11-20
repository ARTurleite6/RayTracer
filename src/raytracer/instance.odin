package raytracer

import vk "vendor:vulkan"


Instance :: vk.Instance

@(require_results)
instance_init :: proc(
	instance: ^Instance,
	app_name: cstring,
	required_extensions: []cstring,
	messenger_create_info: ^vk.DebugUtilsMessengerCreateInfoEXT = nil,
) -> vk.Result {
	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pApplicationName = app_name,
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "No Engine",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_3,
		},
		pNext                   = messenger_create_info,
		enabledExtensionCount   = u32(len(required_extensions)),
		ppEnabledExtensionNames = raw_data(required_extensions),
	}

	when ODIN_DEBUG {
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1
	}

	when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
	}

	return vk.CreateInstance(&create_info, nil, instance)
}

instance_destroy :: proc(instance: Instance) {
	vk.DestroyInstance(instance, nil)
}
