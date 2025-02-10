package raytracer

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
	module:     vk.ShaderModule,
	stage:      vk.ShaderStageFlags,
	entrypoint: string,
}

@(require_results)
shader_init :: proc(
	shader: ^Shader,
	device: Device,
	stage: vk.ShaderStageFlags,
	entrypoint: string,
	file_path: string,
) -> (
	err: Shader_Error,
) {
	shader.entrypoint = entrypoint
	shader.stage = stage

	content, found := os.read_entire_file(file_path)
	if !found {
		return .FileNonExistent
	}
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

shader_destroy :: proc(shader: Shader, device: Device) {
	vk.DestroyShaderModule(device, shader.module, nil)
}
