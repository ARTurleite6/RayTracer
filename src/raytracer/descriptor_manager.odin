package raytracer

import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"
_ :: fmt

Descriptor_Set_Manager :: struct {
	descriptor_sets: map[string]Descriptor_Set_Info,
	pool:            vk.DescriptorPool,
	device:          ^Device,
	allocator:       mem.Allocator,
}

Descriptor_Set_Info :: struct {
	sets:   []vk.DescriptorSet,
	layout: Descriptor_Set_Layout,
}

descriptor_manager_init :: proc(
	manager: ^Descriptor_Set_Manager,
	device: ^Device,
	pool: vk.DescriptorPool,
	allocator := context.allocator,
) {
	manager.descriptor_sets = make(map[string]Descriptor_Set_Info, allocator)
	manager.device = device
	manager.pool = pool
	manager.allocator = allocator
}

descriptor_manager_get_descriptor_set_index :: proc(
	manager: Descriptor_Set_Manager,
	name: string,
	index: u32,
) -> vk.DescriptorSet {
	fmt.println(manager)
	return manager.descriptor_sets[name].sets[index]
}

descriptor_manager_get_descriptor_layout :: proc(
	manager: Descriptor_Set_Manager,
	name: string,
) -> Descriptor_Set_Layout {
	return manager.descriptor_sets[name].layout
}

descriptor_manager_register_descriptor_sets :: proc(
	manager: ^Descriptor_Set_Manager,
	name: string,
	layout: Descriptor_Set_Layout,
	size: int,
) -> (
	err: Pipeline_Error,
) {
	if _, exists := manager.descriptor_sets[name]; exists {
		return .Descriptor_Set_Creation_Failed
	}

	info := Descriptor_Set_Info {
		layout = layout,
		sets   = make([]vk.DescriptorSet, size, manager.allocator),
	}

	for i in 0 ..< size {
		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = manager.pool,
			descriptorSetCount = 1,
			pSetLayouts        = &info.layout.handle,
		}

		if vk_check(
			   vk.AllocateDescriptorSets(
				   manager.device.logical_device.ptr,
				   &alloc_info,
				   &info.sets[i],
			   ),
			   "Failed to allocate descriptor sets",
		   ) !=
		   .SUCCESS {
			return .Descriptor_Set_Creation_Failed
		}

	}

	manager.descriptor_sets[name] = info

	return .None
}

descriptor_manager_write_buffer :: proc(
	manager: ^Descriptor_Set_Manager,
	name: string,
	index: u32,
	binding: u32,
	buffer_info: ^vk.DescriptorBufferInfo,
) -> (
	err: Pipeline_Error,
) {
	info, exists := manager.descriptor_sets[name]
	assert(exists, "Descriptor set not found")
	// if !exists {
	// 	return .Descriptor_Set_Not_Found
	// }

	binding_description, has_binding := info.layout.bindings[binding]
	assert(has_binding, "Binding not found")
	// if !has_binding {
	// 	return .Invalid_Binding
	// }

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = info.sets[index],
		dstBinding      = binding,
		descriptorCount = 1,
		descriptorType  = binding_description.descriptorType,
		pBufferInfo     = buffer_info,
	}

	vk.UpdateDescriptorSets(manager.device.logical_device.ptr, 1, &write, 0, nil)

	return nil
}
