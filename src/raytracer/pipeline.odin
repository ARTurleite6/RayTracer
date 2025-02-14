package raytracer

import "core:strings"
import vk "vendor:vulkan"

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

make_graphics_pipeline :: proc(
	device: Device,
	shaders: []Shader_Module,
) -> (
	pipeline: Pipeline,
	result: vk.Result,
) {
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = &dynamic_states,
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}

	vk.CreatePipelineLayout(device.handle, &pipeline_layout_info, nil, &pipeline.layout) or_return

	shader_stages := make([]vk.PipelineShaderStageCreateInfo, len(shaders), context.temp_allocator)

	for shader, i in shaders {
		shader_stages[i] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = shader.stage,
			module = shader.handle,
			pName  = strings.clone_to_cstring(shader.entrypoint, context.temp_allocator),
		}
	}
}
