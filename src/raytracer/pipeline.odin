package raytracer

import "core:slice"
import "core:strings"

import vk "vendor:vulkan"

Pipeline_Error :: enum {
	None = 0,
	Cache_Creation_Failed,
	Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Descriptor_Set_Creation_Failed,
	Pool_Creation_Failed,
	Shader_Creation_Failed,
}

Pipeline2 :: struct {
	handle: vk.Pipeline,
	state:  Pipeline_State,
}

Raytracing_Pipeline2 :: struct {
	using pipeline: Pipeline2,
	sbt:            Shader_Binding_Table,
}

Graphics_Pipeline :: struct {
	using pipeline: Pipeline2,
}

Pipeline :: struct {
	handle:                 vk.Pipeline,
	layout:                 vk.PipelineLayout,
	shaders:                [dynamic]vk.PipelineShaderStageCreateInfo,
	descriptor_set_layouts: [dynamic]vk.DescriptorSetLayout,
	push_constant_ranges:   [dynamic]vk.PushConstantRange,
}

Vertex_Input_State :: struct {
	bindings:   [dynamic]vk.VertexInputBindingDescription,
	attributes: [dynamic]vk.VertexInputAttributeDescription,
}

Input_Assembly_State :: struct {
	topology:                 Maybe(vk.PrimitiveTopology),
	primitive_restart_enable: bool,
}

Rasterization_State :: struct {
	depth_clamp_enable, rasterizer_discard_enable: bool,
	polygon_mode:                                  vk.PolygonMode,
	cull_mode:                                     Maybe(vk.CullModeFlags),
	front_face:                                    vk.FrontFace,
	depth_bias_enable:                             bool,
}

Viewport_State :: struct {
	viewport_count: Maybe(u32),
	scissor_count:  Maybe(u32),
}

Multisample_State :: struct {
	rasterization_samples:                         Maybe(vk.SampleCountFlags),
	sample_shading_enable:                         bool,
	min_sample_shading:                            f32,
	sample_mask:                                   vk.SampleMask,
	alpha_to_coverage_enable, alpha_to_one_enable: bool,
}

Stencil_Op_State :: struct {
	fail_op, pass_op, depth_fail_op: Maybe(vk.StencilOp),
	compare_op:                      vk.CompareOp,
}

Depth_Stencil_State :: struct {
	depth_test_enable, depth_write_enable:         Maybe(bool),
	depth_compare_op:                              Maybe(vk.CompareOp),
	depth_bounds_test_enable, stencil_test_enable: bool,
	front, back:                                   Stencil_Op_State,
}

Color_Blend_Attachment_State :: struct {
	blend_enable:           bool,
	src_color_blend_factor: Maybe(vk.BlendFactor),
	dst_color_blend_factor: vk.BlendFactor,
	color_blend_op:         vk.BlendOp,
	src_alpha_blend_factor: Maybe(vk.BlendFactor),
	dst_alpha_blend_factor: vk.BlendFactor,
	alpha_blend_op:         vk.BlendOp,
	color_write_mask:       Maybe(vk.ColorComponentFlags),
}

Color_Blend_State :: struct {
	logic_op_enable: bool,
	logic_op:        vk.LogicOp,
	attachments:     [dynamic]Color_Blend_Attachment_State,
}

Pipeline_State :: struct {
	layout:                                             ^Pipeline_Layout,
	vertex_input:                                       Vertex_Input_State,
	input_assembly:                                     Input_Assembly_State,
	rasterization:                                      Rasterization_State,
	viewport:                                           Viewport_State,
	multisample:                                        Multisample_State,
	depth_stencil:                                      Depth_Stencil_State,
	color_blend:                                        Color_Blend_State,
	color_attachment_formats:                           [dynamic]vk.Format,
	depth_attachment_format, stencil_attachment_format: vk.Format,

	// raytracing
	max_ray_recursion:                                  u32,
	dirty:                                              bool,
}

raytracing_pipeline_init :: proc(
	pipeline: ^Raytracing_Pipeline2,
	ctx: ^Vulkan_Context,
	state: Pipeline_State,
) -> (
	err: vk.Result,
) {
	pipeline.state = state

	shader_stages := to_pipeline_shader_stage_create_info(
		pipeline.state.layout.shader_modules[:],
		ctx,
		context.temp_allocator,
	) or_return
	defer for shader in shader_stages {
		vk.DestroyShaderModule(vulkan_get_device_handle(ctx), shader.module, nil)
	}

	for shader, i in state.layout.shader_modules {
		if .RAYGEN_KHR in shader.stage {
			shader_binding_table_add_group(
				&pipeline.sbt,
				{
					sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
					type = .GENERAL,
					generalShader = u32(i),
					closestHitShader = ~u32(0),
					anyHitShader = ~u32(0),
					intersectionShader = ~u32(0),
				},
				.Ray_Gen,
			)
		} else if .MISS_KHR in shader.stage {
			shader_binding_table_add_group(
				&pipeline.sbt,
				{
					sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
					type = .GENERAL,
					generalShader = u32(i),
					closestHitShader = ~u32(0),
					anyHitShader = ~u32(0),
					intersectionShader = ~u32(0),
				},
				.Miss,
			)
		} else if .CLOSEST_HIT_KHR in shader.stage {

			shader_binding_table_add_group(
				&pipeline.sbt,
				{
					sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
					type = .TRIANGLES_HIT_GROUP,
					generalShader = ~u32(0),
					closestHitShader = u32(i),
					anyHitShader = ~u32(0),
					intersectionShader = ~u32(0),
				},
				.Hit,
			)
		}
	}

	create_info := vk.RayTracingPipelineCreateInfoKHR {
		sType                        = .RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
		stageCount                   = u32(len(pipeline.state.layout.shader_modules)),
		pStages                      = raw_data(shader_stages),
		groupCount                   = u32(len(pipeline.sbt.groups)),
		pGroups                      = raw_data(pipeline.sbt.groups),
		maxPipelineRayRecursionDepth = pipeline.state.max_ray_recursion,
		layout                       = pipeline.state.layout.handle,
	}

	vk_check(
		vk.CreateRayTracingPipelinesKHR(
			vulkan_get_device_handle(ctx),
			0,
			0,
			1,
			&create_info,
			nil,
			&pipeline.handle,
		),
		"Failed to create raytracing pipeline",
	) or_return

	shader_binding_table_build(
		&pipeline.sbt,
		ctx,
		pipeline.handle,
		vulkan_get_raytracing_pipeline_properties(ctx),
	)

	return nil
}

raytracing_pipeline_destroy :: proc(pipeline: ^Raytracing_Pipeline2, ctx: ^Vulkan_Context) {
	vk.DestroyPipeline(vulkan_get_device_handle(ctx), pipeline.handle, nil)
	shader_binding_table_destroy(&pipeline.sbt)
}

graphics_pipeline_init :: proc(
	pipeline: ^Graphics_Pipeline,
	ctx: ^Vulkan_Context,
	state: Pipeline_State,
) -> (
	err: vk.Result,
) {
	pipeline.state = state
	pipeline.state.color_attachment_formats = slice.clone_to_dynamic(
		state.color_attachment_formats[:],
	)
	pipeline.state.color_blend.attachments = slice.clone_to_dynamic(
		state.color_blend.attachments[:],
	)

	shader_stages := to_pipeline_shader_stage_create_info(
		pipeline.state.layout.shader_modules[:],
		ctx,
		context.temp_allocator,
	) or_return
	defer for shader in shader_stages {
		vk.DestroyShaderModule(vulkan_get_device_handle(ctx), shader.module, nil)
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = u32(len(state.vertex_input.bindings)),
		pVertexBindingDescriptions      = raw_data(state.vertex_input.bindings[:]),
		vertexAttributeDescriptionCount = u32(len(state.vertex_input.attributes)),
		pVertexAttributeDescriptions    = raw_data(state.vertex_input.attributes[:]),
	}

	input_assembly_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = state.input_assembly.topology.? or_else .TRIANGLE_STRIP,
		primitiveRestartEnable = b32(state.input_assembly.primitive_restart_enable),
	}

	viewport_state_info := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = state.viewport.viewport_count.? or_else 1,
		scissorCount  = state.viewport.scissor_count.? or_else 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = b32(state.rasterization.depth_clamp_enable),
		rasterizerDiscardEnable = b32(state.rasterization.rasterizer_discard_enable),
		polygonMode             = state.rasterization.polygon_mode,
		cullMode                = state.rasterization.cull_mode.? or_else {.BACK},
		frontFace               = state.rasterization.front_face,
		depthBiasEnable         = b32(state.rasterization.depth_bias_enable),
		depthBiasClamp          = 1.0,
		depthBiasSlopeFactor    = 1.0,
		lineWidth               = 1.0,
	}

	multisample_state_info := vk.PipelineMultisampleStateCreateInfo {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable   = b32(state.multisample.sample_shading_enable),
		rasterizationSamples  = state.multisample.rasterization_samples.? or_else {._1},
		minSampleShading      = state.multisample.min_sample_shading,
		alphaToCoverageEnable = b32(state.multisample.alpha_to_coverage_enable),
		alphaToOneEnable      = b32(state.multisample.alpha_to_one_enable),
	}

	if (state.multisample.sample_mask != {}) {
		multisample_state_info.pSampleMask = &pipeline.state.multisample.sample_mask
	}

	depth_stencil_state := vk.PipelineDepthStencilStateCreateInfo {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable = b32(state.depth_stencil.depth_test_enable.? or_else true),
		depthWriteEnable = b32(state.depth_stencil.depth_write_enable.? or_else true),
		depthCompareOp = state.depth_stencil.depth_compare_op.? or_else .GREATER,
		depthBoundsTestEnable = b32(state.depth_stencil.depth_bounds_test_enable),
		stencilTestEnable = b32(state.depth_stencil.stencil_test_enable),
		front = {
			failOp = state.depth_stencil.front.fail_op.? or_else .REPLACE,
			passOp = state.depth_stencil.front.pass_op.? or_else .REPLACE,
			depthFailOp = state.depth_stencil.front.pass_op.? or_else .REPLACE,
			compareOp = state.depth_stencil.front.compare_op,
			compareMask = ~u32(0),
			writeMask = ~u32(0),
			reference = ~u32(0),
		},
		back = {
			failOp = state.depth_stencil.back.fail_op.? or_else .REPLACE,
			passOp = state.depth_stencil.back.pass_op.? or_else .REPLACE,
			depthFailOp = state.depth_stencil.back.pass_op.? or_else .REPLACE,
			compareOp = state.depth_stencil.back.compare_op,
			compareMask = ~u32(0),
			writeMask = ~u32(0),
			reference = ~u32(0),
		},
	}

	color_blend_state := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = b32(state.color_blend.logic_op_enable),
		logicOp         = state.color_blend.logic_op,
		attachmentCount = u32(len(state.color_blend.attachments)),
		pAttachments    = raw_data(
			to_vk_color_blend_attachment_state(
				state.color_blend.attachments[:],
				context.temp_allocator,
			),
		),
		blendConstants  = {1, 1, 1, 1},
	}

	dynamic_states := [9]vk.DynamicState {
		.VIEWPORT,
		.SCISSOR,
		.LINE_WIDTH,
		.DEPTH_BIAS,
		.BLEND_CONSTANTS,
		.DEPTH_BOUNDS,
		.STENCIL_COMPARE_MASK,
		.STENCIL_WRITE_MASK,
		.STENCIL_REFERENCE,
	}

	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states[:]),
	}

	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = u32(len(state.color_attachment_formats)),
		pColorAttachmentFormats = raw_data(state.color_attachment_formats),
		depthAttachmentFormat   = state.depth_attachment_format,
		stencilAttachmentFormat = state.stencil_attachment_format,
	}

	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_info,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly_info,
		pViewportState      = &viewport_state_info,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisample_state_info,
		pDepthStencilState  = &depth_stencil_state,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state,
		layout              = state.layout.handle,
	}

	return vk.CreateGraphicsPipelines(
		vulkan_get_device_handle(ctx),
		0,
		1,
		&create_info,
		nil,
		&pipeline.handle,
	)
}

graphics_pipeline_destroy :: proc(pipeline: ^Graphics_Pipeline, ctx: ^Vulkan_Context) {
	vk.DestroyPipeline(vulkan_get_device_handle(ctx), pipeline.handle, nil)
	delete(pipeline.state.color_attachment_formats)
	delete(pipeline.state.color_blend.attachments)
}

pipeline_add_shader :: proc(self: ^Pipeline, shader: Shader) {
	append(
		&self.shaders,
		vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = shader.type,
			module = shader.module,
			pName = strings.clone_to_cstring(shader.name),
		},
	)
}

pipeline_add_descriptor_set_layout :: proc(self: ^Pipeline, layout: vk.DescriptorSetLayout) {
	append(&self.descriptor_set_layouts, layout)
}

pipeline_add_push_constant_range :: proc(self: ^Pipeline, range: vk.PushConstantRange) {
	append(&self.push_constant_ranges, range)
}

pipeline_destroy :: proc(self: ^Pipeline, device: vk.Device) {
	if self.handle != 0 {
		vk.DestroyPipeline(device, self.handle, nil)
	}

	if self.layout != 0 {
		vk.DestroyPipelineLayout(device, self.layout, nil)
	}

	delete(self.descriptor_set_layouts)
	delete(self.push_constant_ranges)
	for shader in self.shaders {
		delete(shader.pName)
	}
	delete(self.shaders)
}

pipeline_build_layout :: proc(self: ^Pipeline, device: vk.Device) -> (result: vk.Result) {
	create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(self.descriptor_set_layouts)),
		pSetLayouts            = raw_data(self.descriptor_set_layouts),
		pushConstantRangeCount = u32(len(self.push_constant_ranges)),
		pPushConstantRanges    = raw_data(self.push_constant_ranges),
	}

	return vk_check(
		vk.CreatePipelineLayout(device, &create_info, nil, &self.layout),
		"Failed to create pipeline layout",
	)
}

@(private)
@(require_results)
to_pipeline_shader_stage_create_info :: proc(
	modules: []^Shader_Module,
	ctx: ^Vulkan_Context,
	allocator := context.allocator,
) -> (
	create_infos: []vk.PipelineShaderStageCreateInfo,
	err: vk.Result,
) {
	create_infos = make([]vk.PipelineShaderStageCreateInfo, len(modules), allocator)
	for shader, i in modules {
		module_create_info := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = len(shader.compiled_src) * size_of(u32),
			pCode    = &shader.compiled_src[0],
		}

		module: vk.ShaderModule
		vk_check(
			vk.CreateShaderModule(
				vulkan_get_device_handle(ctx),
				&module_create_info,
				nil,
				&module,
			),
			"Failed to creaste shader module",
		) or_return

		stage_create_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = shader.stage,
			pName  = strings.clone_to_cstring(shader.entry_point, context.temp_allocator),
			module = module,
		}
		create_infos[i] = stage_create_info
	}

	return create_infos, nil
}

@(private)
@(require_results)
to_vk_color_blend_attachment_state :: proc(
	states: []Color_Blend_Attachment_State,
	allocator := context.allocator,
) -> []vk.PipelineColorBlendAttachmentState {
	return slice.mapper(
		states,
		proc(state: Color_Blend_Attachment_State) -> vk.PipelineColorBlendAttachmentState {
			return {
				blendEnable = b32(state.blend_enable),
				srcColorBlendFactor = state.src_color_blend_factor.? or_else .ONE,
				dstColorBlendFactor = state.dst_color_blend_factor,
				colorBlendOp = state.color_blend_op,
				srcAlphaBlendFactor = state.src_alpha_blend_factor.? or_else .ONE,
				dstAlphaBlendFactor = state.dst_alpha_blend_factor,
				alphaBlendOp = state.alpha_blend_op,
				colorWriteMask = state.color_write_mask.? or_else {.R, .G, .B, .A},
			}
		},
		allocator = allocator,
	)
}
