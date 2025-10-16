package raytracer

import "core:log"
import "core:mem"
import "core:slice"
_ :: log

import vk "vendor:vulkan"

MAX_PUSH_CONSTANT_SIZE :: 256

Command_Buffer :: struct {
	buffer:      vk.CommandBuffer,
	ctx:         ^Vulkan_Context,

	// TODO: Consider to use an arena allocator to manage this state.

	// state management,
	using state: Command_Buffer_State,
	allocator:   mem.Allocator,
}

Command_Buffer_State :: struct {
	pipeline_state:         Pipeline_State,
	push_constant_state:    Push_Constant_State,
	resource_binding_state: map[u32]Resource_Binding_State, // map from set to resource binding of that set
	sbt:                    ^Shader_Binding_Table,
}

Render_Pass_Info :: struct {
	color_formats:                []vk.Format,
	depth_format, stencil_format: vk.Format,
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
	cmd.allocator = context.temp_allocator
}

command_buffer_destroy :: proc(cmd: ^Command_Buffer) {

}

@(require_results)
command_buffer_end :: proc(cmd: Command_Buffer) -> vk.Result {
	return vk.EndCommandBuffer(cmd.buffer)
}

command_buffer_reset :: proc(cmd: ^Command_Buffer) {
	cmd.state = {}
}

command_buffer_bind_vertex_buffers :: proc(
	cmd: Command_Buffer,
	first_binding: u32,
	buffers: []Buffer,
	offsets: []vk.DeviceSize,
) {
	context.temp_allocator = cmd.allocator
	raw_buffers := slice.mapper(
		buffers,
		proc(buffer: Buffer) -> vk.Buffer {return buffer.handle},
		context.temp_allocator,
	)

	vk.CmdBindVertexBuffers(
		cmd.buffer,
		first_binding,
		u32(len(buffers)),
		raw_data(raw_buffers),
		raw_data(offsets),
	)
}

command_buffer_bind_index_buffer :: proc(
	cmd: Command_Buffer,
	buffer: Buffer,
	offset: vk.DeviceSize,
	index_type: vk.IndexType,
) {
	vk.CmdBindIndexBuffer(cmd.buffer, buffer.handle, offset, index_type)
}

command_buffer_set_vertex_attrib :: proc(
	cmd: ^Command_Buffer,
	location, binding: u32,
	format: vk.Format,
	offset: u32,
) {
	context.allocator = cmd.allocator
	if len(cmd.pipeline_state.vertex_input.attributes) <= int(location) {
		resize(&cmd.pipeline_state.vertex_input.attributes, location + 1)
	}
	cmd.pipeline_state.vertex_input.attributes[location] = {
		location = location,
		binding  = binding,
		format   = format,
		offset   = offset,
	}

	cmd.pipeline_state.dirty = true
}

command_buffer_set_vertex_binding :: proc(
	cmd: ^Command_Buffer,
	binding, stride: u32,
	input_rate := vk.VertexInputRate.VERTEX,
) {
	context.allocator = cmd.allocator
	if len(cmd.pipeline_state.vertex_input.bindings) <= int(binding) {
		resize(&cmd.pipeline_state.vertex_input.bindings, binding + 1)
	}
	cmd.pipeline_state.vertex_input.bindings[binding] = {
		binding   = binding,
		stride    = stride,
		inputRate = input_rate,
	}

	cmd.pipeline_state.dirty = true
}

command_buffer_bind_resource :: proc(
	cmd: ^Command_Buffer,
	set: u32,
	binding: u32,
	info: Resource_Type,
	dst_array_element := u32(0),
) {
	context.allocator = cmd.allocator
	_, set_ptr, just_inserted, _ := map_entry(&cmd.resource_binding_state, set)
	if just_inserted {
		set_ptr^ = {
			buffer_infos                 = make_binding_map(vk.DescriptorBufferInfo),
			image_infos                  = make_binding_map(vk.DescriptorImageInfo),
			acceleration_structure_infos = make_binding_map(
				vk.WriteDescriptorSetAccelerationStructureKHR,
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

command_buffer_push_constant_range :: proc(cmd: ^Command_Buffer, offset: u32, data: []u8) {
	state := &cmd.push_constant_state
	copy(state.info[offset:], data)
	state.size = u32(len(data))
	state.offset = offset
	state.dirty = true
}

command_buffer_set_graphics_program :: proc(
	cmd: ^Command_Buffer,
	vertex_shader: ^Shader_Module,
	fragment_shader: ^Shader_Module,
) -> vk.Result {
	command_buffer_reset(cmd)

	layout := resource_cache_request_pipeline_layout(
		&cmd.ctx.cache,
		cmd.ctx,
		{vertex_shader, fragment_shader},
	) or_return

	cmd.pipeline_state.layout = layout
	cmd.pipeline_state.dirty = true
	return nil
}

command_buffer_draw :: proc(
	cmd: ^Command_Buffer,
	vertex_count, instance_count, first_vertex, first_instance: u32,
) {
	command_buffer_flush(cmd, .GRAPHICS)
	vk.CmdDraw(cmd.buffer, vertex_count, instance_count, first_vertex, first_instance)
}

command_buffer_draw_indexed :: proc(
	cmd: ^Command_Buffer,
	index_count, instance_count, first_index: u32,
	vertex_offset: i32,
	first_instance: u32,
) {
	command_buffer_flush(cmd, .GRAPHICS)
	vk.CmdDrawIndexed(
		cmd.buffer,
		index_count,
		instance_count,
		first_index,
		vertex_offset,
		first_instance,
	)
}


command_buffer_set_raytracing_program :: proc(
	cmd: ^Command_Buffer,
	spec: Raytracing_Spec,
) -> vk.Result {
	command_buffer_reset(cmd)
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

command_buffer_image_blit :: proc(
	cmd: Command_Buffer,
	dst, src: vk.Image,
	dst_offset, dst_extent, src_offset, src_extent: vk.Offset3D,
	dst_level, src_level, dst_base_layer, src_base_layer, num_layers: u32,
	dst_format, src_format: vk.Format,
	filter: vk.Filter,
) {
	add_offset :: proc(a, b: vk.Offset3D) -> vk.Offset3D {
		return {a.x + b.x, a.y + b.y, a.z + b.z}
	}

	blit_region := vk.ImageBlit {
		srcSubresource = {
			aspectMask = format_to_aspect_mask(src_format),
			mipLevel = src_level,
			baseArrayLayer = src_base_layer,
			layerCount = num_layers,
		},
		srcOffsets = [2]vk.Offset3D{src_offset, add_offset(src_offset, src_extent)},
		dstSubresource = {
			aspectMask = format_to_aspect_mask(dst_format),
			mipLevel = dst_level,
			baseArrayLayer = dst_base_layer,
			layerCount = num_layers,
		},
		dstOffsets = [2]vk.Offset3D{dst_offset, add_offset(dst_offset, dst_extent)},
	}

	vk.CmdBlitImage(
		cmd.buffer,
		src,
		.TRANSFER_SRC_OPTIMAL,
		dst,
		.TRANSFER_DST_OPTIMAL,
		1,
		&blit_region,
		filter,
	)
}

command_buffer_image_layout_transition :: proc(
	cmd: Command_Buffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
) {
	src_stage := get_pipeline_stage_flags(old_layout)
	dst_stage := get_pipeline_stage_flags(new_layout)

	src_access := get_access_flags(old_layout)
	dst_access := get_access_flags(new_layout)

	command_buffer_image_layout_transition_stage_access(
		cmd,
		image,
		old_layout,
		new_layout,
		src_stage,
		dst_stage,
		src_access,
		dst_access,
	)
}

command_buffer_image_layout_transition_stage_access :: proc(
	cmd: Command_Buffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
	src_stage, dst_stage: vk.PipelineStageFlags2,
	src_access, dst_access: vk.AccessFlags2,
) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage,
		srcAccessMask = src_access,
		dstStageMask = dst_stage,
		dstAccessMask = dst_access,
		oldLayout = old_layout,
		newLayout = new_layout,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}

	vk.CmdPipelineBarrier2(cmd.buffer, &dependency_info)
}

command_buffer_flush :: proc(cmd: ^Command_Buffer, bind_point: vk.PipelineBindPoint) -> vk.Result {
	// flush pipeline
	if cmd.pipeline_state.dirty {
		// we need to get another pipeline
		defer cmd.pipeline_state.dirty = false

		pipeline: ^Pipeline

		#partial switch bind_point {
		case .RAY_TRACING_KHR:
			raytracing_pipeline := resource_cache_request_raytracing_pipeline(
				&cmd.ctx.cache,
				cmd.ctx,
				cmd.pipeline_state,
			) or_return
			pipeline = raytracing_pipeline
			cmd.sbt = &raytracing_pipeline.sbt

		case .GRAPHICS:
			pipeline = resource_cache_request_graphics_pipeline(
				&cmd.ctx.cache,
				cmd.ctx,
				cmd.pipeline_state,
			) or_return

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
	dirty: bool
	// flush sets
	for set, &state in cmd.resource_binding_state {
		// TODO:check if all descriptors are getting bound(probably this could be directly on descriptor_set
		// module
		if state.dirty {
			defer state.dirty = false
			assert(cmd.pipeline_state.layout != nil, "Pipeline layout must already been bound")
			assert(set < u32(len(cmd.pipeline_state.layout.descriptor_set_layouts)), "Invalid set")
			descriptor_layout := cmd.pipeline_state.layout.descriptor_set_layouts[set]
			dirty = true

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

	if len(binding_sets) > 0 && dirty {
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
	}

	return nil
}


command_buffer_begin_render_pass :: proc(
	cmd: ^Command_Buffer,
	rendering_info: ^vk.RenderingInfo,
	render_pass_info: Render_Pass_Info,
) {
	context.allocator = cmd.allocator

	for format in render_pass_info.color_formats {
		append(&cmd.pipeline_state.color_attachment_formats, format)

		append(
			&cmd.pipeline_state.color_blend.attachments,
			Color_Blend_Attachment_State {
				blend_enable = false,
				color_write_mask = vk.ColorComponentFlags{.R, .G, .B, .A},
			},
		)
	}

	cmd.pipeline_state.depth_attachment_format = render_pass_info.depth_format
	cmd.pipeline_state.stencil_attachment_format = render_pass_info.stencil_format
	cmd.pipeline_state.dirty = true

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
