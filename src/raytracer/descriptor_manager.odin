package raytracer

import "core:fmt"
import vk "vendor:vulkan"
_ :: fmt

Descriptor_Set_Layout :: struct {
	handle: vk.DescriptorSetLayout,
	bindings: []vk.DescriptorSetLayoutBinding,

	ctx: ^Vulkan_Context,
}

create_descriptor_set_layout :: proc(
	bindings: []vk.DescriptorSetLayoutBinding,
	device: vk.Device,
) -> (
	layout: vk.DescriptorSetLayout,
	result: vk.Result,
) {
	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings),
	}

	vk_check(
		vk.CreateDescriptorSetLayout(device, &create_info, nil, &layout),
		"Failed to create descriptor set layout",
	) or_return

	return layout, .SUCCESS
}

descriptor_set_layout_destroy :: proc(layout: vk.DescriptorSetLayout, device: vk.Device) {
	vk.DestroyDescriptorSetLayout(device, layout, nil)
}

allocate_single_descriptor_set :: proc(
	pool: vk.DescriptorPool,
	layout: ^vk.DescriptorSetLayout,
	device: vk.Device,
) -> (
	set: vk.DescriptorSet,
	result: vk.Result,
) {
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = layout,
	}

	vk_check(
		vk.AllocateDescriptorSets(device, &alloc_info, &set),
		"Failed to allocate descriptor sets",
	) or_return

	return set, .SUCCESS
}

allocate_descriptor_sets :: proc(
	pool: vk.DescriptorPool,
	layouts: []vk.DescriptorSetLayout,
	device: vk.Device,
	allocator := context.allocator,
) -> (
	sets: []vk.DescriptorSet,
	result: vk.Result,
) {
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool,
		descriptorSetCount = u32(len(layouts)),
		pSetLayouts        = raw_data(layouts),
	}

	sets = make([]vk.DescriptorSet, len(layouts), allocator)
	vk_check(
		vk.AllocateDescriptorSets(device, &alloc_info, raw_data(sets)),
		"Failed to allocate descriptor sets",
	) or_return

	return sets, .SUCCESS
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