package raytracer

import "core:fmt"
import vk "vendor:vulkan"

Raytracing_Stage :: struct {
	using base:    Render_Stage,
	pipeline:      Pipeline,
	shaders:       [dynamic]vk.PipelineShaderStageCreateInfo,
	shader_groups: [dynamic]vk.RayTracingShaderGroupCreateInfoKHR,
}

raytracing_stage_init :: proc(stage: ^Raytracing_Stage, allocator := context.allocator) {
	render_stage_init(stage, "ray tracing", stage)
	stage.shaders = make([dynamic]vk.PipelineShaderStageCreateInfo, allocator)
	stage.shader_groups = make([dynamic]vk.RayTracingShaderGroupCreateInfoKHR, allocator)
}

raytracing_stage_destroy :: proc(stage: ^Raytracing_Stage) {
	delete(stage.shaders)
	delete(stage.shader_groups)
	stage^ = {}
}

raytracing_render :: proc(
	graph: Render_Graph,
	stage: ^Raytracing_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	vk.CmdBindPipeline(cmd, .RAY_TRACING_KHR, stage.pipeline.handle)

	descriptor_set := render_data.descriptor_set
	vk.CmdBindDescriptorSets(
		cmd,
		.RAY_TRACING_KHR,
		stage.pipeline.layout,
		0,
		1,
		&descriptor_set,
		0,
		nil,
	)

	// Get properties for SBT
	rt_props: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR
	props2: vk.PhysicalDeviceProperties2 = {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &rt_props,
	}
	vk.GetPhysicalDeviceProperties2(render_data.renderer.ctx.device.physical_device.ptr, &props2)

	// Build shader binding table
	sbt: Shader_Binding_Table
	sbt_init(&sbt, render_data.renderer.ctx.device, stage.pipeline.handle, rt_props)
	// defer sbt_destroy(&sbt)

	// Add shader records
	sbt_add_ray_gen_shader(&sbt, 0) // RayGen group
	sbt_add_miss_shader(&sbt, 1) // Miss group
	sbt_add_hit_shader(&sbt, 2) // Hit group

	// Build the SBT
	if err := sbt_build(&sbt); err != nil {
		fmt.eprintln("Failed to build shader binding table:", err)
		return
	}

	// Get swapchain extent
	extent := graph.swapchain.extent

	// Trace rays
	vk.CmdTraceRaysKHR(
		cmd,
		&sbt.sections[.Ray_Gen].region,
		&sbt.sections[.Miss].region,
		&sbt.sections[.Hit].region,
		&vk.StridedDeviceAddressRegionKHR{}, // Empty callable region
		extent.width,
		extent.height,
		1,
	)
}

@(private)
build_raytracing_pipeline :: proc(stage: ^Raytracing_Stage, device: Device) {
	{ 	// create pipeline layout
		create_info := vk.PipelineLayoutCreateInfo {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = u32(len(stage.descriptor_layouts)),
			pSetLayouts            = raw_data(stage.descriptor_layouts),
			pushConstantRangeCount = u32(len(stage.push_constants)),
			pPushConstantRanges    = raw_data(stage.push_constants[:]),
		}

		_ = vk_check(
			vk.CreatePipelineLayout(
				device.logical_device.ptr,
				&create_info,
				nil,
				&stage.pipeline.layout,
			),
			"Failed to create raytracing pipeline layout",
		)
	}

	create_info := vk.RayTracingPipelineCreateInfoKHR {
		sType                        = .RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
		stageCount                   = u32(len(stage.shaders)),
		pStages                      = raw_data(stage.shaders),
		groupCount                   = u32(len(stage.shader_groups)),
		pGroups                      = raw_data(stage.shader_groups),
		maxPipelineRayRecursionDepth = 1,
		layout                       = stage.pipeline.layout,
	}

	_ = vk_check(
		vk.CreateRayTracingPipelinesKHR(
			device.logical_device.ptr,
			0,
			0,
			1,
			&create_info,
			nil,
			&stage.pipeline.handle,
		),
		"Failed to create ray tracing pipeline",
	)
}

@(private)
simple_raytracing_pipeline :: proc(
	renderer: ^Renderer,
	raygen_shader, miss_shader, closest_hit_shader: string,
	allocator := context.allocator,
) -> (
	stage: ^Raytracing_Stage,
	err: Pipeline_Error,
) {
	stage = new(Raytracing_Stage, allocator)

	if stage == nil {
		return nil, .Pipeline_Creation_Failed
	}

	raytracing_stage_init(stage, allocator)

	// Add color attachment for swapchain
	render_stage_add_color_attachment(
		stage,
		.CLEAR,
		.STORE,
		vk.ClearValue{color = {float32 = {0.0, 0.0, 0.2, 1.0}}},
	)

	ds_layout_bindings := []vk.DescriptorSetLayoutBinding {
		// Top-level acceleration structure binding
		{
			binding = 0,
			descriptorType = .ACCELERATION_STRUCTURE_KHR,
			descriptorCount = 1,
			stageFlags = {.RAYGEN_KHR, .CLOSEST_HIT_KHR},
		},
		// Output image binding
		{
			binding = 1,
			descriptorType = .STORAGE_IMAGE,
			descriptorCount = 1,
			stageFlags = {.RAYGEN_KHR},
		},
		// Camera uniform buffer
		{
			binding = 2,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.RAYGEN_KHR},
		},
	}

	descriptor_layout: vk.DescriptorSetLayout
	ds_layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(ds_layout_bindings)),
		pBindings    = raw_data(ds_layout_bindings),
	}

	_ = vk_check(
		vk.CreateDescriptorSetLayout(
			renderer.ctx.device.logical_device.ptr,
			&ds_layout_info,
			nil,
			&descriptor_layout,
		),
		"Failed to create ray tracing descriptor layout",
	)

	render_stage_use_descriptor_layout(stage, descriptor_layout)

	push_constant_range := vk.PushConstantRange {
		stageFlags = {.RAYGEN_KHR, .CLOSEST_HIT_KHR, .MISS_KHR},
		offset     = 0,
		size       = 128, // Allow up to 128 bytes of push constants
	}

	render_stage_use_push_constant_range(stage, push_constant_range)

	shaders: [3]Shader
	// Load shaders
	_ = shader_init(
		&shaders[0],
		renderer.ctx.device,
		name = "raygen",
		entry_point = "main",
		path = raygen_shader,
		type = {.RAYGEN_KHR},
	)

	_ = shader_init(
		&shaders[1],
		renderer.ctx.device,
		name = "miss",
		entry_point = "main",
		path = miss_shader,
		type = {.MISS_KHR},
	)

	_ = shader_init(
		&shaders[2],
		renderer.ctx.device,
		name = "closest_hit",
		entry_point = "main",
		path = closest_hit_shader,
		type = {.CLOSEST_HIT_KHR},
	)

	// Define shader stages
	raygen_stage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.RAYGEN_KHR},
		module = shaders[0].module,
		pName  = "main",
	}
	append(&stage.shaders, raygen_stage)

	miss_stage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.MISS_KHR},
		module = shaders[1].module,
		pName  = "main",
	}
	append(&stage.shaders, miss_stage)

	chit_stage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.CLOSEST_HIT_KHR},
		module = shaders[2].module,
		pName  = "main",
	}
	append(&stage.shaders, chit_stage)

	// Define shader groups
	raygen_group := vk.RayTracingShaderGroupCreateInfoKHR {
		sType              = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
		type               = .GENERAL,
		generalShader      = 0, // Index of raygen shader
		closestHitShader   = ~u32(0),
		anyHitShader       = ~u32(0),
		intersectionShader = ~u32(0),
	}
	append(&stage.shader_groups, raygen_group)

	miss_group := vk.RayTracingShaderGroupCreateInfoKHR {
		sType              = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
		type               = .GENERAL,
		generalShader      = 1, // Index of miss shader
		closestHitShader   = ~u32(0),
		anyHitShader       = ~u32(0),
		intersectionShader = ~u32(0),
	}
	append(&stage.shader_groups, miss_group)

	hit_group := vk.RayTracingShaderGroupCreateInfoKHR {
		sType              = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
		type               = .TRIANGLES_HIT_GROUP,
		generalShader      = ~u32(0),
		closestHitShader   = 2, // Index of closest hit shader
		anyHitShader       = ~u32(0),
		intersectionShader = ~u32(0),
	}
	append(&stage.shader_groups, hit_group)

	return stage, nil
}
