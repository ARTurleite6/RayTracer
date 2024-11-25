package raytracer

import "core:mem"
import "core:os"
import vk "vendor:vulkan"

Shader_Error :: union #shared_nil {
	Shader_Load_Error,
	vk.Result,
}

Shader_Load_Error :: enum u8 {
	None = 0,
	FileNonExistent,
}

Shader :: struct {
	module: vk.ShaderModule,
}

@(require_results)
shader_init_from_filepath :: proc(
	shader: ^Shader,
	device: Device,
	file_path: string,
	temp_allocator: mem.Allocator,
) -> (
	err: Shader_Error,
) {
	content, found := os.read_entire_file(file_path, temp_allocator)
	if !found {
		return .FileNonExistent
	}

	return shader_init_from_code(shader, device, content)
}

@(require_results)
shader_init_from_code :: proc(
	shader: ^Shader,
	device: Device,
	content: []byte,
) -> (
	err: Shader_Error,
) {
	code := transmute([]u32)content

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(content),
		pCode    = &code[0],
	}

	if result := vk.CreateShaderModule(device, &create_info, nil, &shader.module);
	   result != .SUCCESS {
		return result
	}

	return
}

shader_init :: proc {
	shader_init_from_code,
	shader_init_from_filepath,
}
