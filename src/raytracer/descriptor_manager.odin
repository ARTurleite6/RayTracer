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

Descriptor_Set_Write_Info :: union {
	^vk.DescriptorBufferInfo,
	^vk.DescriptorImageInfo,
	^vk.AccelerationStructureKHR,
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

descriptor_manager_destroy :: proc(manager: ^Descriptor_Set_Manager) {
	for _, &d in manager.descriptor_sets {
		vk.DestroyDescriptorSetLayout(manager.device.logical_device.ptr, d.layout.handle, nil)
	}
	delete(manager.descriptor_sets)

	manager^ = {}
}

descriptor_manager_get_descriptor_set_index :: proc(
	manager: Descriptor_Set_Manager,
	name: string,
	index: u32,
) -> vk.DescriptorSet {
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
	size: int = 1,
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
	buffer: vk.Buffer,
	range: vk.DeviceSize,
	offset: vk.DeviceSize = 0,
	// layout: vk.ImageLayout,
) {
	info := vk.DescriptorBufferInfo {
		buffer = buffer,
		offset = offset,
		range  = range,
	}

	_descriptor_manager_write(manager, name, index, binding, &info)
}

descriptor_manager_write :: proc {
	descriptor_manager_write_buffer,
	descriptor_manager_write_image,
	descriptor_manager_write_acceleration_structure,
}

descriptor_manager_write_acceleration_structure :: proc(
	manager: ^Descriptor_Set_Manager,
	name: string,
	index: u32,
	binding: u32,
	acceleration_structure: ^vk.AccelerationStructureKHR,
) {
	_descriptor_manager_write(manager, name, index, binding, acceleration_structure)
}

descriptor_manager_write_image :: proc(
	manager: ^Descriptor_Set_Manager,
	name: string,
	index: u32,
	binding: u32,
	image_view: vk.ImageView,
	// layout: vk.ImageLayout,
) {
	info := vk.DescriptorImageInfo {
		imageView   = image_view,
		imageLayout = .GENERAL,
	}

	_descriptor_manager_write(manager, name, index, binding, &info)
}

@(private = "file")
_descriptor_manager_write :: proc(
	manager: ^Descriptor_Set_Manager,
	name: string,
	index: u32,
	binding: u32,
	info: Descriptor_Set_Write_Info,
) -> Pipeline_Error {
	set_info, exists := manager.descriptor_sets[name]
	assert(exists, "Descriptor set not found")

	binding_desc, has_binding := set_info.layout.bindings[binding]
	assert(has_binding, "Binding not found")

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = set_info.sets[index],
		dstBinding      = binding,
		descriptorCount = 1,
		descriptorType  = binding_desc.descriptorType,
	}

	accel_info: vk.WriteDescriptorSetAccelerationStructureKHR
	switch value in info {
	case ^vk.DescriptorImageInfo:
		write.pImageInfo = value
	case ^vk.DescriptorBufferInfo:
		write.pBufferInfo = value
	case ^vk.AccelerationStructureKHR:
		accel_info = {
			sType                      = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
			accelerationStructureCount = 1,
			pAccelerationStructures    = value,
		}
		write.pNext = &accel_info
	}

	vk.UpdateDescriptorSets(manager.device.logical_device.ptr, 1, &write, 0, nil)
	return .None
}
