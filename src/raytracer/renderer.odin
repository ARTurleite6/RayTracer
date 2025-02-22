package raytracer

import "core:fmt"
import glm "core:math/linalg"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Renderer :: struct {
	ctx:    Context,
	window: ^Window,
	mesh:   Mesh,
	camera: Camera,
}

VERTICES := []Vertex {
	{{0.0, -0.5, 0.0}, {1.0, 0.0, 0.0}},
	{{0.5, 0.5, 0.0}, {0.0, 1.0, 0.0}},
	{{-0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}},
}

renderer_init :: proc(
	renderer: ^Renderer,
	window: ^Window,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	context_init(&renderer.ctx, window^, allocator) or_return
	renderer.window = window

	// mesh_init_without_indices(&renderer.mesh, &renderer.ctx, "Triangle", VERTICES) or_return
	renderer.mesh = create_quad(&renderer.ctx, "Triangle") or_return

	camera_init(&renderer.camera, aspect = window_aspect_ratio(window^))
	return nil
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.ptr)
	mesh_destroy(&renderer.mesh)
	delete_context(&renderer.ctx)
}

@(require_results)
renderer_begin_frame :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	frame_manager_acquire(&renderer.ctx) or_return

	frame := renderer.ctx.frame_manager.frames[renderer.ctx.frame_manager.current_frame]

	ubo := Uniform_Buffer_Object {
		view_proj = glm.matrix4_rotate_f32(glm.to_radians(f32(90)), {0, 0, 1}),
	}
	buffer_write(frame.uniform_buffer, &ubo)

	buffer_info := vk.DescriptorBufferInfo {
		buffer = frame.uniform_buffer.handle,
		offset = 0,
		range  = size_of(Uniform_Buffer_Object),
	}

	descriptor_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = frame.descriptor_set,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		pBufferInfo     = &buffer_info,
	}

	vk.UpdateDescriptorSets(renderer.ctx.device.ptr, 1, &descriptor_write, 0, nil)

	frame_manager_frame_begin(&renderer.ctx) or_return

	frame_manager_frame_begin_rendering(
		&renderer.ctx,
		renderer.ctx.swapchain.extent,
		vk.ClearValue{color = {float32 = {0, 0, 0, 1}}},
	)

	return nil
}

renderer_draw :: proc(renderer: ^Renderer) {
	frame := frame_manager_get_frame(&renderer.ctx.frame_manager) // TODO: Improve this
	cmd_handle := frame.command_buffer.handle

	vk.CmdBindPipeline(cmd_handle, .GRAPHICS, renderer.ctx.pipeline.handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(renderer.ctx.swapchain.extent.width),
		height   = f32(renderer.ctx.swapchain.extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	vk.CmdSetViewport(cmd_handle, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = renderer.ctx.swapchain.extent,
	}

	vk.CmdSetScissor(cmd_handle, 0, 1, &scissor)

	mesh_bind(renderer.mesh, frame.command_buffer)

	vk.CmdBindDescriptorSets(
		cmd_handle,
		.GRAPHICS,
		renderer.ctx.pipeline.layout,
		0,
		1,
		&frame.descriptor_set,
		0,
		nil,
	)

	mesh_draw(renderer.mesh, frame.command_buffer)

	vk.CmdDraw(cmd_handle, u32(len(VERTICES)), 1, 0, 0)
}

@(require_results)
renderer_end_frame :: proc(renderer: ^Renderer) -> (err: Backend_Error) {
	frame_manager_frame_end_rendering(&renderer.ctx)

	if result := renderer_flush(renderer); result != .SUCCESS {
		if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
			return .NeedsResizing
		}
		return result
	}
	frame_manager_advance(&renderer.ctx)
	return
}

@(require_results)
renderer_flush :: proc(renderer: ^Renderer) -> (result: vk.Result) {
	cmd := frame_manager_frame_get_command_buffer(&renderer.ctx)
	vk.EndCommandBuffer(cmd.handle) or_return // TODO: probably clean this

	frame_manager_frame_submit(&renderer.ctx) or_return

	frame_manager_frame_present(&renderer.ctx) or_return

	return
}

renderer_handle_resize :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	handle_resize(&renderer.ctx, renderer.window^, allocator) or_return

	renderer.camera.aspect = window_aspect_ratio(renderer.window^)
	camera_update_matrices(&renderer.camera)

	return nil
}
