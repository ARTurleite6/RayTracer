package raytracer

import "core:os"
import "core:strings"

import spirv "external:odin-spirv-reflect"
import vk "vendor:vulkan"

Shader_Error :: enum {
	None = 0,
	File_Non_Existent,
	Shader_Creation_Error,
}

Resource_Layout :: struct {
	sets: [dynamic]Descriptor_Set_Layout_Info,
}

Descriptor_Set_Layout_Info :: struct {
	set:      u32,
	bindings: [dynamic]vk.DescriptorSetLayoutBinding,
}

Pipeline_Layout :: struct {
	handle:                 vk.PipelineLayout,
	descriptor_set_layouts: []Descriptor_Set_Layout,
}

Shader :: struct {
	name:        string,
	entry_point: string,
	type:        vk.ShaderStageFlags,
	module:      vk.ShaderModule,
	device:      vk.Device,
	code:        []u8,
}

shader_init :: proc(
	shader: ^Shader,
	device: vk.Device,
	path: string,
	allocator := context.allocator,
) -> (
	err: Shader_Error,
) {
	shader.device = device

	data, ok := os.read_entire_file(path, allocator = allocator)
	if !ok {
		return .File_Non_Existent
	}

	shader.code = data

	content := transmute([]u32)data

	spirv_module: spirv.ShaderModule
	result := spirv.CreateShaderModule(len(data), raw_data(data), &spirv_module)
	assert(result == .SUCCESS)
	defer spirv.DestroyShaderModule(&spirv_module)

	shader.name = strings.clone_from_cstring(spirv_module.entry_point_name)
	shader.entry_point = strings.clone_from_cstring(spirv_module.entry_point_name)
	shader.type = spirv_module.shader_stage

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(content),
		pCode    = &content[0],
	}

	if vk_check(
		   vk.CreateShaderModule(device, &create_info, nil, &shader.module),
		   "Failed to create shader module",
	   ) !=
	   .SUCCESS {
		return .Shader_Creation_Error
	}

	return .None
}

// TODO: create function to create shader program,
// that using reflection it creates both the descriptor set layouts and the pipeline layout

shader_destroy :: proc(shader: ^Shader) {
	vk.DestroyShaderModule(shader.device, shader.module, nil)
	shader.module = 0
	delete(shader.name)
	delete(shader.entry_point)
	delete(shader.code)
}
