package raytracer

import "core:log"
import "core:os"
import "core:slice"

import spvc "external:odin-spirv-cross"
import vk "vendor:vulkan"

Shader_Module :: struct {
	stage:        vk.ShaderStageFlags,
	entry_point:  string,
	compiled_src: []u32,
	resources:    []Shader_Resource,
}

Shader_Resource :: struct {
	stages:                                         vk.ShaderStageFlags,
	type:                                           Shader_Resource_Type,
	mode:                                           Shader_Resource_Mode,
	set, binding, location, input_attachment_index: u32,
	vec_size, columns, array_size:                  u32,
	offset, size, constant_id, qualifiers:          u32,
	name:                                           string,
}

Shader_Resource_Type :: enum {
	Input,
	Input_Attachment,
	Output,
	Image,
	Image_Sampler,
	Image_Storage,
	Sampler,
	Buffer_Uniform,
	Buffer_Storage,
	Push_Constant,
	Specialization_Constant,
	All,
}

Shader_Resource_Mode :: enum {
	Static,
	Dynamic,
	Update_After_Bind,
}

Shader_Module_Error :: union {
	os.Error,
	spvc.result,
}

shader_module_init :: proc(
	module: ^Shader_Module,
	stage: vk.ShaderStageFlags,
	filename: string,
	allocator := context.allocator,
) -> (
	err: Shader_Module_Error,
) {
	module.stage = stage
	data := os.read_entire_file_or_err(filename, allocator) or_return
	content := slice.reinterpret([]u32, data)
	module.compiled_src = content
	module.resources, err = reflect_shader_resources(module.compiled_src, stage, allocator)

	log.debug(module.resources)
	return nil
}

@(private = "file")
reflect_shader_resources :: proc(
	code: []u32,
	stage: vk.ShaderStageFlags,
	allocator := context.allocator,
) -> (
	resources: []Shader_Resource,
	result: spvc.result,
) {
	ctx: spvc.spvc_context
	spvc.context_create(&ctx) or_return
	defer spvc.context_destroy(ctx)

	ir: spvc.parsed_ir
	result = spvc.context_parse_spirv(ctx, raw_data(code), len(code), &ir)
	compiler: spvc.compiler
	spvc.context_create_compiler(ctx, .GLSL, ir, .TAKE_OWNERSHIP, &compiler) or_return

	return
}

@(private = "file")
parse_shader_resources :: proc(
	compiler: spvc.compiler,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) {
	// read_input_shader_resources(module, stage, resources)
	// read_input_attachment_shader_resources(module, stage, resources)
	// read_output_shader_resources(module, stage, resources)
}

read_input_shader_resources :: proc(
	compiler: spvc.compiler,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) {

}

@(private = "file")
read_input_attachment_shader_resources :: proc(
	compiler: spvc.compiler,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) {

}

@(private = "file")
read_output_shader_resources :: proc(
	compiler: spvc.compiler,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) {

}

@(private = "file")
@(require_results)
read_resource_array_size :: proc() -> u32 {
	return 0
}
