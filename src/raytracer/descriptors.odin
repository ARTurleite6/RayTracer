package raytracer

import "base:runtime"
import "core:log"
import vk "vendor:vulkan"

Descriptor_Set_Layout :: struct {
	handle:   vk.DescriptorSetLayout,
	bindings: map[u32]vk.DescriptorSetLayoutBinding,
	ctx:      ^Vulkan_Context,
}

Descriptor_Set :: struct {
	handle: vk.DescriptorSet,
	layout: ^Descriptor_Set_Layout,
}

Descriptor_Set_Write_Info :: struct {
	binding:    u32,
	write_info: union {
		vk.DescriptorBufferInfo,
		vk.DescriptorImageInfo,
		vk.WriteDescriptorSetAccelerationStructureKHR,
	},
}

create_descriptor_set_layout :: proc(
	ctx: ^Vulkan_Context,
	bindings: ..vk.DescriptorSetLayoutBinding,
) -> (
	layout: Descriptor_Set_Layout,
) {
	layout.ctx = ctx

	for binding in bindings {
		if binding.binding in layout.bindings {
			log.errorf("Binding %d already exists in the descriptor set layout\n", binding.binding)
			continue
		}
		layout.bindings[binding.binding] = binding
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings),
	}

	_ = vk_check(
		vk.CreateDescriptorSetLayout(
			vulkan_get_device_handle(ctx),
			&create_info,
			nil,
			&layout.handle,
		),
		"Failed to create descriptor set layout",
	)

	return layout
}

descriptor_set_layout_destroy :: proc(layout: ^Descriptor_Set_Layout) {
	vk.DestroyDescriptorSetLayout(vulkan_get_device_handle(layout.ctx), layout.handle, nil)
	delete(layout.bindings)
	layout^ = {}
}

descriptor_set_allocate :: proc(layout: ^Descriptor_Set_Layout) -> (set: Descriptor_Set) {
	set.layout = layout
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = layout.ctx.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &layout.handle,
	}

	vk.AllocateDescriptorSets(vulkan_get_device_handle(layout.ctx), &alloc_info, &set.handle)

	return set
}

descriptor_set_update :: proc(set: ^Descriptor_Set, write_infos: ..Descriptor_Set_Write_Info) {
	if set == nil || len(write_infos) == 0 {
		return
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	ctx := set.layout.ctx
	device := vulkan_get_device_handle(ctx)

	write_set_count := len(write_infos)
	descriptor_writes := make(
		[dynamic]vk.WriteDescriptorSet,
		0,
		write_set_count,
		context.temp_allocator,
	)

	for write_info, i in write_infos {
		binding_it, binding_exists := set.layout.bindings[u32(write_info.binding)]

		if !binding_exists {
			log.errorf("Binding %d does not exist in descriptor set layout", write_info.binding)
			continue
		}

		descriptor_write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = set.handle,
			dstBinding      = u32(write_info.binding),
			descriptorCount = 1,
			descriptorType  = binding_it.descriptorType,
		}

		switch &info in write_info.write_info {
		case vk.DescriptorBufferInfo:
			// TODO: we can improve this with bit_sets
			if binding_it.descriptorType != .UNIFORM_BUFFER &&
			   binding_it.descriptorType != .STORAGE_BUFFER &&
			   binding_it.descriptorType != .UNIFORM_BUFFER_DYNAMIC &&
			   binding_it.descriptorType != .STORAGE_BUFFER_DYNAMIC {
				log.errorf(
					"Binding %d expects buffer info but has type %v",
					i,
					binding_it.descriptorType,
				)
				continue
			}
			info_alloc := new_clone(info, context.temp_allocator)
			descriptor_write.pBufferInfo = info_alloc
		case vk.DescriptorImageInfo:
			// TODO: we can improve this with bit_sets
			if binding_it.descriptorType != .SAMPLER &&
			   binding_it.descriptorType != .COMBINED_IMAGE_SAMPLER &&
			   binding_it.descriptorType != .SAMPLED_IMAGE &&
			   binding_it.descriptorType != .STORAGE_IMAGE {
				log.errorf(
					"Binding %d expects image info but has type %v",
					i,
					binding_it.descriptorType,
				)
				continue
			}
			info_alloc := new_clone(info, context.temp_allocator)
			descriptor_write.pImageInfo = info_alloc
		case vk.WriteDescriptorSetAccelerationStructureKHR:
			if binding_it.descriptorType != .ACCELERATION_STRUCTURE_KHR {
				log.errorf(
					"Binding %d expects acceleration structure but has type %v",
					i,
					binding_it.descriptorType,
				)
				continue
			}
			info_alloc := new_clone(info, context.temp_allocator)
			descriptor_write.pNext = info_alloc
		}

		append(&descriptor_writes, descriptor_write)
	}

	vk.UpdateDescriptorSets(
		device,
		u32(len(descriptor_writes)),
		raw_data(descriptor_writes),
		0,
		nil,
	)
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
