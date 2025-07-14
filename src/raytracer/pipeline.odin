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

Pipeline :: struct {
	handle:                 vk.Pipeline,
	layout:                 vk.PipelineLayout,
	shaders:                [dynamic]vk.PipelineShaderStageCreateInfo,
	descriptor_set_layouts: [dynamic]vk.DescriptorSetLayout,
	push_constant_ranges:   [dynamic]vk.PushConstantRange,
}

Pipeline_State :: struct {
	layout:            ^Pipeline_Layout,

	// raytracing
	max_ray_recursion: u32,
}

raytracing_pipeline_init :: proc(
	pipeline: ^Raytracing_Pipeline2,
	ctx: ^Vulkan_Context,
	state: Pipeline_State,
) -> (
	err: vk.Result,
) {
	pipeline.state = state

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

	shader_stages := make(
		[dynamic]vk.PipelineShaderStageCreateInfo,
		0,
		len(pipeline.state.layout.shader_modules),
	)
	defer delete(shader_stages)
	shader_modules := make([dynamic]vk.ShaderModule, 0, len(pipeline.state.layout.shader_modules))
	defer {
		defer for module in shader_modules {
			vk.DestroyShaderModule(vulkan_get_device_handle(ctx), module, nil)
		}

		delete(shader_modules)
	}

	for s in pipeline.state.layout.shader_modules {
		module_create_info := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = len(s.compiled_src) * size_of(u32),
			pCode    = &s.compiled_src[0],
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

		append(&shader_modules, module)

		stage_create_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = s.stage,
			pName  = strings.clone_to_cstring(s.entry_point, context.temp_allocator),
			module = module,
		}

		append(&shader_stages, stage_create_info)
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
