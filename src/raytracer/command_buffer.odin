package raytracer

import "core:log"
_ :: log

import vk "vendor:vulkan"

Buffer_Info :: struct {
	buffer: ^Buffer,
	offset: vk.DeviceSize,
	range:  vk.DeviceSize,
}

Image_Info :: struct {
	image_view: vk.ImageView,
	sampler:    vk.Sampler,
}

Resource_Info :: struct {
	info:  union {
		Buffer_Info,
		Image_Info,
	},
	dirty: bool,
}

Resource_Set :: struct {
	bindings: Binding_Map(Resource_Info),
	dirty:    bool,
}

Resource_Binding_State :: struct {
	resource_sets: map[u32]Resource_Set,
	dirty:         bool,
}

Command_Buffer :: struct {
	buffer:                 vk.CommandBuffer,
	resource_binding_state: Resource_Binding_State,
}

command_buffer_init :: proc(cmd: ^Command_Buffer, buffer: vk.CommandBuffer) {
	cmd.buffer = buffer
	cmd.resource_binding_state = {}
}

command_buffer_destroy :: proc(cmd: ^Command_Buffer) {
	for _, &set in cmd.resource_binding_state.resource_sets {
		for _, &binding in set.bindings.inner {
			delete(binding)
		}
		delete(set.bindings.inner)
		set.dirty = false
	}
	delete(cmd.resource_binding_state.resource_sets)
	cmd.resource_binding_state.dirty = false
}

command_buffer_bind_buffer :: proc(
	cmd: ^Command_Buffer,
	buffer: ^Buffer,
	offset: vk.DeviceSize,
	range: vk.DeviceSize,
	set: u32,
	binding: u32,
	array_element: u32,
) {
	_, set_ptr, _, _ := map_entry(&cmd.resource_binding_state.resource_sets, set)
	_, binding_ptr, _, _ := map_entry(&set_ptr.bindings.inner, binding)
	binding_ptr[array_element] = {
		info = Buffer_Info{buffer = buffer, offset = offset, range = range},
		dirty = true,
	}
}

command_buffer_bind_image :: proc(
	cmd: ^Command_Buffer,
	image_view: vk.ImageView,
	sampler: vk.Sampler,
	set: u32,
	binding: u32,
	array_element: u32,
) {
	_, set_ptr, _, _ := map_entry(&cmd.resource_binding_state.resource_sets, set)
	_, binding_ptr, _, _ := map_entry(&set_ptr.bindings.inner, binding)
	binding_ptr[array_element] = {
		info = Image_Info{image_view = image_view, sampler = sampler},
		dirty = true,
	}
}

command_buffer_trace_rays :: proc(
	cmd: ^Command_Buffer,
	regions: ^[Shader_Region]vk.StridedDeviceAddressRegionKHR,
	width, height: u32,
	depth: u32,
) {
	command_buffer_flush(cmd)

	vk.CmdTraceRaysKHR(
		cmd.buffer,
		&regions[.Ray_Gen],
		&regions[.Miss],
		&regions[.Hit],
		&regions[.Callable],
		width,
		height,
		1,
	)
}

// command_buffer_bind_pipeline :: proc(
// 	cmd: ^Command_Buffer,
// 	bind_point: vk.PipelineBindPoint,
// 	pipeline: vk.Pipeline,
// flush{
// 	vk.CmdBindPipeline(cmd.buffer, bind_point, pipeline)
// }

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

command_buffer_end_render_pass :: proc(cmd: ^Command_Buffer) {
	vk.CmdEndRendering(cmd.buffer)
}

command_buffer_flush :: proc(cmd: ^Command_Buffer) {

}
