package raytracer

import "core:log"
_ :: log

import "core:hash/xxhash"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

import spvc "external:odin-spirv-cross"
import vk "vendor:vulkan"

Shader_Module :: struct {
	id:           u32,
	stage:        vk.ShaderStageFlags,
	entry_point:  string,
	compiled_src: []u32,
	resources:    []Shader_Resource,
}

Shader_Resource :: struct {
	stages:                                         vk.ShaderStageFlags,
	type:                                           Shader_Resource_Type,
	mode:                                           Shader_Resource_Mode,
	// maybe make set and binding to be a Maybe(u32)
	set, binding, location, input_attachment_index: u32,
	vec_size, columns, array_size:                  u32,
	offset, size, constant_id:                      u32,
	qualifiers:                                     Shader_Resource_Qualifiers,
	name:                                           string,
}

Shader_Resource_Qualifiers :: distinct bit_set[Shader_Resource_Qualifier]

Shader_Resource_Qualifier :: enum {
	None = 0,
	NonReadable,
	NonWritable,
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
	Acceleration_Structure,
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
	entry_point: string,
	allocator := context.allocator,
) -> (
	err: Shader_Module_Error,
) {
	data := os.read_entire_file_or_err(filename, allocator) or_return
	content := slice.reinterpret([]u32, data)

	module.stage = stage
	module.compiled_src = content
	module.resources = reflect_shader_resources(module.compiled_src, stage, allocator) or_return
	module.entry_point = entry_point

	hasher, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(hasher, context.temp_allocator)
	xxhash.XXH32_update(hasher, mem.any_to_bytes(content))
	module.id = xxhash.XXH32_digest(hasher)
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

	result_resources := make([dynamic]Shader_Resource)
	parse_shader_resources(compiler, stage, &result_resources)
	parse_push_constants(compiler, stage, &result_resources)

	return result_resources[:], nil
}

parse_push_constants :: proc(
	compiler: spvc.compiler,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	shader_resources: spvc.resources
	spvc.compiler_create_shader_resources(compiler, &shader_resources) or_return
	push_constants := get_resource_list(shader_resources, .PUSH_CONSTANT) or_return

	for pc in push_constants {
		type_handle := spvc.compiler_get_type_handle(compiler, pc.type_id)
		num_member_types := spvc.type_get_num_member_types(type_handle)

		offset := max(u32)
		for i in 0 ..< num_member_types {
			mem_offset := spvc.compiler_get_member_decoration(compiler, pc.id, i, .Offset)
			offset = min(offset, mem_offset)
		}

		resource := Shader_Resource {
			type   = .Push_Constant,
			stages = stage,
			name   = strings.clone_from_cstring(pc.name),
			offset = offset,
		}

		// TODO: read resource size
		resource.size = read_resource_size(compiler, pc)
		resource.size -= resource.offset
		append(resources, resource)
	}


	return nil
}

@(private = "file")
parse_shader_resources :: proc(
	compiler: spvc.compiler,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	shader_resources: spvc.resources
	spvc.compiler_create_shader_resources(compiler, &shader_resources) or_return
	read_input_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_input_attachment_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_output_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_image_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_image_sampler_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_image_storage_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_sampler_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_uniform_buffers_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_buffer_storage_shader_resources(compiler, shader_resources, stage, resources) or_return
	read_acceleration_structures(compiler, shader_resources, stage, resources) or_return

	return nil
}

read_input_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	inputs := get_resource_list(shader_resources, .STAGE_INPUT) or_return

	for input in inputs {
		vecsize, columns := read_resource_vec_size(compiler, input)
		spvc.compiler_get_decoration(compiler, input.id, .Location)
		resource := Shader_Resource {
			type     = .Input,
			stages   = stage,
			name     = strings.clone_from_cstring(input.name),
			vec_size = vecsize,
			columns  = columns,
			location = spvc.compiler_get_decoration(compiler, input.id, .Location),
		}

		append(resources, resource)
	}

	return nil
}

@(private = "file")
read_input_attachment_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	attachments := get_resource_list(shader_resources, .SUBPASS_INPUT) or_return
	for a in attachments {
		resource := Shader_Resource {
			type       = .Input_Attachment,
			stages     = {.FRAGMENT},
			name       = strings.clone_from_cstring(a.name),
			array_size = read_resource_array_size(compiler, a),
			location   = spvc.compiler_get_decoration(compiler, a.id, .Location),
			set        = spvc.compiler_get_decoration(compiler, a.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, a.id, .Binding),
		}

		append(resources, resource)
	}

	return nil
}

@(private = "file")
read_output_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	outputs := get_resource_list(shader_resources, .STAGE_OUTPUT) or_return
	for output in outputs {
		vecsize, columns := read_resource_vec_size(compiler, output)
		resource := Shader_Resource {
			type       = .Output,
			stages     = stage,
			name       = strings.clone_from_cstring(output.name),
			array_size = read_resource_array_size(compiler, output),
			vec_size   = vecsize,
			columns    = columns,
			location   = spvc.compiler_get_decoration(compiler, output.id, .Location),
		}

		append(resources, resource)
	}

	return nil
}

@(private = "file")
read_image_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	images := get_resource_list(shader_resources, .SEPARATE_IMAGE) or_return

	for image in images {
		vecsize, columns := read_resource_vec_size(compiler, image)
		resource := Shader_Resource {
			type       = .Image,
			stages     = stage,
			name       = strings.clone_from_cstring(image.name),
			array_size = read_resource_array_size(compiler, image),
			vec_size   = vecsize,
			columns    = columns,
			set        = spvc.compiler_get_decoration(compiler, image.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, image.id, .Binding),
		}

		append(resources, resource)
	}
	return nil
}

@(private = "file")
read_image_sampler_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	images := get_resource_list(shader_resources, .SAMPLED_IMAGE) or_return

	for image in images {
		vecsize, columns := read_resource_vec_size(compiler, image)
		resource := Shader_Resource {
			type       = .Image_Sampler,
			stages     = stage,
			name       = strings.clone_from_cstring(image.name),
			array_size = read_resource_array_size(compiler, image),
			vec_size   = vecsize,
			columns    = columns,
			set        = spvc.compiler_get_decoration(compiler, image.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, image.id, .Binding),
		}

		append(resources, resource)
	}
	return nil
}

@(private = "file")
read_image_storage_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	images := get_resource_list(shader_resources, .STORAGE_IMAGE) or_return

	for image in images {
		resource := Shader_Resource {
			type       = .Image_Storage,
			stages     = stage,
			name       = strings.clone_from_cstring(image.name),
			array_size = read_resource_array_size(compiler, image),
			set        = spvc.compiler_get_decoration(compiler, image.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, image.id, .Binding),
			qualifiers = {.NonWritable, .NonReadable},
		}

		append(resources, resource)
	}
	return nil
}

@(private = "file")
read_sampler_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	images := get_resource_list(shader_resources, .SEPARATE_SAMPLERS) or_return

	for image in images {
		resource := Shader_Resource {
			type       = .Sampler,
			stages     = stage,
			name       = strings.clone_from_cstring(image.name),
			array_size = read_resource_array_size(compiler, image),
			set        = spvc.compiler_get_decoration(compiler, image.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, image.id, .Binding),
		}

		append(resources, resource)
	}
	return nil
}

@(private = "file")
read_uniform_buffers_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	buffers := get_resource_list(shader_resources, .UNIFORM_BUFFER) or_return

	for buffer in buffers {
		resource := Shader_Resource {
			type       = .Buffer_Uniform,
			stages     = stage,
			name       = strings.clone_from_cstring(buffer.name),
			array_size = read_resource_array_size(compiler, buffer),
			// TODO: get resource size
			size       = read_resource_size(compiler, buffer),
			set        = spvc.compiler_get_decoration(compiler, buffer.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, buffer.id, .Binding),
		}

		append(resources, resource)
	}
	return nil
}

@(private = "file")
read_buffer_storage_shader_resources :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	buffers := get_resource_list(shader_resources, .STORAGE_BUFFER) or_return

	for buffer in buffers {
		resource := Shader_Resource {
			type       = .Buffer_Storage,
			stages     = stage,
			name       = strings.clone_from_cstring(buffer.name),
			array_size = read_resource_array_size(compiler, buffer),
			// TODO: get resource size
			size       = read_resource_size(compiler, buffer),
			qualifiers = {.NonReadable, .NonWritable},
			set        = spvc.compiler_get_decoration(compiler, buffer.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, buffer.id, .Binding),
		}

		append(resources, resource)
	}
	return nil
}

@(private = "file")
read_acceleration_structures :: proc(
	compiler: spvc.compiler,
	shader_resources: spvc.resources,
	stage: vk.ShaderStageFlags,
	resources: ^[dynamic]Shader_Resource,
) -> (
	err: spvc.result,
) {
	acceleration_structures := get_resource_list(
		shader_resources,
		.ACCELERATION_STRUCTURE,
	) or_return
	for accel_struct in acceleration_structures {
		resource := Shader_Resource {
			type       = .Acceleration_Structure,
			stages     = stage,
			name       = strings.clone_from_cstring(accel_struct.name),
			array_size = read_resource_array_size(compiler, accel_struct),
			qualifiers = {.NonWritable},
			set        = spvc.compiler_get_decoration(compiler, accel_struct.id, .DescriptorSet),
			binding    = spvc.compiler_get_decoration(compiler, accel_struct.id, .Binding),
		}
		append(resources, resource)
	}

	return nil
}

read_resource_vec_size :: proc(
	compiler: spvc.compiler,
	resource: spvc.reflected_resource,
) -> (
	vecsize: u32,
	columns: u32,
) {
	type_handle := spvc.compiler_get_type_handle(compiler, resource.type_id)
	vecsize = spvc.type_get_vector_size(type_handle)
	columns = spvc.type_get_columns(type_handle)

	return vecsize, columns
}

read_resource_array_size :: proc(
	compiler: spvc.compiler,
	resource: spvc.reflected_resource,
) -> u32 {
	type_handle := spvc.compiler_get_type_handle(compiler, resource.type_id)
	dimension_count := spvc.type_get_num_array_dimensions(type_handle)
	return dimension_count > 0 ? spvc.type_get_array_dimension(type_handle, 0) : 1
}

read_resource_size :: proc(compiler: spvc.compiler, resource: spvc.reflected_resource) -> u32 {
	type_handle := spvc.compiler_get_type_handle(compiler, resource.type_id)
	size: uint
	spvc.compiler_get_declared_struct_size(compiler, type_handle, &size)
	return u32(size)
}

@(private = "file")
get_resource_list :: proc(
	shader_resources: spvc.resources,
	type: spvc.resource_type,
) -> (
	inputs: []spvc.reflected_resource,
	err: spvc.result,
) {
	input_raw: [^]spvc.reflected_resource
	count: uint
	spvc.resources_get_resource_list_for_type(shader_resources, type, &input_raw, &count) or_return
	return input_raw[:count], nil
}
