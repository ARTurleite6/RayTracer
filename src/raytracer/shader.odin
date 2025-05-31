package raytracer

import "core:os"
import vk "vendor:vulkan"

Shader_Error :: enum {
	None = 0,
	File_Non_Existent,
	Shader_Creation_Error,
}

Shader :: struct {
	name:        string,
	entry_point: string,
	type:        vk.ShaderStageFlags,
	module:      vk.ShaderModule,
	device:      vk.Device,
}

shader_init :: proc(
	shader: ^Shader,
	device: vk.Device,
	name: string,
	entry_point: string,
	path: string,
	type: vk.ShaderStageFlags,
) -> (
	err: Shader_Error,
) {
	shader.name = name
	shader.entry_point = entry_point
	shader.type = type
	shader.device = device

	data, ok := os.read_entire_file(path, allocator = context.temp_allocator)
	if !ok {
		return .File_Non_Existent
	}

	content := transmute([]u32)data

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

shader_destroy :: proc(shader: ^Shader) {
	vk.DestroyShaderModule(shader.device, shader.module, nil)
	shader.module = 0
}
