package raytracer

import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"
_ :: fmt

Descriptor_Set_Layout :: struct {
	handle: vk.DescriptorSetLayout,
	bindings: []vk.DescriptorSetLayoutBinding,

	ctx: ^Vulkan_Context,
}

create_descriptor_set_layout :: proc{create_descriptor_set_layout1 ,create_descriptor_set_layout2 }

@(require_results)
descriptor_set_layout_hash :: proc(resources: []Shader_Resource) -> u32 { 
	h := hash_func({0})
	for r in resources {
		if r.type == .Push_Constant || r.type == .Output || r.type == .Specialization_Constant || r.type == .Input {
			continue
		}

		h ~= hash_func(mem.any_to_bytes(r.binding))
		h ~= hash_func(mem.any_to_bytes(r.type))
		h ~= hash_func(mem.any_to_bytes(r.stages))
	}

	return h
}

create_descriptor_set_layout2 :: proc(resources: []Shader_Resource, ctx: ^Vulkan_Context) -> (layout: Descriptor_Set_Layout) {
	layout.ctx = ctx
	bindings := make([dynamic]vk.DescriptorSetLayoutBinding, context.temp_allocator)
	for r in resources {
		if r.type == .Push_Constant || r.type == .Output || r.type == .Specialization_Constant || r.type == .Input {
			continue
		}

		append(&bindings, vk.DescriptorSetLayoutBinding {
			binding = r.binding,
			descriptorType = find_descriptor_type(r.type),
			descriptorCount = 1, // TODO: change when receiving arrays
			stageFlags = r.stages,
		})
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings = raw_data(bindings),
	}

	_ = vk_check(vk.CreateDescriptorSetLayout(ctx.device.logical_device.ptr, &create_info, nil, &layout.handle), "Failed to create descriptor set layout")
	layout.bindings = bindings[:]

	return layout
}

create_descriptor_set_layout1 :: proc(
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

@(private="file")
find_descriptor_type :: proc(resource_type: Shader_Resource_Type) -> vk.DescriptorType {
	#partial switch resource_type {
		case .Input_Attachment:
			return .INPUT_ATTACHMENT
		case .Image:
			return .SAMPLED_IMAGE
		case .Image_Sampler:
			return .COMBINED_IMAGE_SAMPLER
		case .Image_Storage:
			return .STORAGE_IMAGE
		case .Sampler:
			return .SAMPLER
		case .Buffer_Uniform:
			return .UNIFORM_BUFFER
		case .Buffer_Storage:
			return .STORAGE_BUFFER
		case .Acceleration_Structure:
			return .ACCELERATION_STRUCTURE_KHR
	}
	assert(false, "Failed to find descriptor type")
	return {}
}