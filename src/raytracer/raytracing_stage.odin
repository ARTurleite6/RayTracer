package raytracer

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

}

@(private = "file")
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
