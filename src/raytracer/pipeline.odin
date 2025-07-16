package raytracer

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
	topology: vk.PrimitiveTopology,
}

Rasterization_State :: struct {
	depth_clamp_enable:        bool,
	rasterizer_discard_enable: bool,
	polygon_mode:              vk.PolygonMode,
	cull_mode:                 vk.CullModeFlags,
	front_face:                vk.FrontFace,
	depth_bias_enable:         bool,
}

Viewport_State :: struct {
	viewport_count: u32,
	scissor_count:  u32,
}

Pipeline_State :: struct {
	layout:            ^Pipeline_Layout,
	vertex_input:      Vertex_Input_State,
	input_assembly:    Input_Assembly_State,
	rasterization:     Rasterization_State,
	viewport:          Viewport_State,

	// raytracing
	max_ray_recursion: u32,
	dirty:             bool,
}

raytracing_pipeline_init :: proc(
	pipeline: ^Raytracing_Pipeline2,
	ctx: ^Vulkan_Context,
	state: Pipeline_State,
) -> (
	err: vk.Result,
) {
	pipeline.state = state

	shader_stages := to_pipeline_shader_stage_craete_info(
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
) {
	pipeline.state = state

	shader_stages := to_pipeline_shader_stage_craete_info(
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
		topology               = state.input_assembly.topology,
		primitiveRestartEnable = false,
	}

	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly_info,
	}
}

graphics_pipeline_destroy :: proc(pipeline: ^Graphics_Pipeline, ctx: ^Vulkan_Context) {
	vk.DestroyPipeline(vulkan_get_device_handle(ctx), pipeline.handle, nil)
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
to_pipeline_shader_stage_craete_info :: proc(
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
