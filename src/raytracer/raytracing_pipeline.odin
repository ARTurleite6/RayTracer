package raytracer

import "core:fmt"
_ :: fmt

import vk "vendor:vulkan"

Raytracing_Pipeline :: struct {
	using base:           Pipeline,
	indices:              map[int]struct {},
	raytracing_props:     vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	// shader binding table data
	shader_binding_table: Shader_Binding_Table,
}

rt_pipeline_init :: proc(self: ^Raytracing_Pipeline, ctx: ^Vulkan_Context) {
	self^ = {}
	self.raytracing_props = vulkan_get_raytracing_pipeline_properties(ctx)
	self.shader_binding_table = {}
}

rt_pipeline_destroy :: proc(self: ^Raytracing_Pipeline, device: vk.Device) {
	pipeline_destroy(&self.base, device)
	shader_binding_table_destroy(&self.shader_binding_table)
}

rt_pipeline_build :: proc(
	self: ^Raytracing_Pipeline,
	ctx: ^Vulkan_Context,
	max_pipeline_recursion: u32,
) -> (
	result: vk.Result,
) {
	self.layout = vulkan_get_pipeline_layout(
		ctx,
		self.descriptor_set_layouts[:],
		self.push_constant_ranges[:],
	)

	self.handle = vulkan_get_raytracing_pipeline(
		ctx,
		self.shaders[:],
		self.shader_binding_table.groups[:],
		max_pipeline_recursion,
		self.layout,
	)

	shader_binding_table_build(&self.shader_binding_table, ctx, self.handle, self.raytracing_props)

	return .SUCCESS
}

rt_pipeline_add_shader :: proc(self: ^Raytracing_Pipeline, shader: Shader, index: int) {
	// TODO: add callable support

	if .RAYGEN_KHR in shader.type {
		rt_pipeline_add_raygen_shader(self, shader, index)
	} else if .MISS_KHR in shader.type {
		rt_pipeline_add_miss_shader(self, shader, index)

	} else if .CLOSEST_HIT_KHR in shader.type {
		rt_pipeline_add_closest_hit(self, shader, index)
	} else if .CALLABLE_KHR in shader.type {
		unimplemented("Callable shaders is not implemented still")
	}
}

@(private = "file")
rt_pipeline_add_raygen_shader :: proc(self: ^Raytracing_Pipeline, shader: Shader, index: int) {
	_, found := self.indices[index]
	assert(!found, "Index already found on raytracing pipeline")

	pipeline_add_shader(&self.base, shader)

	shader_binding_table_add_group(
		&self.shader_binding_table,
		{
			sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
			type = .GENERAL,
			generalShader = u32(index),
			closestHitShader = ~u32(0),
			anyHitShader = ~u32(0),
			intersectionShader = ~u32(0),
		},
		.Ray_Gen,
	)
}

@(private = "file")
rt_pipeline_add_miss_shader :: proc(self: ^Raytracing_Pipeline, shader: Shader, index: int) {
	_, found := self.indices[index]
	assert(!found, "Index already found on raytracing pipeline")

	pipeline_add_shader(&self.base, shader)

	shader_binding_table_add_group(
		&self.shader_binding_table,
		{
			sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
			type = .GENERAL,
			generalShader = u32(index),
			closestHitShader = ~u32(0),
			anyHitShader = ~u32(0),
			intersectionShader = ~u32(0),
		},
		.Miss,
	)
}

@(private = "file")
rt_pipeline_add_closest_hit :: proc(self: ^Raytracing_Pipeline, shader: Shader, index: int) {
	_, found := self.indices[index]
	assert(!found, "Index already found on raytracing pipeline")

	pipeline_add_shader(&self.base, shader)

	shader_binding_table_add_group(
		&self.shader_binding_table,
		{
			sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
			type = .TRIANGLES_HIT_GROUP,
			generalShader = ~u32(0),
			closestHitShader = u32(index),
			anyHitShader = ~u32(0),
			intersectionShader = ~u32(0),
		},
		.Hit,
	)
}
