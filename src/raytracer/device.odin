package raytracer

import vkb "external:odin-vk-bootstrap"
import vma "external:odin-vma"
import vk "vendor:vulkan"

Device :: struct {
	instance:        ^vkb.Instance,
	physical_device: ^vkb.Physical_Device,
	logical_device:  ^vkb.Device,
	allocator:       vma.Allocator,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
}

Device_Error :: enum {
	None = 0,
	Instance_Creation_Failed,
	Surface_Creation_Failed,
	Physical_Device_Selection_Failed,
	Logical_Device_Creation_Failed,
	Queue_Acquisition_Failed,
	Allocator_Creation_Failed,
}

@(require_results)
device_init :: proc(
	device: ^Device,
	window: ^Window,
	allocator := context.allocator,
) -> (
	err: Device_Error,
) {
	{ 	// Create instance
		builder, instance_ok := vkb.init_instance_builder()
		if !instance_ok {
			err = .Instance_Creation_Failed
			return
		}
		defer vkb.destroy_instance_builder(&builder)


		vkb.instance_set_minimum_version(&builder, vk.API_VERSION_1_3)

		when ODIN_DEBUG {
			vkb.instance_request_validation_layers(&builder)
			vkb.instance_use_default_debug_messenger(&builder)
		}

		ok: bool
		if device.instance, ok = vkb.build_instance(&builder); !ok {
			err = .Instance_Creation_Failed
			return
		}
	}

	{ 	// Choose physical device
		selector, selector_ok := vkb.init_physical_device_selector(device.instance)
		if !selector_ok {
			err = .Physical_Device_Selection_Failed
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		surface, result := window_get_surface(window, device.instance)
		if result != .SUCCESS {
			err = .Surface_Creation_Failed
			return
		}

		vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
		vkb.selector_set_required_features_13(&selector, {dynamicRendering = true})
		vkb.selector_set_surface(&selector, surface)

		ok: bool
		if device.physical_device, ok = vkb.select_physical_device(
			&selector,
			allocator = allocator,
		); !ok {
			err = .Physical_Device_Selection_Failed
			return
		}
	}

	{ 	// Create logical device
		builder, device_ok := vkb.init_device_builder(device.physical_device)
		if !device_ok {
			err = .Logical_Device_Creation_Failed
			return
		}
		defer vkb.destroy_device_builder(&builder)

		ok: bool
		if device.logical_device, ok = vkb.build_device(&builder, allocator); !ok {
			err = .Logical_Device_Creation_Failed
			return
		}
	}

	{ 	// Get Queues
		ok: bool
		if device.graphics_queue, ok = vkb.device_get_queue(device.logical_device, .Graphics);
		   !ok {
			err = .Queue_Acquisition_Failed
			return
		}
		if device.present_queue, ok = vkb.device_get_queue(device.logical_device, .Present); !ok {
			err = .Queue_Acquisition_Failed
			return
		}
	}

	{ 	// Create allocator
		vma_functions := vma.create_vulkan_functions()
		// create allocator
		create_info := vma.Allocator_Create_Info {
			vulkan_api_version = vkb.convert_vulkan_to_vma_version(device.instance.api_version),
			physical_device    = device.physical_device.ptr,
			device             = device.logical_device.ptr,
			instance           = device.instance.ptr,
			vulkan_functions   = &vma_functions,
		}

		vk_must(
			vma.create_allocator(create_info, &device.allocator),
			"Failed to create VMA allocator",
		)
	}

	return .None
}

device_destroy :: proc(device: ^Device) {
	vma.destroy_allocator(device.allocator)
	vkb.destroy_device(device.logical_device)
	vkb.destroy_physical_device(device.physical_device)
	vkb.destroy_instance(device.instance)
}
