package raytracer

import "core:log"
_ :: log

import vk "vendor:vulkan"

MAX_PUSH_CONSTANT_SIZE :: 128

Command_Buffer :: struct {
	buffer:                 vk.CommandBuffer,
	ctx:                    ^Vulkan_Context,

	// TODO: Consider to use an arena allocator to manage this state.

	// state management,
	pipeline_state:         Pipeline_State,
	push_constant_state:    Push_Constant_State,
	resource_binding_state: map[u32]Resource_Binding_State, // map from set to resource binding of that set
	sbt:                    ^Shader_Binding_Table,
}

Resource_Binding_State :: struct {
	buffer_infos:                 Binding_Map(vk.DescriptorBufferInfo),
	image_infos:                  Binding_Map(vk.DescriptorImageInfo),
	acceleration_structure_infos: Binding_Map(vk.WriteDescriptorSetAccelerationStructureKHR),
	dirty:                        bool,
}

Resource_Type :: union {
	vk.DescriptorBufferInfo,
	vk.DescriptorImageInfo,
	vk.WriteDescriptorSetAccelerationStructureKHR,
}

Push_Constant_State :: struct {
	info:   [MAX_PUSH_CONSTANT_SIZE]u8,
	size:   u32,
	offset: u32,
	stages: vk.ShaderStageFlags,
	dirty:  bool,
}

Raytracing_Spec :: struct {
	rgen_shader:                       ^Shader_Module,
	miss_shaders, closest_hit_shaders: []^Shader_Module,
	max_tracing_depth:                 u32,
}

command_buffer_init :: proc(cmd: ^Command_Buffer, ctx: ^Vulkan_Context, buffer: vk.CommandBuffer) {
	cmd^ = {}
	cmd.buffer = buffer
	cmd.ctx = ctx
	cmd.resource_binding_state = make(map[u32]Resource_Binding_State, context.temp_allocator)
}

command_buffer_destroy :: proc(cmd: ^Command_Buffer) {

}

command_buffer_reset :: proc(cmd: ^Command_Buffer) {
	// TODO: implement the rest of resource cleaning in the future.
	cmd.pipeline_state = {}
}

command_buffer_bind_image :: proc(
	cmd: ^Command_Buffer,
	set: u32,
	binding: u32,
	info: vk.DescriptorImageInfo,
	dst_array_element := u32(0),
) {
	_, set_ptr, just_inserted, _ := map_entry(&cmd.resource_binding_state, set)
	if just_inserted {
		set_ptr^ = {
			buffer_infos                 = make_binding_map(
				vk.DescriptorBufferInfo,
				context.temp_allocator,
			),
			image_infos                  = make_binding_map(
				vk.DescriptorImageInfo,
				context.temp_allocator,
			),
			acceleration_structure_infos = make_binding_map(
				vk.WriteDescriptorSetAccelerationStructureKHR,
				context.temp_allocator,
			),
		}
	}
	bind_resource(&set_ptr.image_infos, binding, dst_array_element, info)
	set_ptr.dirty = true
}

command_buffer_bind_resource :: proc(
	cmd: ^Command_Buffer,
	set: u32,
	binding: u32,
	info: Resource_Type,
	dst_array_element := u32(0),
) {
	_, set_ptr, just_inserted, _ := map_entry(&cmd.resource_binding_state, set)
	if just_inserted {
		set_ptr^ = {
			buffer_infos                 = make_binding_map(
				vk.DescriptorBufferInfo,
				context.temp_allocator,
			),
			image_infos                  = make_binding_map(
				vk.DescriptorImageInfo,
				context.temp_allocator,
			),
			acceleration_structure_infos = make_binding_map(
				vk.WriteDescriptorSetAccelerationStructureKHR,
				context.temp_allocator,
			),
		}
	}

	switch v in info {
	case vk.DescriptorBufferInfo:
		bind_resource(&set_ptr.buffer_infos, binding, dst_array_element, v)
	case vk.DescriptorImageInfo:
		bind_resource(&set_ptr.image_infos, binding, dst_array_element, v)
	case vk.WriteDescriptorSetAccelerationStructureKHR:
		bind_resource(&set_ptr.acceleration_structure_infos, binding, dst_array_element, v)
	}
	set_ptr.dirty = true
}

command_buffer_bind_buffer :: proc(
	cmd: ^Command_Buffer,
	set: u32,
	binding: u32,
	info: vk.DescriptorBufferInfo,
	dst_array_element := u32(0),
) {
	_, set_ptr, just_inserted, _ := map_entry(&cmd.resource_binding_state, set)
	if just_inserted {
		set_ptr^ = {
			buffer_infos                 = make_binding_map(
				vk.DescriptorBufferInfo,
				context.temp_allocator,
			),
			image_infos                  = make_binding_map(
				vk.DescriptorImageInfo,
				context.temp_allocator,
			),
			acceleration_structure_infos = make_binding_map(
				vk.WriteDescriptorSetAccelerationStructureKHR,
				context.temp_allocator,
			),
		}
	}
	bind_resource(&set_ptr.buffer_infos, binding, dst_array_element, info)
	set_ptr.dirty = true
}

command_buffer_bind_acceleration_structure :: proc(
	cmd: ^Command_Buffer,
	set: u32,
	binding: u32,
	info: vk.WriteDescriptorSetAccelerationStructureKHR,
	dst_array_element := u32(0),
) {
	_, set_ptr, just_inserted, _ := map_entry(&cmd.resource_binding_state, set)
	if just_inserted {
		set_ptr^ = {
			buffer_infos                 = make_binding_map(
				vk.DescriptorBufferInfo,
				context.temp_allocator,
			),
			image_infos                  = make_binding_map(
				vk.DescriptorImageInfo,
				context.temp_allocator,
			),
			acceleration_structure_infos = make_binding_map(
				vk.WriteDescriptorSetAccelerationStructureKHR,
				context.temp_allocator,
			),
		}
	}
	bind_resource(&set_ptr.acceleration_structure_infos, binding, dst_array_element, info)
	set_ptr.dirty = true
}

command_buffer_push_constant_range :: proc(cmd: ^Command_Buffer, offset: u32, data: []u8) {
	state := &cmd.push_constant_state
	copy(state.info[offset:], data)
	state.size = u32(len(data))
	state.offset = offset
	state.dirty = true
}

command_buffer_set_raytracing_program :: proc(
	cmd: ^Command_Buffer,
	spec: Raytracing_Spec,
) -> vk.Result {
	modules := make(
		[dynamic]^Shader_Module,
		0,
		1 + len(spec.miss_shaders) + len(spec.closest_hit_shaders),
		context.temp_allocator,
	)
	append(&modules, spec.rgen_shader)
	for miss in spec.miss_shaders {
		append(&modules, miss)
	}

	for closest_hit in spec.closest_hit_shaders {
		append(&modules, closest_hit)
	}

	layout := resource_cache_request_pipeline_layout(&cmd.ctx.cache, cmd.ctx, modules[:]) or_return

	cmd.pipeline_state.layout = layout
	cmd.pipeline_state.max_ray_recursion = spec.max_tracing_depth
	cmd.pipeline_state.dirty = true
	return nil
}

command_buffer_trace_rays :: proc(cmd: ^Command_Buffer, width, height: u32, depth: u32) {
	command_buffer_flush(cmd, .RAY_TRACING_KHR)

	vk.CmdTraceRaysKHR(
		cmd.buffer,
		&cmd.sbt.regions[.Ray_Gen],
		&cmd.sbt.regions[.Miss],
		&cmd.sbt.regions[.Hit],
		&cmd.sbt.regions[.Callable],
		width,
		height,
		1,
	)
}
command_buffer_flush :: proc(cmd: ^Command_Buffer, bind_point: vk.PipelineBindPoint) -> vk.Result {
	// flush pipeline
	if cmd.pipeline_state.dirty {
		// we need to get another pipeline
		defer cmd.pipeline_state.dirty = true

		pipeline: ^Pipeline2

		#partial switch bind_point {
		case .RAY_TRACING_KHR:
			raytracing_pipeline := resource_cache_request_raytracing_pipeline(
				&cmd.ctx.cache,
				cmd.ctx,
				cmd.pipeline_state,
			) or_return
			pipeline = raytracing_pipeline
			cmd.sbt = &raytracing_pipeline.sbt

		case:
			unimplemented("Pipeline still not implemented")
		}
		vk.CmdBindPipeline(cmd.buffer, bind_point, pipeline.handle)
	}

	// flush push_constants

	if cmd.push_constant_state.dirty {
		defer cmd.push_constant_state.dirty = false

		assert(cmd.pipeline_state.layout != nil, "Pipeline layout must already been bound")
		layout := cmd.pipeline_state.layout
		offset := cmd.push_constant_state.offset
		size := cmd.push_constant_state.size
		stages := pipeline_layout_get_push_constant_range_stages(layout^, size, offset)
		vk.CmdPushConstants(
			cmd.buffer,
			layout.handle,
			stages,
			offset,
			size,
			raw_data(cmd.push_constant_state.info[:size]),
		)
	}

	binding_sets := make(
		[]vk.DescriptorSet,
		len(cmd.resource_binding_state),
		context.temp_allocator,
	)
	// flush sets
	for set, &state in cmd.resource_binding_state {
		// TODO:check if all descriptors are getting bound(probably this could be directly on descriptor_set
		// module
		if state.dirty {
			defer state.dirty = false
			assert(cmd.pipeline_state.layout != nil, "Pipeline layout must already been bound")
			assert(set < u32(len(cmd.pipeline_state.layout.descriptor_set_layouts)), "Invalid set")
			descriptor_layout := cmd.pipeline_state.layout.descriptor_set_layouts[set]

			descriptor_set := resource_cache_request_descriptor_set2(
				&cmd.ctx.cache,
				cmd.ctx,
				descriptor_layout,
				state.buffer_infos,
				state.image_infos,
				state.acceleration_structure_infos,
			) or_return

			descriptor_set_update2(descriptor_set, cmd.ctx)
			// TODO: in here we could check actually what bindings we need to update, for example only 
			// update a specific buffer

			assert(
				set < u32(len(binding_sets)),
				"You havent provided any binding resources for this set",
			)
			binding_sets[set] = descriptor_set.handle
		}
	}

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		bind_point,
		cmd.pipeline_state.layout.handle,
		0,
		u32(len(binding_sets)),
		raw_data(binding_sets),
		0,
		nil,
	)

	return nil
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

command_buffer_end_render_pass :: proc(cmd: ^Command_Buffer) {
	vk.CmdEndRendering(cmd.buffer)
}

@(private = "file")
bind_resource :: proc(
	binding_map: ^Binding_Map($T),
	binding: u32,
	dst_array_element: u32,
	info: T,
) {
	binding_map_set_binding(binding_map, binding, info, dst_array_element)
}
