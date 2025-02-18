package raytracer

import "core:strings"
import vk "vendor:vulkan"

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

make_graphics_pipeline :: proc(
	device: Device,
	swapchain: Swapchain,
	shaders: []Shader_Module,
) -> (
	pipeline: Pipeline,
	result: vk.Result,
) {
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}

	vertex_binding_info := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Vertex),
		inputRate = .VERTEX,
	}

	pos_vertex_attribute_info := vk.VertexInputAttributeDescription {
		binding  = 0,
		location = 0,
		format   = .R32G32B32_SFLOAT,
		offset   = u32(offset_of(Vertex, position)),
	}

	color_vertex_attribute_info := vk.VertexInputAttributeDescription {
		binding  = 0,
		location = 1,
		format   = .R32G32B32_SFLOAT,
		offset   = u32(offset_of(Vertex, color)),
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &vertex_binding_info,
		vertexAttributeDescriptionCount = 2,
		pVertexAttributeDescriptions    = raw_data(
			[]vk.VertexInputAttributeDescription {
				pos_vertex_attribute_info,
				color_vertex_attribute_info,
			},
		),
	}

	input_assembly_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewport_state_info := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterization_info := vk.PipelineRasterizationStateCreateInfo {
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

	{ 	// create pipeline layout
		create_info := vk.PipelineLayoutCreateInfo {
			sType = .PIPELINE_LAYOUT_CREATE_INFO,
		}

		vk.CreatePipelineLayout(device.handle, &create_info, nil, &pipeline.layout) or_return
	}

	shader_stages := make([]vk.PipelineShaderStageCreateInfo, len(shaders), context.temp_allocator)

	for shader, i in shaders {
		shader_stages[i] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = shader.stage,
			module = shader.handle,
			pName  = strings.clone_to_cstring(shader.entrypoint, context.temp_allocator),
		}
	}

	swapchain_format := swapchain.format.format
	pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &swapchain_format,
	}

	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_create_info,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly_info,
		pViewportState      = &viewport_state_info,
		pRasterizationState = &rasterization_info,
		pMultisampleState   = &multisampling_info,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state,
		layout              = pipeline.layout,
	}

	vk.CreateGraphicsPipelines(device.handle, 0, 1, &create_info, nil, &pipeline.handle) or_return

	for s in shaders {
		delete_shader_module(device, s)
	}

	return
}

delete_pipeline :: proc(pipeline: Pipeline, device: Device) {
	vk.DestroyPipelineLayout(device.handle, pipeline.layout, nil)
	vk.DestroyPipeline(device.handle, pipeline.handle, nil)
}
