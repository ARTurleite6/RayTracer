package raytracer

import vk "vendor:vulkan"


Pipeline_Manager :: struct {
	device:         ^Device,
	pipeline_cache: vk.PipelineCache, // TODO: this for now is not to be used
}

Pipeline_Error :: enum {
	None = 0,
	Cache_Creation_Failed,
	Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Descriptor_Set_Creation_Failed,
	Pool_Creation_Failed,
	Shader_Creation_Failed,
}

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
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
	vk.DestroyPipelineCache(manager.device.logical_device.ptr, manager.pipeline_cache, nil)
}
