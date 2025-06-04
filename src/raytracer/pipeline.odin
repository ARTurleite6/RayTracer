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

Pipeline :: struct {
	handle:                 vk.Pipeline,
	layout:                 vk.PipelineLayout,
	shaders:                [dynamic]vk.PipelineShaderStageCreateInfo,
	descriptor_set_layouts: [dynamic]vk.DescriptorSetLayout,
	push_constant_ranges:   [dynamic]vk.PushConstantRange,
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
