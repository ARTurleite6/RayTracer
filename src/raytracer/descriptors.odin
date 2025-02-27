package raytracer

import "core:slice"
import vk "vendor:vulkan"

Descriptor_Set_Layout_Builder :: struct {
	device:   ^Device,
	bindings: map[u32]vk.DescriptorSetLayoutBinding,
}

Descriptor_Set_Layout :: struct {
	handle:   vk.DescriptorSetLayout,
	bindings: map[u32]vk.DescriptorSetLayoutBinding,
}

Descriptor_Pool_Builder :: struct {
	device:     ^Device,
	pool_sizes: [dynamic]vk.DescriptorPoolSize,
	max_sets:   u32,
	flags:      vk.DescriptorPoolCreateFlags,
}

Descriptor_Writer :: struct {
	layout: Descriptor_Set_Layout,
	pool:   vk.DescriptorPool,
	device: ^Device,
	writes: [dynamic]vk.WriteDescriptorSet,
}

descriptor_layout_builder_init :: proc(builder: ^Descriptor_Set_Layout_Builder, device: ^Device) {
	builder.device = device
	builder.bindings = make(map[u32]vk.DescriptorSetLayoutBinding)
}

descriptor_layout_builder_add_binding :: proc(
	builder: ^Descriptor_Set_Layout_Builder,
	binding: u32,
	type: vk.DescriptorType,
	stage_flags: vk.ShaderStageFlags,
	count: u32 = 1,
) {
	builder.bindings[binding] = {
		binding         = binding,
		descriptorType  = type,
		descriptorCount = count,
		stageFlags      = stage_flags,
	}
}

descriptor_layout_build :: proc(
	builder: ^Descriptor_Set_Layout_Builder,
) -> (
	layout: Descriptor_Set_Layout,
	err: Pipeline_Error,
) {
	layout.bindings = builder.bindings
	binding_values, _ := slice.map_values(builder.bindings, context.temp_allocator)

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(binding_values)),
		pBindings    = raw_data(binding_values),
	}

	if vk_check(
		   vk.CreateDescriptorSetLayout(
			   builder.device.logical_device.ptr,
			   &create_info,
			   nil,
			   &layout.handle,
		   ),
		   "Failed to create descriptor layout",
	   ) !=
	   .SUCCESS {
		return {}, .Layout_Creation_Failed
	}

	return layout, nil
}

descriptor_layout_destroy :: proc(layout: ^Descriptor_Set_Layout, device: Device) {
	delete(layout.bindings)
	layout.bindings = nil
	vk.DestroyDescriptorSetLayout(device.logical_device.ptr, layout.handle, nil)
	layout.handle = 0
}

descriptor_pool_builder_init :: proc(
	builder: ^Descriptor_Pool_Builder,
	device: ^Device,
	allocator := context.allocator,
) {
	builder.device = device
	builder.pool_sizes = make([dynamic]vk.DescriptorPoolSize, allocator)
	builder.max_sets = 1000
}

descriptor_pool_builder_add_pool_size :: proc(
	builder: ^Descriptor_Pool_Builder,
	type: vk.DescriptorType,
	count: u32,
) {
	append(&builder.pool_sizes, vk.DescriptorPoolSize{type = type, descriptorCount = count})
}

descriptor_pool_builder_set_flags :: proc(
	builder: ^Descriptor_Pool_Builder,
	flags: vk.DescriptorPoolCreateFlags,
) {
	builder.flags = flags
}

descriptor_pool_builder_set_max_sets :: proc(builder: ^Descriptor_Pool_Builder, count: u32) {
	builder.max_sets = count
}

descriptor_pool_build :: proc(
	builder: ^Descriptor_Pool_Builder,
) -> (
	pool: vk.DescriptorPool,
	err: Pipeline_Error,
) {
	create_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(builder.pool_sizes)),
		pPoolSizes    = raw_data(builder.pool_sizes),
		maxSets       = builder.max_sets,
		flags         = builder.flags,
	}

	if vk_check(
		   vk.CreateDescriptorPool(builder.device.logical_device.ptr, &create_info, nil, &pool),
		   "Failed to create descriptor pool",
	   ) !=
	   .SUCCESS {
		return 0, .Pool_Creation_Failed
	}

	delete(builder.pool_sizes)
	builder.pool_sizes = nil

	return pool, nil
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

	if vk.AllocateDescriptorSets(writer.device.logical_device.ptr, &alloc_info, &set) != .SUCCESS {
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
