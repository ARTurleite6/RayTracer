package raytracer

import vk "vendor:vulkan"

Raytracing_Pipeline_State :: struct{
	using _: Pipeline,
	ray_gen_shaders, miss_shaders, hit_groups: []u32,
	max_raytracing_recursion: u32,
}

Attribute :: struct {
	attribute: u32,
	binding: u32,
	format: vk.Format,
	offset: vk.DeviceSize,
}

Command_Buffer_Dirty_Flag :: enum {
	Static_Vertex,	
	Pipeline,
}

Command_Buffer_Dirty_Flags :: distinct bit_set[Command_Buffer_Dirty_Flag]

Command_Buffer :: struct {
	buffer: vk.CommandBuffer,

	pipeline_state: Raytracing_Pipeline_State,
	shaders: [dynamic]Shader,

	dirty: Command_Buffer_Dirty_Flags,
}

command_buffer_init :: proc(cmd: ^Command_Buffer, buffer: vk.CommandBuffer) {
	cmd.buffer = buffer
	cmd.shaders = make([dynamic]Shader, context.temp_allocator)
	cmd.dirty = {}
}

command_buffer_destroy :: proc(cmd: ^Command_Buffer) {
	delete(cmd.shaders)
	cmd^ = {}
}

command_buffer_bind_pipeline :: proc(
	cmd: ^Command_Buffer,
	bind_point: vk.PipelineBindPoint,
	pipeline: vk.Pipeline,
) {
	vk.CmdBindPipeline(cmd.buffer, bind_point, pipeline)
}

command_buffer_begin_render_pass :: proc(cmd: ^Command_Buffer, rendering_info: ^vk.RenderingInfo) {
	vk.CmdBeginRendering(cmd.buffer, rendering_info)

	viewport := vk.Viewport {
		minDepth = 0,
		maxDepth = 1,
		width    = f32(rendering_info.renderArea.extent.width),
		height   = f32(rendering_info.renderArea.extent.height),
	}

	scissor := vk.Rect2D {
		extent = rendering_info.renderArea.extent,
	}

	vk.CmdSetViewport(cmd.buffer, 0, 1, &viewport)
	vk.CmdSetScissor(cmd.buffer, 0, 1, &scissor)
}

command_buffer_set_pipeline_layout :: proc(cmd: ^Command_Buffer, layout: vk.PipelineLayout) {
	cmd.pipeline_state.layout = layout
	set_dirty(cmd, {.Pipeline})
}

command_buffer_set_shader_groups :: proc(cmd: ^Command_Buffer, shader_groups: []vk.RayTracingShaderGroupCreateInfoKHR) {
	set_dirty(cmd, {.Pipeline})
}

 command_buffer_set_max_ray_recursion_depth :: proc(cmd: ^Command_Buffer, max_ray_recursion : u32) {
	cmd.pipeline_state.max_raytracing_recursion = max_ray_recursion

	set_dirty(cmd, {.Pipeline})
 }

command_buffer_end_render_pass :: proc(cmd: ^Command_Buffer) {
	vk.CmdEndRendering(cmd.buffer)
}

@(private="file")
flush_raytracing_state :: proc(cmd: ^Command_Buffer, synchronous := true) {
	assert(cmd.pipeline_state.layout != 0, "Needs to have a pipeline layout already assigned")

	if cmd.pipeline_state.pipeline == 0 do set_dirty(cmd, {.Pipeline})

	if get_and_clear(cmd, {.Pipeline}) {
		// flush state regarding the pipeline
		flush_raytracing_pipeline(cmd, synchronous)
	}
}

@(private="file")
flush_raytracing_pipeline :: proc(cmd: ^Command_Buffer, synchronous := true) {

}

@(private="file")
set_dirty :: proc(cmd: ^Command_Buffer, flags: Command_Buffer_Dirty_Flags) {
	cmd.dirty += flags
}

@(private="file")
get_and_clear :: proc(cmd: ^Command_Buffer, flags: Command_Buffer_Dirty_Flags) -> bool {
	has := card(flags & cmd.dirty) != 0
	cmd.dirty -= flags
	return has
}