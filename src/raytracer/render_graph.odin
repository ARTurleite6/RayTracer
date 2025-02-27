package raytracer

import "core:fmt"
import "core:slice"
import "core:strings"
import vk "vendor:vulkan"
_ :: fmt

Render_Stage :: struct {
	name:               string,
	reads:              [dynamic]Render_Resource,
	descriptor_layouts: [dynamic]vk.DescriptorSetLayout,
	push_constants:     [dynamic]vk.PushConstantRange,
	// TODO: Possibly in the future add a execute proc pointer
	variant:            Render_Stage_Variant,
}

// TODO: see if this is needed
Render_Data :: struct {
	scene:          ^Scene,
	descriptor_set: vk.DescriptorSet,
}

Render_Stage_Variant :: union {
	^Graphics_Stage,
}

Graphics_Stage :: struct {
	using base:      Render_Stage,
	pipeline:        Pipeline,
	shaders:         [dynamic]vk.PipelineShaderStageCreateInfo,
	vertex_bindings: [dynamic]Vertex_Buffer_Binding,
	format:          vk.Format,
}

Vertex_Buffer_Binding :: struct {
	value:                 u32,
	binding_description:   vk.VertexInputBindingDescription,
	attribute_description: []vk.VertexInputAttributeDescription,
}

Render_Resource :: union {
	Buffer,
}

Render_Graph :: struct {
	stages:    [dynamic]^Render_Stage,
	swapchain: ^Swapchain_Manager,
	device:    ^Device,
}

render_graph_init :: proc(
	graph: ^Render_Graph,
	device: ^Device,
	swapchain: ^Swapchain_Manager,
	allocator := context.allocator,
) {
	graph.stages = make([dynamic]^Render_Stage, allocator)
	graph.swapchain = swapchain
	graph.device = device
}

render_graph_destroy :: proc(graph: ^Render_Graph) {
	for stage in graph.stages {
		render_stage_destroy(stage, graph.device^)
	}
	delete(graph.stages)
	graph.stages = nil
}

render_graph_add_stage :: proc(graph: ^Render_Graph, stage: ^Render_Stage) {
	append(&graph.stages, stage)
}

render_graph_compile :: proc(graph: ^Render_Graph) {
	for stage in graph.stages {
		switch v in stage.variant {
		case ^Graphics_Stage:
			build_graphics_pipeline(v, graph.device^)
		}
	}
}

render_graph_render :: proc(
	graph: ^Render_Graph,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	for stage in graph.stages {
		record_command_buffer(graph^, stage^, cmd, image_index, render_data)
	}
}

render_stage_init :: proc(
	stage: ^Render_Stage,
	name: string,
	variant: Render_Stage_Variant,
	allocator := context.allocator,
) {
	stage.name = name
	stage.reads = make([dynamic]Render_Resource, allocator)
	stage.descriptor_layouts = make([dynamic]vk.DescriptorSetLayout, allocator)
	stage.push_constants = make([dynamic]vk.PushConstantRange, allocator)
	stage.variant = variant
}

render_stage_destroy :: proc(stage: ^Render_Stage, device: Device) {
	switch v in stage.variant {
	case ^Graphics_Stage:
		graphics_stage_destroy(v, device)
	}
	stage.variant = nil

	delete(stage.reads)
	delete(stage.descriptor_layouts)
	delete(stage.push_constants)
	stage.reads = nil
	stage.descriptor_layouts = nil
	stage.push_constants = nil
}

render_stage_use_descriptor_layout :: proc(stage: ^Render_Stage, layout: vk.DescriptorSetLayout) {
	append(&stage.descriptor_layouts, layout)
}

render_stage_use_push_constant_range :: proc(stage: ^Render_Stage, range: vk.PushConstantRange) {
	append(&stage.push_constants, range)
}

graphics_stage_init :: proc(stage: ^Graphics_Stage, name: string, allocator := context.allocator) {
	render_stage_init(stage, name, stage, allocator = allocator)
	stage.vertex_bindings = make([dynamic]Vertex_Buffer_Binding, allocator)
}

graphics_stage_destroy :: proc(stage: ^Graphics_Stage, device: Device) {
	vk.DestroyPipelineLayout(device.logical_device.ptr, stage.pipeline.layout, nil)
	vk.DestroyPipeline(device.logical_device.ptr, stage.pipeline.handle, nil)
	delete(stage.shaders)
	delete(stage.vertex_bindings)
	stage.vertex_bindings = nil
	stage.shaders = nil
	stage.vertex_bindings = nil
	free(stage)
}

graphics_stage_use_vertex_buffer_binding :: proc(
	stage: ^Graphics_Stage,
	binding: u32,
	attribute_description: []vk.VertexInputAttributeDescription,
	binding_description: vk.VertexInputBindingDescription,
) {
	append(
		&stage.vertex_bindings,
		Vertex_Buffer_Binding {
			value = binding,
			attribute_description = attribute_description,
			binding_description = binding_description,
		},
	)
}

graphics_stage_use_format :: proc(stage: ^Graphics_Stage, format: vk.Format) {
	stage.format = format
}

graphics_stage_use_shader :: proc(stage: ^Graphics_Stage, shader: Shader) {
	append(
		&stage.shaders,
		vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = shader.type,
			module = shader.module,
			pName = strings.clone_to_cstring(shader.name, context.temp_allocator),
		},
	)
}

@(private = "file")
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

@(private = "file")
record_command_buffer :: proc(
	graph: Render_Graph,
	stage: Render_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	if graphics_stage, ok := stage.variant.(^Graphics_Stage); ok {
		graphics_stage_render(graph, graphics_stage, cmd, image_index, render_data)
	}
}

graphics_stage_render :: proc(
	graph: Render_Graph,
	graphics_stage: ^Graphics_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {

	begin_render_pass(graph, graphics_stage, cmd, image_index)

	vk.CmdBindPipeline(cmd, .GRAPHICS, graphics_stage.pipeline.handle)
	if render_data.descriptor_set != 0 {
		descriptor_set := render_data.descriptor_set
		vk.CmdBindDescriptorSets(
			cmd,
			.GRAPHICS,
			graphics_stage.pipeline.layout,
			0,
			1,
			&descriptor_set,
			0,
			nil,
		)
	}

	scene_draw(render_data.scene, cmd, graphics_stage.pipeline.layout)

	end_render_pass(cmd)

	image_transition(
		cmd,
		{
			image = graph.swapchain.images[image_index],
			old_layout = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout = .PRESENT_SRC_KHR,
			src_stage = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage = {.BOTTOM_OF_PIPE},
			src_access = {.COLOR_ATTACHMENT_WRITE},
			dst_access = {},
		},
	)
}

@(private = "file")
begin_render_pass :: proc(
	render_graph: Render_Graph,
	stage: ^Graphics_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
) {
	image, image_view := swapchain_manager_get_image(render_graph.swapchain^, image_index)

	image_transition(
		cmd,
		{
			image = image,
			old_layout = .UNDEFINED,
			new_layout = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage = {.TOP_OF_PIPE},
			dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
			src_access = {},
			dst_access = {.COLOR_ATTACHMENT_WRITE},
		},
	)

	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = vk.ClearValue{color = vk.ClearColorValue{float32 = {0.01, 0.01, 0.01, 1.0}}},
	}

	extent := render_graph.swapchain.extent
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	viewport := vk.Viewport {
		minDepth = 0,
		maxDepth = 1,
		width    = f32(extent.width),
		height   = f32(extent.height),
	}

	scissor := vk.Rect2D {
		extent = extent,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)
	vk.CmdSetScissor(cmd, 0, 1, &scissor)
}

@(private = "file")
end_render_pass :: proc(cmd: vk.CommandBuffer) {
	vk.CmdEndRendering(cmd)
}
