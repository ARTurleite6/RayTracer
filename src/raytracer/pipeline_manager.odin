package raytracer

import "core:os"
import "core:strings"
import vk "vendor:vulkan"

Pipeline_Type :: enum {
	Graphics,
	Compute,
	Ray_Tracing,
}

Pipeline_Manager :: struct {
	device:             ^Device,
	pipelines:          map[string]Pipeline,
	descriptor_layouts: map[string]vk.DescriptorSetLayout,
	pipeline_cache:     vk.PipelineCache, // TODO: this for now is not to be used
}

Pipeline_Error :: enum {
	None = 0,
	Cache_Creation_Failed,
	Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Shader_Creation_Failed,
}

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
	type:   Pipeline_Type,
}

Pipeline_Config :: struct {
	descriptor_layouts: []vk.DescriptorSetLayout,
	shader_stages:      []Shader_Stage_Info,
	color_attachment:   vk.Format,
	push_contant_range: vk.PushConstantRange,
}

Shader_Stage_Info :: struct {
	stage:     vk.ShaderStageFlags,
	entry:     cstring,
	file_path: string,
}

pipeline_manager_init :: proc(
	manager: ^Pipeline_Manager,
	device: ^Device,
	allocator := context.allocator,
) -> (
	err: Pipeline_Error,
) {
	manager.device = device
	manager.pipelines = make(map[string]Pipeline)
	manager.descriptor_layouts = make(map[string]vk.DescriptorSetLayout)

	cache_info := vk.PipelineCacheCreateInfo {
		sType = .PIPELINE_CACHE_CREATE_INFO,
	}

	if vk.CreatePipelineCache(
		   device.logical_device.ptr,
		   &cache_info,
		   nil,
		   &manager.pipeline_cache,
	   ) !=
	   .SUCCESS {
		return .Cache_Creation_Failed
	}

	return .None
}

pipeline_manager_destroy :: proc(manager: ^Pipeline_Manager) {
	for name, pipeline in manager.pipelines {
		vk.DestroyPipeline(manager.device.logical_device.ptr, pipeline.handle, nil)
		vk.DestroyPipelineLayout(manager.device.logical_device.ptr, pipeline.layout, nil)
		delete(name)
	}
	delete(manager.pipelines)

	vk.DestroyPipelineCache(manager.device.logical_device.ptr, manager.pipeline_cache, nil)
}

pipeline_manager_bind_pipeline :: proc(
	manager: Pipeline_Manager,
	name: string,
	cmd: vk.CommandBuffer,
) -> Pipeline {
	pipeline := manager.pipelines[name]
	vk.CmdBindPipeline(cmd, pipeline_type_bind_point(pipeline.type), pipeline.handle)

	return pipeline
}

@(require_results)
create_graphics_pipeline :: proc(
	manager: ^Pipeline_Manager,
	name: string,
	config: Pipeline_Config,
	allocator := context.allocator,
) -> (
	result: Pipeline_Error,
) {
	pipeline: Pipeline

	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &VERTEX_INPUT_BINDING_DESCRIPTION,
		vertexAttributeDescriptionCount = len(VERTEX_INPUT_ATTRIBUTE_DESCRIPTION),
		pVertexAttributeDescriptions    = raw_data(VERTEX_INPUT_ATTRIBUTE_DESCRIPTION[:]),
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

	// TODO: its possible for this to be changed in the future
	push_constant_range := vk.PushConstantRange {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = size_of(Push_Constants),
	}

	descriptor_layouts := config.descriptor_layouts

	{ 	// create pipeline layout

		create_info := vk.PipelineLayoutCreateInfo {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = u32(len(descriptor_layouts)),
			pSetLayouts            = raw_data(descriptor_layouts),
			pushConstantRangeCount = 1,
			pPushConstantRanges    = &push_constant_range,
		}

		vk.CreatePipelineLayout(
			manager.device.logical_device.ptr,
			&create_info,
			nil,
			&pipeline.layout,
		)
	}

	shader_stages := make([dynamic]vk.PipelineShaderStageCreateInfo, context.temp_allocator)
	shader_modules := make([dynamic]vk.ShaderModule, context.temp_allocator)
	defer {
		for shader in shader_modules {
			vk.DestroyShaderModule(manager.device.logical_device.ptr, shader, nil)
		}
	}
	for stage in config.shader_stages {
		shader_module := create_shader_module(manager.device, stage.file_path) or_return

		stage_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = stage.stage,
			module = shader_module,
			pName  = stage.entry,
		}

		append(&shader_stages, stage_info)
		append(&shader_modules, shader_module)
	}

	color_attachment := config.color_attachment
	pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &color_attachment,
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

	if result := vk.CreateGraphicsPipelines(
		manager.device.logical_device.ptr,
		0,
		1,
		&create_info,
		nil,
		&pipeline.handle,
	); result != .SUCCESS {
		return .Pipeline_Creation_Failed
	}

	pipeline.type = .Graphics

	manager.pipelines[strings.clone(name, allocator)] = pipeline

	return .None
}

create_shader_module :: proc(
	device: ^Device,
	file_path: string,
) -> (
	shader: vk.ShaderModule,
	err: Pipeline_Error,
) {
	data, ok := os.read_entire_file(file_path)
	if !ok {
		return {}, .Shader_Creation_Failed
	}
	content := string(data)
	code := transmute([]u32)content

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = &code[0],
	}

	if result := vk.CreateShaderModule(device.logical_device.ptr, &create_info, nil, &shader);
	   result != .SUCCESS {
		return {}, .Shader_Creation_Failed
	}

	return shader, .None
}

pipeline_type_bind_point :: proc(type: Pipeline_Type) -> vk.PipelineBindPoint {
	switch type {
	case .Compute:
		return .COMPUTE
	case .Graphics:
		return .GRAPHICS
	case .Ray_Tracing:
		return .RAY_TRACING_NV
	}

	return {}
}
