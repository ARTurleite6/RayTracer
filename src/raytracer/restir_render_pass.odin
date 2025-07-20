package raytracer

import "core:log"
import "core:mem"
_ :: mem

import vk "vendor:vulkan"

Restir_Render_Pass :: struct {
	ctx:              ^Vulkan_Context,
	output_image:     Image_Set,
	restir_di_shader: Shader_Module,
	vertex_shader:    Shader_Module,
	fragment_shader:  Shader_Module,
	gbuffers:         GBuffers,
	vertex_buffer:    Buffer,
}

GBuffers :: struct {
	albedo, normal, world_position, emission, material_properties: Image_Set,
	depth_test:                                                    Image_Set,
}

restir_render_pass_init :: proc(renderer: ^Restir_Render_Pass, ctx: ^Vulkan_Context) {
	renderer^ = {}
	renderer.ctx = ctx
	renderer.output_image = make_image_set(
		ctx,
		.R32G32B32A32_SFLOAT,
		renderer.ctx.swapchain_manager.extent,
		MAX_FRAMES_IN_FLIGHT,
	)


	if err := shader_module_init(
		&renderer.vertex_shader,
		{.VERTEX},
		"shaders/restir/gbuffer_vert.spv",
		"main",
	); err != nil {
		log.errorf("Error compiling shader: %v", err)
	}

	if err := shader_module_init(
		&renderer.fragment_shader,
		{.FRAGMENT},
		"shaders/restir/gbuffer_frag.spv",
		"main",
	); err != nil {
		log.errorf("Error compiling shader: %v", err)
	}

	if err := shader_module_init(
		&renderer.restir_di_shader,
		{.RAYGEN_KHR},
		"shaders/restir/restir_di_rgen.spv",
		"main",
	); err != nil {
		log.errorf("Error compiling shader: %v", err)
	}

	renderer.gbuffers = make_gbuffers(renderer.ctx, renderer.ctx.swapchain_manager.extent)
}

restir_render_pass_destroy :: proc(renderer: ^Restir_Render_Pass) {
	image_set_destroy(renderer.ctx, &renderer.output_image)
	shader_module_destroy(&renderer.vertex_shader)
	shader_module_destroy(&renderer.fragment_shader)
}

// TODO: see if this should take the command buffer in
restir_render_pass_render :: proc(
	renderer: ^Restir_Render_Pass,
	cmd: ^Command_Buffer,
	gpu_scene: ^GPU_Scene2,
	scene: Scene,
	camera: Camera,
	camera_ubo: Buffer,
) -> ^Image {
	output_image_view := image_set_get_view(renderer.output_image, renderer.ctx.current_frame)
	output_image := image_set_get(&renderer.output_image, renderer.ctx.current_frame)

	albedo_view := image_set_get_view(renderer.gbuffers.albedo, renderer.ctx.current_frame)
	normal_view := image_set_get_view(renderer.gbuffers.normal, renderer.ctx.current_frame)
	world_pos_view := image_set_get_view(
		renderer.gbuffers.world_position,
		renderer.ctx.current_frame,
	)
	emission_view := image_set_get_view(renderer.gbuffers.emission, renderer.ctx.current_frame)
	material_props_view := image_set_get_view(
		renderer.gbuffers.material_properties,
		renderer.ctx.current_frame,
	)
	depth_image_view := image_set_get_view(
		renderer.gbuffers.depth_test,
		renderer.ctx.current_frame,
	)

	{
		command_buffer_set_graphics_program(
			cmd,
			&renderer.vertex_shader,
			&renderer.fragment_shader,
		)

		color_attachments := [?]vk.RenderingAttachmentInfo {
			{
				sType = .RENDERING_ATTACHMENT_INFO,
				imageView = albedo_view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {color = {float32 = {0, 0, 0, 1}}},
			},
			{
				sType = .RENDERING_ATTACHMENT_INFO,
				imageView = normal_view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {color = {float32 = {0, 0, 0, 1}}},
			},
			{
				sType = .RENDERING_ATTACHMENT_INFO,
				imageView = world_pos_view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {color = {float32 = {0, 0, 0, 1}}},
			},
			{
				sType = .RENDERING_ATTACHMENT_INFO,
				imageView = emission_view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {color = {float32 = {0, 0, 0, 1}}},
			},
			{
				sType = .RENDERING_ATTACHMENT_INFO,
				imageView = material_props_view,
				imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
				loadOp = .CLEAR,
				storeOp = .STORE,
				clearValue = {color = {float32 = {0, 0, 0, 1}}},
			},
		}

		// TODO: make this a little bit more generic in order to work both on raytracing and on rasterization
		command_buffer_begin_render_pass(
			cmd,
			&vk.RenderingInfo {
				sType = .RENDERING_INFO,
				renderArea = {{0, 0}, renderer.ctx.swapchain_manager.extent},
				layerCount = 1,
				colorAttachmentCount = u32(len(color_attachments)),
				pColorAttachments = raw_data(color_attachments[:]),
				pDepthAttachment = &{
					sType = .RENDERING_ATTACHMENT_INFO,
					imageView = depth_image_view,
					imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
					loadOp = .CLEAR,
					storeOp = .STORE,
					clearValue = {depthStencil = {depth = 1, stencil = 0}},
				},
			},
			Render_Pass_Info {
				color_formats = {
					renderer.gbuffers.albedo.images[0].format,
					renderer.gbuffers.normal.images[0].format,
					renderer.gbuffers.world_position.images[0].format,
					renderer.gbuffers.emission.images[0].format,
					renderer.gbuffers.material_properties.images[0].format,
				},
				depth_format = .D32_SFLOAT,
			},
		)
		defer command_buffer_end_render_pass(cmd)

		command_buffer_set_vertex_binding(cmd, 0, size_of(Vertex))
		command_buffer_set_vertex_attrib(cmd, 0, 0, .R32G32B32_SFLOAT, 0)
		command_buffer_set_vertex_attrib(cmd, 1, 0, .R32G32B32_SFLOAT, size_of(Vec3))

		command_buffer_bind_resource(cmd, 0, 0, buffer_descriptor_info(camera_ubo))
		command_buffer_bind_resource(
			cmd,
			0,
			1,
			buffer_descriptor_info(gpu_scene.materials_buffer.buffers[0]),
		)

		for object in scene.objects {
			mesh := gpu_scene.meshes_data[object.mesh_index]

			command_buffer_bind_vertex_buffers(cmd^, 0, {mesh.vertex_buffer}, {0})
			command_buffer_bind_index_buffer(cmd^, mesh.index_buffer, 0, .UINT32)

			Push_Constant :: struct #align (4) {
				model_matrix:   Mat4,
				normal_matrix:  Mat4,
				material_index: u32,
			}
			command_buffer_push_constant_range(
				cmd,
				0,
				mem.any_to_bytes(
					Push_Constant {
						model_matrix = object.transform.model_matrix,
						normal_matrix = object.transform.normal_matrix,
						material_index = u32(object.material_index),
					},
				),
			)

			command_buffer_draw_indexed(cmd, u32(mesh.num_indices), 1, 0, 0, 0)
		}
	}

	vk.CmdPipelineBarrier(
		cmd.buffer,
		{.FRAGMENT_SHADER},
		{.RAY_TRACING_SHADER_KHR},
		{},
		0,
		{},
		0,
		{},
		0,
		{},
	)

	{
		spec := Raytracing_Spec {
			rgen_shader         = &renderer.restir_di_shader,
			miss_shaders        = {},
			closest_hit_shaders = {},
			max_tracing_depth   = 1,
		}
		command_buffer_set_raytracing_program(cmd, spec)

		command_buffer_bind_resource(
			cmd,
			0,
			0,
			vk.WriteDescriptorSetAccelerationStructureKHR {
				sType = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
				accelerationStructureCount = 1,
				pAccelerationStructures = &gpu_scene.tlas.handle,
			},
		)

		command_buffer_bind_resource(
			cmd,
			1,
			0,
			vk.DescriptorImageInfo{imageView = albedo_view, imageLayout = .GENERAL},
		)

		command_buffer_bind_resource(
			cmd,
			1,
			1,
			vk.DescriptorImageInfo{imageView = normal_view, imageLayout = .GENERAL},
		)

		command_buffer_bind_resource(
			cmd,
			1,
			2,
			vk.DescriptorImageInfo{imageView = world_pos_view, imageLayout = .GENERAL},
		)

		command_buffer_bind_resource(
			cmd,
			1,
			3,
			vk.DescriptorImageInfo{imageView = emission_view, imageLayout = .GENERAL},
		)

		command_buffer_bind_resource(
			cmd,
			1,
			4,
			vk.DescriptorImageInfo{imageView = material_props_view, imageLayout = .GENERAL},
		)

		command_buffer_bind_resource(
			cmd,
			1,
			5,
			vk.DescriptorImageInfo{imageView = output_image_view, imageLayout = .GENERAL},
		)

		command_buffer_trace_rays(
			cmd,
			renderer.ctx.swapchain_manager.extent.width,
			renderer.ctx.swapchain_manager.extent.height,
			1,
		)
	}

	return output_image
}

make_gbuffers :: proc(ctx: ^Vulkan_Context, extent: vk.Extent2D) -> (buffers: GBuffers) {
	buffers.albedo = make_image_set(ctx, .R8G8B8A8_UNORM, extent, MAX_FRAMES_IN_FLIGHT)
	buffers.normal = make_image_set(ctx, .R32G32B32A32_SFLOAT, extent, MAX_FRAMES_IN_FLIGHT)
	buffers.world_position = make_image_set(
		ctx,
		.R32G32B32A32_SFLOAT,
		extent,
		MAX_FRAMES_IN_FLIGHT,
	)
	buffers.emission = make_image_set(ctx, .R32G32B32A32_SFLOAT, extent, MAX_FRAMES_IN_FLIGHT)
	buffers.material_properties = make_image_set(
		ctx,
		.R32G32B32A32_SFLOAT,
		extent,
		MAX_FRAMES_IN_FLIGHT,
	)

	buffers.depth_test = make_image_set(ctx, .D32_SFLOAT, extent, MAX_FRAMES_IN_FLIGHT)
	return buffers
}
