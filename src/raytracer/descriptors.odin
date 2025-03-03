package raytracer

import "core:slice"
import vk "vendor:vulkan"

Descriptor_Set_Layout :: struct {
	handle:   vk.DescriptorSetLayout,
	bindings: map[u32]vk.DescriptorSetLayoutBinding,
}

Descriptor_Writer :: struct {
	layout: Descriptor_Set_Layout,
	pool:   vk.DescriptorPool,
	device: ^Device,
	writes: [dynamic]vk.WriteDescriptorSet,
}

descriptor_set_layout_init :: proc(
	layout: ^Descriptor_Set_Layout,
	device: ^Device,
	bindings: []vk.DescriptorSetLayoutBinding,
	allocator := context.allocator,
) -> Pipeline_Error {
	layout.bindings = make(map[u32]vk.DescriptorSetLayoutBinding, allocator)

	for binding in bindings {
		layout.bindings[binding.binding] = binding
	}

	binding_values, _ := slice.map_values(layout.bindings, context.temp_allocator)
	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(binding_values)),
		pBindings    = raw_data(binding_values),
	}

	if vk_check(
		   vk.CreateDescriptorSetLayout(
			   device.logical_device.ptr,
			   &create_info,
			   nil,
			   &layout.handle,
		   ),
		   "Failed to create descriptor layout",
	   ) !=
	   .SUCCESS {
		return .Layout_Creation_Failed
	}

	return nil
}

descriptor_layout_destroy :: proc(layout: ^Descriptor_Set_Layout, device: Device) {
	delete(layout.bindings)
	vk.DestroyDescriptorSetLayout(device.logical_device.ptr, layout.handle, nil)
	layout^ = {}
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

descriptor_writer_init :: proc(
	writer: ^Descriptor_Writer,
	layout: Descriptor_Set_Layout,
	pool: vk.DescriptorPool,
	device: ^Device,
) {
	writer.layout = layout
	writer.pool = pool
	writer.device = device
	writer.writes = make([dynamic]vk.WriteDescriptorSet)
}

descriptor_writer_write_buffer :: proc(
	writer: ^Descriptor_Writer,
	binding: u32,
	buffer_info: ^vk.DescriptorBufferInfo,
) {
	binding_description, has_binding := writer.layout.bindings[binding]
	assert(has_binding, "Descriptor set layout does not have desired binding")

	assert(
		binding_description.descriptorCount == 1,
		"Binding to single descriptor info, but binding expects multiple",
	)

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		descriptorCount = 1,
		descriptorType  = binding_description.descriptorType,
		pBufferInfo     = buffer_info,
	}
	append(&writer.writes, write)
}

// descriptor_writer_write_image :: proc(
// 	writer: ^Descriptor_Writer,
// 	binding: u32,
// 	image_info: ^vk.DescriptorImageInfo,
// ) {
// 	write := vk.WriteDescriptorSet {
// 		sType           = .WRITE_DESCRIPTOR_SET,
// 		dstBinding      = binding,
// 		descriptorCount = 1,
// 		descriptorType  = .COMBINED_IMAGE_SAMPLER,
// 		pImageInfo      = image_info,
// 	}
// 	append(&writer.writes, write)
// }

descriptor_writer_build :: proc(
	writer: ^Descriptor_Writer,
) -> (
	set: vk.DescriptorSet,
	err: Pipeline_Error,
) {
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = writer.pool,
		descriptorSetCount = 1,
		pSetLayouts        = &writer.layout.handle,
	}

	if vk_check(
		   vk.AllocateDescriptorSets(writer.device.logical_device.ptr, &alloc_info, &set),
		   "Failed to allocate Descriptor Set",
	   ) !=
	   .SUCCESS {
		return 0, .Descriptor_Set_Creation_Failed
	}

	for &write in writer.writes {
		write.dstSet = set
	}

	vk.UpdateDescriptorSets(
		writer.device.logical_device.ptr,
		u32(len(writer.writes)),
		raw_data(writer.writes),
		0,
		nil,
	)

	delete(writer.writes)
	writer.writes = nil

	return set, nil
}
