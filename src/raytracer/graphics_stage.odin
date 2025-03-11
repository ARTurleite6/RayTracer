package raytracer

import "core:fmt"
import "core:slice"
import "core:strings"
import vk "vendor:vulkan"
_ :: fmt

Graphics_Stage :: struct {
	using base:      Render_Stage,
	pipeline:        Pipeline,
	shaders:         [dynamic]vk.PipelineShaderStageCreateInfo,
	vertex_bindings: []Vertex_Buffer_Binding,
	format:          vk.Format,
}

graphics_stage_init :: proc(
	stage: ^Graphics_Stage,
	name: string,
	shaders: []Shader,
	format: vk.Format,
	vertex_bindings: []Vertex_Buffer_Binding = {},
	allocator := context.allocator,
) {
	render_stage_init(stage, name, stage, allocator = allocator)
	stage.format = format

	stage.vertex_bindings = slice.clone(vertex_bindings, allocator)

	for shader in shaders {
		append(
			&stage.shaders,
			vk.PipelineShaderStageCreateInfo {
				sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage = shader.type,
				module = shader.module,
				pName = strings.clone_to_cstring(shader.name),
			},
		)
	}
}

graphics_stage_destroy :: proc(stage: ^Graphics_Stage, device: Device) {
	vk.DestroyPipelineLayout(device.logical_device.ptr, stage.pipeline.layout, nil)
	vk.DestroyPipeline(device.logical_device.ptr, stage.pipeline.handle, nil)
	delete(stage.shaders)
	delete(stage.vertex_bindings)
	stage.vertex_bindings = nil
	stage.shaders = nil
	stage.vertex_bindings = nil
}

graphics_stage_render :: proc(
	graph: Render_Graph,
	graphics_stage: ^Graphics_Stage,
	buffer: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	cmd := Command_Buffer {
		buffer = buffer,
	}

	ctx_transition_swapchain_image(
		graph.ctx^,
		cmd,
		old_layout = .UNDEFINED,
		new_layout = .COLOR_ATTACHMENT_OPTIMAL,
		src_stage = {.TOP_OF_PIPE},
		dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
		src_access = {},
		dst_access = {.COLOR_ATTACHMENT_WRITE},
	)

	info := ctx_get_swapchain_render_pass(graph.ctx^)
	command_buffer_begin_render_pass(&cmd, &info)
	command_buffer_bind_pipeline(&cmd, .GRAPHICS, graphics_stage.pipeline.handle)

	descriptor_set := descriptor_manager_get_descriptor_set_index(
		render_data.descriptor_manager^,
		"camera",
		render_data.frame_index,
	)

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.GRAPHICS,
		graphics_stage.pipeline.layout,
		0,
		1,
		&descriptor_set,
		0,
		nil,
	)

	scene_draw(&render_data.renderer.scene, cmd.buffer, graphics_stage.pipeline.layout)

	command_buffer_end_render_pass(&cmd)

	ctx_transition_swapchain_image(
		graph.ctx^,
		cmd,
		old_layout = .COLOR_ATTACHMENT_OPTIMAL,
		new_layout = .PRESENT_SRC_KHR,
		src_stage = {.COLOR_ATTACHMENT_OUTPUT},
		dst_stage = {.BOTTOM_OF_PIPE},
		src_access = {.COLOR_ATTACHMENT_WRITE},
		dst_access = {},
	)
}


@(private)
build_graphics_pipeline :: proc(stage: ^Graphics_Stage, device: Device) -> Render_Error {
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}

	bindings := slice.mapper(
		stage.vertex_bindings[:],
		proc(b: Vertex_Buffer_Binding) -> vk.VertexInputBindingDescription {
			return b.binding_description
		},
		context.temp_allocator,
	)

	attribute_descriptions := make(
		[dynamic]vk.VertexInputAttributeDescription,
		allocator = context.temp_allocator,
	)

	for attr in stage.vertex_bindings {
		for b in attr.attribute_description {
			append_elem(&attribute_descriptions, b)
		}
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = u32(len(bindings)),
		pVertexBindingDescriptions      = raw_data(bindings),
		vertexAttributeDescriptionCount = u32(len(attribute_descriptions)),
		pVertexAttributeDescriptions    = raw_data(attribute_descriptions),
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
		frontFace               = .COUNTER_CLOCKWISE,
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

	// TODO: its possible for this to be changed in the future

	descriptor_layouts := stage.descriptor_layouts[:]

	{ 	// create pipeline layout

		create_info := vk.PipelineLayoutCreateInfo {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = u32(len(descriptor_layouts)),
			pSetLayouts            = raw_data(descriptor_layouts),
			pushConstantRangeCount = u32(len(stage.push_constants)),
			pPushConstantRanges    = raw_data(stage.push_constants[:]),
		}

		vk.CreatePipelineLayout(
			device.logical_device.ptr,
			&create_info,
			nil,
			&stage.pipeline.layout,
		)
	}

	pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &stage.format,
	}

	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_create_info,
		stageCount          = u32(len(stage.shaders)),
		pStages             = raw_data(stage.shaders),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly_info,
		pViewportState      = &viewport_state_info,
		pRasterizationState = &rasterization_info,
		pMultisampleState   = &multisampling_info,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state,
		layout              = stage.pipeline.layout,
	}

	if result := vk.CreateGraphicsPipelines(
		device.logical_device.ptr,
		0,
		1,
		&create_info,
		nil,
		&stage.pipeline.handle,
	); result != .SUCCESS {
		return .Pipeline_Creation_Failed
	}

	return nil
}
