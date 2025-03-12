package raytracer

import "core:fmt"
import "core:slice"
import vk "vendor:vulkan"
_ :: fmt

Descriptor_Set_Manager :: struct {
	raytracing_descriptor_set, scene_descriptor_set, camera_descriptor_set: vk.DescriptorSetLayout,
	pool:                                                                   vk.DescriptorPool,
	device:                                                                 ^Device,
}

descriptor_set_manager2_init :: proc(manager: ^Descriptor_Set_Manager, device: ^Device) {
	manager.device = device
	descriptor_pool_init(
		&manager.pool,
		manager.device,
		{
			vk.DescriptorPoolSize{type = .ACCELERATION_STRUCTURE_KHR, descriptorCount = 1},
			vk.DescriptorPoolSize{type = .STORAGE_IMAGE, descriptorCount = 1},
			vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = 2},
		},
		1000,
	)
	{ 	// raytracing descriptor set layout
		bindings := [?]vk.DescriptorSetLayoutBinding {
			{ 	// Acceleration structure (TLAS)
				binding         = 0,
				descriptorType  = .ACCELERATION_STRUCTURE_KHR,
				descriptorCount = 1,
				stageFlags      = {.RAYGEN_KHR},
			},
			{ 	// Output Image
				binding         = 1,
				descriptorType  = .STORAGE_IMAGE,
				descriptorCount = 1,
				stageFlags      = {.RAYGEN_KHR},
			},
		}

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = len(bindings),
			pBindings    = raw_data(bindings[:]),
		}

		vk.CreateDescriptorSetLayout(
			manager.device.logical_device.ptr,
			&create_info,
			nil,
			&manager.raytracing_descriptor_set,
		)
	}

	{ 	// scene descriptor set layout
		bindings := [?]vk.DescriptorSetLayoutBinding {
			{ 	// Acceleration structure (TLAS)
				binding         = 0,
				descriptorType  = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags      = {.CLOSEST_HIT_KHR},
			},
			{ 	// Output Image
				binding         = 1,
				descriptorType  = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags      = {.CLOSEST_HIT_KHR},
			},
		}

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = len(bindings),
			pBindings    = raw_data(bindings[:]),
		}

		vk.CreateDescriptorSetLayout(
			manager.device.logical_device.ptr,
			&create_info,
			nil,
			&manager.scene_descriptor_set,
		)
	}

	{ 	// Camera
		bindings := [?]vk.DescriptorSetLayoutBinding {
			{ 	// Camera
				binding         = 0,
				descriptorType  = .UNIFORM_BUFFER,
				descriptorCount = 1,
				stageFlags      = {.RAYGEN_KHR},
			},
		}

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = len(bindings),
			pBindings    = raw_data(bindings[:]),
		}

		vk.CreateDescriptorSetLayout(
			manager.device.logical_device.ptr,
			&create_info,
			nil,
			&manager.camera_descriptor_set,
		)
	}
}

descriptor_set_manager_get_descriptor_layouts :: proc(
	manager: Descriptor_Set_Manager,
	allocator := context.allocator,
) -> []vk.DescriptorSetLayout {
	descriptors := [?]vk.DescriptorSetLayout {
		manager.raytracing_descriptor_set,
		manager.scene_descriptor_set,
		manager.camera_descriptor_set,
	}
	return slice.clone(descriptors[:], allocator)
}

descriptor_set_manager_allocate_descriptor_sets :: proc(
	manager: Descriptor_Set_Manager,
	allocator := context.allocator,
) -> (
	result: []vk.DescriptorSet,
) {
	layouts := descriptor_set_manager_get_descriptor_layouts(manager, context.temp_allocator)
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = manager.pool,
		descriptorSetCount = 2,
		pSetLayouts        = raw_data(layouts[:]),
	}

	result = make([]vk.DescriptorSet, len(layouts))
	vk.AllocateDescriptorSets(manager.device.logical_device.ptr, &alloc_info, raw_data(result))

	return result
}

descriptor_pool_init :: proc(
	pool: ^vk.DescriptorPool,
	device: ^Device,
	pool_sizes: []vk.DescriptorPoolSize,
	max_sets: u32,
	flags: vk.DescriptorPoolCreateFlags = {},
) -> Pipeline_Error {
	create_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
		maxSets       = max_sets,
		flags         = flags,
	}

	if vk_check(
		   vk.CreateDescriptorPool(device.logical_device.ptr, &create_info, nil, pool),
		   "Failed to create descriptor pool",
	   ) !=
	   .SUCCESS {
		return .Pool_Creation_Failed
	}

	return .None
}
