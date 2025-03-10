package raytracer

import "core:fmt"
// import "core:strings"
import vkb "external:odin-vk-bootstrap"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: fmt

Device :: struct {
	instance:        ^vkb.Instance,
	physical_device: ^vkb.Physical_Device,
	logical_device:  ^vkb.Device,
	allocator:       vma.Allocator,
	command_pool:    vk.CommandPool,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
}

Device_Error :: enum {
	None = 0,
	Instance_Creation_Failed,
	Surface_Creation_Failed,
	Physical_Device_Selection_Failed,
	Logical_Device_Creation_Failed,
	Transfer_Command_Pool_Creation_Failed,
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


		vkb.instance_set_minimum_version(&builder, vk.API_VERSION_1_4)

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

		vkb.selector_add_required_extension(&selector, vk.KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME)
		vkb.selector_add_required_extension(
			&selector,
			vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
		)
		vkb.selector_add_required_extension(
			&selector,
			vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
		)
		vkb.selector_add_required_extension(&selector, vk.KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME)
		vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
		vkb.selector_set_required_features(&selector, {shaderInt64 = true})
		vkb.selector_set_required_features_12(&selector, {bufferDeviceAddress = true})
		vkb.selector_set_required_features_13(
			&selector,
			{dynamicRendering = true, synchronization2 = true},
		)
		vkb.selector_add_required_extension_features(
			&selector,
			vk.PhysicalDeviceRayTracingPipelineFeaturesKHR {
				sType = .PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR,
				rayTracingPipeline = true,
			},
		)
		vkb.selector_add_required_extension_features(
			&selector,
			vk.PhysicalDeviceAccelerationStructureFeaturesKHR {
				sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
				accelerationStructure = true,
			},
		)
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
			flags              = {.Buffer_Device_Address},
			physical_device    = device.physical_device.ptr,
			device             = device.logical_device.ptr,
			instance           = device.instance.ptr,
			vulkan_functions   = &vma_functions,
		}

		_ = vk_check(
			vma.create_allocator(create_info, &device.allocator),
			"Failed to create VMA allocator",
		)
	}

	{ 	// Create transfer command pool
		create_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			flags            = {.TRANSIENT},
			queueFamilyIndex = vkb.device_get_queue_index(device.logical_device, .Graphics),
		}

		if result := vk_check(
			vk.CreateCommandPool(
				device.logical_device.ptr,
				&create_info,
				nil,
				&device.command_pool,
			),
			"Failed to create Transfer command pool",
		); result != .SUCCESS {
			return .Transfer_Command_Pool_Creation_Failed
		}
	}

	return .None
}

device_destroy :: proc(device: ^Device) {
	vk.DestroyCommandPool(device.logical_device.ptr, device.command_pool, nil)
	vma.destroy_allocator(device.allocator)
	vkb.destroy_device(device.logical_device)
	vkb.destroy_physical_device(device.physical_device)
	vkb.destroy_instance(device.instance)
}

device_copy_buffer :: proc(device: ^Device, src, dst: vk.Buffer, size: vk.DeviceSize) {
	cmd := device_begin_single_time_commands(device, device.command_pool)
	defer device_end_single_time_commands(device, device.command_pool, cmd)

	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}

	vk.CmdCopyBuffer(cmd, src, dst, 1, &copy_region)
}

device_begin_single_time_commands :: proc(
	device: ^Device,
	pool: vk.CommandPool,
) -> (
	cmd: vk.CommandBuffer,
) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = pool,
		commandBufferCount = 1,
	}

	vk.AllocateCommandBuffers(device.logical_device.ptr, &alloc_info, &cmd)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	_ = vk_check(vk.BeginCommandBuffer(cmd, &begin_info), "Failed to start single time command")

	return cmd
}

device_end_single_time_commands :: proc(
	device: ^Device,
	pool: vk.CommandPool,
	cmd: vk.CommandBuffer,
) {
	cmd := cmd
	_ = vk_check(vk.EndCommandBuffer(cmd), "Failed to end single time command")

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
	}

	_ = vk_check(
		vk.QueueSubmit(device.graphics_queue, 1, &submit_info, 0),
		"Failed to submit single time command",
	)

	_ = vk_check(vk.QueueWaitIdle(device.graphics_queue), "Failed to wait on graphics queue")
	vk.FreeCommandBuffers(device.logical_device.ptr, pool, 1, &cmd)
}
