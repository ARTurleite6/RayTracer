package raytracer

import "core:fmt"
import "core:strings"
import vk "vendor:vulkan"

Pipeline_Layout :: struct {
	handle:                 vk.PipelineLayout,
	shader_modules:         []^Shader_Module,
	// list of shader resources
	shader_resources:       map[string]Shader_Resource,
	// map for each set and the resources it owns
	shader_sets:            map[u32][dynamic]Shader_Resource,
	descriptor_set_layouts: []^Descriptor_Set_Layout,
}

pipeline_layout_init2 :: proc(
	layout: ^Pipeline_Layout,
	shader_modules: []^Shader_Module,
	allocator := context.allocator,
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

			if res, ok := layout.shader_resources[key]; ok {
				res.stages |= resource.stages
			} else {
				layout.shader_resources[strings.clone(key, allocator)] = resource
			}
		}
	}

	for _, res in layout.shader_resources {
		if set, ok := &layout.shader_sets[res.set]; ok {
			append(set, res)
		} else {
			layout.shader_sets[res.set] = make([dynamic]Shader_Resource, allocator)
		}
	}
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
