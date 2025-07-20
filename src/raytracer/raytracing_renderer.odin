package raytracer

import "core:log"
import "core:mem"
_ :: log

import vk "vendor:vulkan"

Raytracing_Renderer :: struct {
	ctx:                 Vulkan_Context,
	scene:               ^Scene,
	gpu_scene:           GPU_Scene2,
	camera_ubo:          Uniform_Buffer_Set,
	output_images:       Image_Set,
	window:              ^Window,

	//frame data
	current_image_index: u32,
	current_cmd:         Command_Buffer,
	accumulation_frame:  u32,

	// different render passes
	restir_render_pass:  Restir_Render_Pass,

	// resources
	shaders:             [4]Shader_Module,
}


raytracing_renderer_init :: proc(
	renderer: ^Raytracing_Renderer,
	window: ^Window,
	allocator := context.allocator,
) {
	renderer^ = {}
	renderer.accumulation_frame = 1
	renderer.window = window
	//TODO: change the creation of vulkan context to the windowa, it makes more sense to be there
	vulkan_context_init(&renderer.ctx, window, allocator)

	renderer.camera_ubo = make_uniform_buffer_set(
		&renderer.ctx,
		size_of(Camera_UBO),
		MAX_FRAMES_IN_FLIGHT,
	)

	renderer.output_images = make_image_set(
		&renderer.ctx,
		.R32G32B32A32_SFLOAT,
		renderer.ctx.swapchain_manager.extent,
		MAX_FRAMES_IN_FLIGHT,
	)

	shader_module_init(&renderer.shaders[0], {.RAYGEN_KHR}, "shaders/rgen.spv", "main")
	shader_module_init(&renderer.shaders[1], {.MISS_KHR}, "shaders/rmiss.spv", "main")
	shader_module_init(&renderer.shaders[2], {.MISS_KHR}, "shaders/shadow.spv", "main")
	shader_module_init(&renderer.shaders[3], {.CLOSEST_HIT_KHR}, "shaders/rchit.spv", "main")

	restir_render_pass_init(&renderer.restir_render_pass, &renderer.ctx)
}

raytracing_renderer_destroy :: proc(renderer: ^Raytracing_Renderer) {
	// TODO: remove this DeviceWaitIdle to the vulkan_context 
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)

	restir_render_pass_destroy(&renderer.restir_render_pass)

	if renderer.scene != nil {
		gpu_scene2_destroy(&renderer.gpu_scene, &renderer.ctx)
	}

	uniform_buffer_set_destroy(&renderer.ctx, &renderer.camera_ubo)

	for &shader in renderer.shaders {
		shader_module_destroy(&shader)
	}
	ctx_destroy(&renderer.ctx)
}

raytracing_renderer_set_scene :: proc(renderer: ^Raytracing_Renderer, scene: ^Scene) {
	renderer.scene = scene
	if renderer.scene != nil {
		gpu_scene2_init(&renderer.gpu_scene, &renderer.ctx, renderer.scene^)
	}
}

raytracing_renderer_begin_frame :: proc(renderer: ^Raytracing_Renderer) {
	renderer.current_image_index, _ = ctx_begin_frame(&renderer.ctx)
	renderer.current_cmd = ctx_request_command_buffer(&renderer.ctx)
}

raytracing_renderer_render_scene :: proc(renderer: ^Raytracing_Renderer, camera: ^Camera) {
	cmd := &renderer.current_cmd

	extent := renderer.ctx.swapchain_manager.extent
	output_image: ^Image
	if camera.dirty {
		renderer.accumulation_frame = 1
		camera.dirty = false
	}

	ubo_buffer := uniform_buffer_set_get(&renderer.camera_ubo, renderer.ctx.current_frame)
	update_camera_ubo(renderer, ubo_buffer, camera)
	if true {

		spec := Raytracing_Spec {
			rgen_shader         = &renderer.shaders[0],
			miss_shaders        = {&renderer.shaders[1], &renderer.shaders[2]},
			closest_hit_shaders = {&renderer.shaders[3]},
			max_tracing_depth   = 2,
		}
		command_buffer_set_raytracing_program(cmd, spec)

		output_image_view := image_set_get_view(renderer.output_images, renderer.ctx.current_frame)
		// TODO: maybe add also layout tracking into the image
		command_buffer_bind_resource(
			cmd,
			2,
			0,
			vk.DescriptorImageInfo{imageView = output_image_view, imageLayout = .GENERAL},
		)
		command_buffer_bind_resource(cmd, 1, 0, buffer_descriptor_info(ubo_buffer^))
		command_buffer_bind_resource(
			cmd,
			0,
			0,
			vk.WriteDescriptorSetAccelerationStructureKHR {
				sType = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
				accelerationStructureCount = 1,
				pAccelerationStructures = &renderer.gpu_scene.tlas.handle,
			},
		)
		command_buffer_bind_resource(
			cmd,
			0,
			1,
			buffer_descriptor_info(renderer.gpu_scene.objects_buffer.buffers[0]),
		)
		command_buffer_bind_resource(
			cmd,
			0,
			2,
			buffer_descriptor_info(renderer.gpu_scene.materials_buffer.buffers[0]),
		)
		command_buffer_bind_resource(
			cmd,
			0,
			3,
			buffer_descriptor_info(renderer.gpu_scene.lights_buffer.buffers[0]),
		)

		command_buffer_push_constant_range(
			cmd,
			0,
			mem.any_to_bytes(
				Raytracing_Push_Constant {
					clear_color = {0.2, 0.2, 0.2},
					accumulation_frame = renderer.accumulation_frame,
				},
			),
		)
		command_buffer_trace_rays(cmd, extent.width, extent.height, 1)
		output_image = image_set_get(&renderer.output_images, renderer.ctx.current_frame)
	} else {
		output_image = restir_render_pass_render(
			&renderer.restir_render_pass,
			cmd,
			&renderer.gpu_scene,
			ubo_buffer^,
		)
	}

	{
		// output_image := image_set_get(&renderer.output_images, renderer.ctx.current_frame)
		image_index := renderer.current_image_index
		storage_image := output_image.handle
		swapchain_image := renderer.ctx.swapchain_manager.images[image_index]
		command_buffer_image_layout_transition_stage_access(
			cmd^,
			renderer.ctx.swapchain_manager.images[renderer.ctx.current_image],
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
			{.TOP_OF_PIPE},
			{.TRANSFER},
			{},
			{.TRANSFER_WRITE},
		)

		command_buffer_image_layout_transition_stage_access(
			cmd^,
			output_image.handle,
			.GENERAL,
			.TRANSFER_SRC_OPTIMAL,
			{.ALL_COMMANDS},
			{.TRANSFER},
			{},
			{.TRANSFER_READ},
		)
		command_buffer_image_blit(
			cmd^,
			dst = swapchain_image,
			src = storage_image,
			dst_offset = {0, 0, 0},
			dst_extent = {i32(extent.width), i32(extent.height), 1},
			src_offset = {0, 0, 0},
			src_extent = {i32(extent.width), i32(extent.height), 1},
			dst_level = 0,
			src_level = 0,
			dst_base_layer = 0,
			src_base_layer = 0,
			dst_format = renderer.ctx.swapchain_manager.format,
			src_format = output_image.format,
			num_layers = 1,
			filter = .LINEAR,
		)

		command_buffer_image_layout_transition_stage_access(
			cmd^,
			swapchain_image,
			.TRANSFER_DST_OPTIMAL,
			.PRESENT_SRC_KHR,
			{.TRANSFER},
			{.BOTTOM_OF_PIPE},
			{.TRANSFER_WRITE},
			{},
		)

		// Transition ray tracing output image back to general layout
		command_buffer_image_layout_transition_stage_access(
			cmd^,
			storage_image,
			.TRANSFER_SRC_OPTIMAL,
			.GENERAL,
			{.TRANSFER},
			{.ALL_COMMANDS},
			{.TRANSFER_READ},
			{},
		)
	}
}

raytracing_renderer_end_frame :: proc(renderer: ^Raytracing_Renderer) {
	_ = vk_check(vk.EndCommandBuffer(renderer.current_cmd.buffer), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, renderer.current_cmd.buffer, renderer.current_image_index)

	command_buffer_reset(&renderer.current_cmd)
	// command_buffer_destroy(&renderer.current_cmd)
	renderer.accumulation_frame += 1
}

@(private = "file")
update_camera_ubo :: proc(renderer: ^Raytracing_Renderer, ubo_buffer: ^Buffer, camera: ^Camera) {
	ubo_data := Camera_UBO {
		projection         = camera.proj,
		view               = camera.view,
		inverse_view       = camera.inverse_view,
		inverse_projection = camera.inverse_proj,
	}
	buffer_map(ubo_buffer)
	buffer_write(ubo_buffer, &ubo_data)
	buffer_flush(ubo_buffer, 0, ubo_buffer.size)
	buffer_unmap(ubo_buffer)
}
