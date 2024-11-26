package raytracer

import "core:mem"
import "core:strings"
import vk "vendor:vulkan"

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

pipeline_init :: proc(
	pipeline: ^Pipeline,
	device: Device,
	swapchain: Swapchain,
	render_pass: vk.RenderPass,
	shaders: []Shader,
	temp_allocator: mem.Allocator,
) -> vk.Result {
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}

	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	assembly_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = {.BACK},
		frontFace               = .CLOCKWISE,
		lineWidth               = 1,
	}

	multisampling_info := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false,
	}

	color_blend_state := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	{ 	// pipeline layout (uniforms and such)
		create_info := vk.PipelineLayoutCreateInfo {
			sType = .PIPELINE_LAYOUT_CREATE_INFO,
		}

		if result := vk.CreatePipelineLayout(device, &create_info, nil, &pipeline.layout);
		   result != .SUCCESS {
			return result
		}
	}


	// TODO: Finish creating the pipeline
	{
		stages := make([]vk.PipelineShaderStageCreateInfo, len(shaders), temp_allocator)
		for shader, i in shaders {
			stages[i] = vk.PipelineShaderStageCreateInfo {
				sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage  = shader.stage,
				module = shader.module,
				pName  = strings.clone_to_cstring(shader.entrypoint, temp_allocator),
			}
		}

		create_info := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			stageCount          = u32(len(stages)),
			pStages             = raw_data(stages),
			pVertexInputState   = &vertex_input_info,
			pInputAssemblyState = &assembly_info,
			pViewportState      = &viewport_state,
			pRasterizationState = &rasterizer,
			pMultisampleState   = &multisampling_info,
			pColorBlendState    = &color_blend_state,
			pDynamicState       = &dynamic_state,
			layout              = pipeline.layout,
			renderPass          = render_pass,
			subpass             = 0,
		}

		if result := vk.CreateGraphicsPipelines(device, 0, 1, &create_info, nil, &pipeline.handle);
		   result != .SUCCESS {
			return result
		}
	}

	return .SUCCESS
}

pipeline_destroy :: proc(pipeline: Pipeline, device: Device) {
	vk.DestroyPipelineLayout(device, pipeline.layout, nil)
	vk.DestroyPipeline(device, pipeline.handle, nil)
}
