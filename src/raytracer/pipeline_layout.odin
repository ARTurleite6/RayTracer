package raytracer

import "core:log"
_ :: log

import "core:fmt"
import "core:slice"
import "core:strings"

import vk "vendor:vulkan"

Pipeline_Layout :: struct {
	handle:                 vk.PipelineLayout,
	shader_modules:         []^Shader_Module,
	// list of shader resources
	shader_resources:       map[string]Shader_Resource,
	// map for each set and the resources it owns
	shader_sets:            map[u32][dynamic]Shader_Resource,
	descriptor_set_layouts: [dynamic]^Descriptor_Set_Layout2,
}

pipeline_layout_init2 :: proc(
	layout: ^Pipeline_Layout,
	ctx: ^Vulkan_Context,
	shader_modules: []^Shader_Module,
	allocator := context.allocator,
) -> (
	err: vk.Result,
) {
	layout.shader_modules = shader_modules

	for module in shader_modules {
		for resource in module.resources {
			key: string
			if resource.type == .Input || resource.type == .Output {
				key = fmt.aprintf("%v_%s", resource.name, allocator = context.temp_allocator)
			} else {
				key = resource.name
			}
			if res, ok := &layout.shader_resources[key]; ok {
				res.stages |= resource.stages
			} else {
				layout.shader_resources[strings.clone(key, allocator)] = resource
			}
		}
	}

	for _, res in layout.shader_resources {
		_, value_ptr, _, _ := map_entry(&layout.shader_sets, res.set)
		append(value_ptr, res)
	}

	for shader_set, set_resources in layout.shader_sets {
		descriptor_set_layout, _ := resource_cache_request_descriptor_set_layout2(
			&ctx.cache,
			ctx,
			shader_set,
			shader_modules,
			set_resources[:],
		)

		append_elem(&layout.descriptor_set_layouts, descriptor_set_layout)
	}
	// sort descriptor set layouts (I think odin's map foreach does not garantee order)
	slice.sort_by_key(layout.descriptor_set_layouts[:], proc(l: ^Descriptor_Set_Layout2) -> u32 {
		return l.set_index
	})

	descriptor_set_layout_handles := make(
		[dynamic]vk.DescriptorSetLayout,
		0,
		len(layout.descriptor_set_layouts),
	)
	defer delete(descriptor_set_layout_handles)

	for desc_layout in layout.descriptor_set_layouts {
		if desc_layout != nil {
			append(&descriptor_set_layout_handles, desc_layout.handle)
		} else {
			append(&descriptor_set_layout_handles, 0)
		}
	}

	push_constant_ranges := make([dynamic]vk.PushConstantRange)
	defer delete(push_constant_ranges)

	for push_constant_range in pipeline_layout_get_resources(
		layout^,
		.Push_Constant,
		allocator = context.temp_allocator,
	) {
		range := vk.PushConstantRange {
			stageFlags = push_constant_range.stages,
			offset     = push_constant_range.offset,
			size       = push_constant_range.size,
		}
		append(&push_constant_ranges, range)
	}

	create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(descriptor_set_layout_handles)),
		pSetLayouts            = raw_data(descriptor_set_layout_handles),
		pushConstantRangeCount = u32(len(push_constant_ranges)),
		pPushConstantRanges    = raw_data(push_constant_ranges),
	}

	vk_check(
		vk.CreatePipelineLayout(vulkan_get_device_handle(ctx), &create_info, nil, &layout.handle),
		"Failed to create Pipeline layout",
	) or_return

	return nil
}

pipeline_layout_destroy :: proc(
	layout: ^Pipeline_Layout,
	ctx: ^Vulkan_Context,
	allocator := context.allocator,
) {
	context.allocator = allocator

	for key in layout.shader_resources {
		delete(key)
	}
	delete(layout.shader_resources)
	for _, set in layout.shader_sets {
		delete(set)
	}
	delete(layout.shader_sets)
	delete(layout.descriptor_set_layouts)

	vk.DestroyPipelineLayout(vulkan_get_device_handle(ctx), layout.handle, nil)
}

pipeline_layout_get_resources :: proc(
	layout: Pipeline_Layout,
	type: Shader_Resource_Type,
	stage := vk.ShaderStageFlags_ALL,
	allocator := context.allocator,
) -> []Shader_Resource {
	result := make([dynamic]Shader_Resource, allocator = allocator)
	for _, resource in layout.shader_resources {
		if (resource.type == type || type == .All) &&
		   (resource.stages == stage || stage == vk.ShaderStageFlags_ALL) {
			append_elem(&result, resource)
		}
	}
	return result[:]
}

// make_pipeline_layout :: proc(
// 	ctx: ^Vulkan_Context,
// 	shaders: []^Shader,
// ) -> (
// 	layout: Pipeline_Layout,
// ) {
// }

pipeline_layout_init :: proc(
	ctx: ^Vulkan_Context,
	descriptor_set_layouts: []vk.DescriptorSetLayout,
	push_constant_ranges: []vk.PushConstantRange,
) -> (
	layout: vk.PipelineLayout,
) {
	create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(descriptor_set_layouts)),
		pSetLayouts            = raw_data(descriptor_set_layouts),
		pushConstantRangeCount = u32(len(push_constant_ranges)),
		pPushConstantRanges    = raw_data(push_constant_ranges),
	}

	_ = vk_check(
		vk.CreatePipelineLayout(vulkan_get_device_handle(ctx), &create_info, nil, &layout),
		"Failed to create pipeline layout",
	)

	return layout
}
