package raytracer

import "core:os"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"

Shader_Error :: union #shared_nil {
	vk.Result,
	os.Error,
}

Shader_Module :: struct {
	handle:     vk.ShaderModule,
	entrypoint: string,
	stage:      vk.ShaderStageFlags,
}

@(require_results)
make_vertex_shader_module :: proc(
	device: ^vkb.Device,
	filepath: string,
	entrypoint: string,
) -> (
	shader_module: Shader_Module,
	ok: bool,
) {
	return _make_shader_module(device, filepath, entrypoint, {.VERTEX})
}

@(require_results)
make_fragment_shader_module :: proc(
	device: ^vkb.Device,
	filepath: string,
	entrypoint: string,
) -> (
	shader_module: Shader_Module,
	ok: bool,
) {
	return _make_shader_module(device, filepath, entrypoint, {.FRAGMENT})
}

delete_shader_module :: proc(device: ^vkb.Device, shader: Shader_Module) {
	vk.DestroyShaderModule(device.ptr, shader.handle, nil)
}

@(private = "file")
@(require_results)
_make_shader_module :: proc(
	device: ^vkb.Device,
	filepath: string,
	entrypoint: string,
	stage: vk.ShaderStageFlags,
) -> (
	shader_module: Shader_Module,
	ok: bool,
) {
	content := string(os.read_entire_file(filepath) or_return)

	code := transmute([]u32)content

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = &code[0],
	}

	vk_must(
		vk.CreateShaderModule(device.ptr, &create_info, nil, &shader_module.handle),
		"Failed to create shader module",
	)

	shader_module.entrypoint = entrypoint
	shader_module.stage = stage

	ok = true
	return
}
