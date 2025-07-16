package raytracer

import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Restir_Render_Pass :: struct {
	ctx:            ^Vulkan_Context,
	output_image:   Image_Set,
	shader_modules: [3]Shader_Module,
	gbuffers:       GBuffers,
}

GBuffers :: struct {
	albedo, normal, world_position, emission, material_properties: Image_Set,
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
		&renderer.shader_modules[0],
		{.RAYGEN_KHR},
		"shaders/restir_rgen.spv",
		"main",
	); err != nil {
		log.errorf("Error compiling shader: %v", err)
	}

	if err := shader_module_init(
		&renderer.shader_modules[1],
		{.MISS_KHR},
		"shaders/restir_rmiss.spv",
		"main",
	); err != nil {
		log.errorf("Error compiling shader: %v", err)
	}

	if err := shader_module_init(
		&renderer.shader_modules[2],
		{.CLOSEST_HIT_KHR},
		"shaders/restir_rchit.spv",
		"main",
	); err != nil {
		log.errorf("Error compiling shader: %v", err)
	}

	renderer.gbuffers = make_gbuffers(renderer.ctx, renderer.ctx.swapchain_manager.extent)
}

restir_render_pass_destroy :: proc(renderer: ^Restir_Render_Pass) {
	image_set_destroy(renderer.ctx, &renderer.output_image)

	for &shader in renderer.shader_modules {
		shader_module_destroy(&shader)
	}
}

// TODO: see if this should take the command buffer in
restir_render_pass_render :: proc(
	renderer: ^Restir_Render_Pass,
	cmd: ^Command_Buffer,
	gpu_scene: ^GPU_Scene2,
	camera_ubo: Buffer,
) -> ^Image {
	spec := Raytracing_Spec {
		rgen_shader         = &renderer.shader_modules[0],
		miss_shaders        = {&renderer.shader_modules[1]},
		closest_hit_shaders = {&renderer.shader_modules[2]},
		max_tracing_depth   = 1,
	}
	command_buffer_set_raytracing_program(cmd, spec)
	output_image_view := image_set_get_view(renderer.output_image, renderer.ctx.current_frame)
	command_buffer_bind_resource(
		cmd,
		0,
		0,
		vk.DescriptorImageInfo{imageView = output_image_view, imageLayout = .GENERAL},
	)
	command_buffer_bind_resource(
		cmd,
		0,
		1,
		vk.DescriptorImageInfo {
			imageView = renderer.gbuffers.albedo.image_views[0],
			imageLayout = .GENERAL,
		},
	)
	command_buffer_bind_resource(
		cmd,
		0,
		2,
		vk.DescriptorImageInfo {
			imageView = renderer.gbuffers.normal.image_views[0],
			imageLayout = .GENERAL,
		},
	)
	command_buffer_bind_resource(
		cmd,
		0,
		3,
		vk.DescriptorImageInfo {
			imageView = renderer.gbuffers.world_position.image_views[0],
			imageLayout = .GENERAL,
		},
	)
	command_buffer_bind_resource(
		cmd,
		0,
		4,
		vk.DescriptorImageInfo {
			imageView = renderer.gbuffers.emission.image_views[0],
			imageLayout = .GENERAL,
		},
	)
	command_buffer_bind_resource(
		cmd,
		0,
		5,
		vk.DescriptorImageInfo {
			imageView = renderer.gbuffers.material_properties.image_views[0],
			imageLayout = .GENERAL,
		},
	)

	command_buffer_bind_resource(
		cmd,
		1,
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
		1,
		buffer_descriptor_info(gpu_scene.objects_buffer.buffers[0]),
	)
	command_buffer_bind_resource(
		cmd,
		1,
		2,
		buffer_descriptor_info(gpu_scene.materials_buffer.buffers[0]),
	)

	command_buffer_bind_resource(cmd, 2, 0, buffer_descriptor_info(camera_ubo))

	command_buffer_push_constant_range(
		cmd,
		0,
		mem.any_to_bytes(
			Raytracing_Push_Constant{clear_color = {0.2, 0.2, 0.2}, accumulation_frame = 1},
		),
	)

	command_buffer_trace_rays(
		cmd,
		renderer.ctx.swapchain_manager.extent.width,
		renderer.ctx.swapchain_manager.extent.height,
		1,
	)

	return image_set_get(&renderer.output_image, renderer.ctx.current_frame)
}

make_gbuffers :: proc(ctx: ^Vulkan_Context, extent: vk.Extent2D) -> (buffers: GBuffers) {
	buffers.albedo = make_image_set(ctx, .R16G16B16A16_SFLOAT, extent, MAX_FRAMES_IN_FLIGHT)
	buffers.normal = make_image_set(ctx, .R16G16B16A16_SFLOAT, extent, MAX_FRAMES_IN_FLIGHT)
	buffers.world_position = make_image_set(
		ctx,
		.R32G32B32A32_SFLOAT,
		extent,
		MAX_FRAMES_IN_FLIGHT,
	)
	buffers.emission = make_image_set(ctx, .R16G16B16A16_SFLOAT, extent, MAX_FRAMES_IN_FLIGHT)
	buffers.material_properties = make_image_set(
		ctx,
		.R16G16B16A16_SFLOAT,
		extent,
		MAX_FRAMES_IN_FLIGHT,
	)
	return buffers
}
