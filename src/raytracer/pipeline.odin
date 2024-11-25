package raytracer

import vk "vendor:vulkan"

Pipeline :: struct {
	handle:  vk.Pipeline,
	layout:  vk.PipelineLayout,
	shaders: []^Shader,
}

pipeline_init :: proc(
	pipeline: Pipeline,
	device: Device,
	swapchain: Swapchain,
	shaders: []^Shader,
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

	viewport := vk.Viewport {
		x        = 0.0,
		y        = 0.0,
		width    = f32(swapchain.extent.width),
		height   = f32(swapchain.extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	scissor := vk.Rect2D {
		offset = {},
		extent = swapchain.extent,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
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

	// TODO: Finish creating the pipeline and create graphics pass
}

pipeline_destroy :: proc(pipeline: Pipeline, device: Device) {
	delete(pipeline.shaders)
	vk.DestroyPipelineLayout(device, pipeline.layout, nil)
	vk.DestroyPipeline(device, pipeline.handle, nil)
}
