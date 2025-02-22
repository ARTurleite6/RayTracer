package raytracer

import "base:runtime"
import "core:slice"
import vk "vendor:vulkan"

Descriptor_Pool :: struct {
	handle: vk.DescriptorPool,
	device: vk.Device,
}

Descriptor_Pool_Builder :: struct {
	device:     vk.Device,
	pool_sizes: [dynamic]vk.DescriptorPoolSize,
	max_sets:   u32,
	pool_flags: vk.DescriptorPoolCreateFlags,
}

Descriptor_Set_Layout :: struct {
	handle: vk.DescriptorSetLayout,
	device: vk.Device,
}

Descriptor_Set_Layout_Builder :: struct {
	bindings: map[u32]vk.DescriptorSetLayoutBinding,
	device:   vk.Device,
}

create_descriptor_set_layout_builder :: proc(
	device: vk.Device,
	allocator := context.allocator,
) -> Descriptor_Set_Layout_Builder {
	return {bindings = make(map[u32]vk.DescriptorSetLayoutBinding, allocator), device = device}
}

descriptor_set_layout_add_binding :: proc(
	self: ^Descriptor_Set_Layout_Builder,
	binding: u32,
	descriptor_type: vk.DescriptorType,
	stage_flags: vk.ShaderStageFlags,
	count: u32 = 1,
) {
	assert(binding not_in self.bindings, "Binding already inserted")

	self.bindings[binding] = vk.DescriptorSetLayoutBinding {
		binding         = binding,
		descriptorType  = descriptor_type,
		descriptorCount = count,
		stageFlags      = stage_flags,
	}
}

create_descriptor_set_layout :: proc(
	builder: Descriptor_Set_Layout_Builder,
) -> (
	layout: Descriptor_Set_Layout,
	err: Backend_Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	bindings, _ := slice.map_values(builder.bindings, context.temp_allocator) // TODO: Handle the allocator error in the future
	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings),
	}

	vk_check(
		vk.CreateDescriptorSetLayout(builder.device, &create_info, nil, &layout.handle),
		"Failed to create Descriptor Layout",
	) or_return
	layout.device = builder.device

	return layout, nil
}

descriptor_set_layout_destroy :: proc(self: Descriptor_Set_Layout) {
	vk.DestroyDescriptorSetLayout(self.device, self.handle, nil)
}

create_descriptor_pool :: proc(
	builder: Descriptor_Pool_Builder,
) -> (
	pool: Descriptor_Pool,
	err: Backend_Error,
) {

	create_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = builder.pool_flags,
		maxSets       = builder.max_sets,
		poolSizeCount = u32(len(builder.pool_sizes)),
		pPoolSizes    = raw_data(builder.pool_sizes),
	}

	vk_check(
		vk.CreateDescriptorPool(builder.device, &create_info, nil, &pool.handle),
		"Failed to create descriptor pool",
	) or_return

	pool.device = builder.device

	return pool, nil
}

descriptor_pool_destroy :: proc(self: Descriptor_Pool) {
	vk.DestroyDescriptorPool(self.device, self.handle, nil)
}

create_descriptor_pool_builder :: proc(
	device: vk.Device,
	max_sets: u32 = 1000,
	pool_flags: vk.DescriptorPoolCreateFlags = {},
	allocator := context.allocator,
) -> Descriptor_Pool_Builder {return{
		device = device,
		pool_sizes = make([dynamic]vk.DescriptorPoolSize),
		max_sets = max_sets,
		pool_flags = pool_flags,
	}
}

descriptor_pool_add_pool_size :: proc(
	self: ^Descriptor_Pool_Builder,
	descriptor_type: vk.DescriptorType,
	count: u32,
) {
	append(
		&self.pool_sizes,
		vk.DescriptorPoolSize{type = descriptor_type, descriptorCount = count},
	)
}

descriptor_pool_set_pool_flags :: proc(
	self: ^Descriptor_Pool_Builder,
	flags: vk.DescriptorPoolCreateFlags,
) {
	self.pool_flags = flags
}

descriptor_pool_set_max_sets :: proc(self: ^Descriptor_Pool_Builder, count: u32) {
	self.max_sets = count
}
