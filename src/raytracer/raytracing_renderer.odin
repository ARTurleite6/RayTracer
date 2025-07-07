#+feature dynamic-literals
package raytracer

import "core:log"
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

	// resources
	gbuffers:            GBuffers,
	raytracing_pipeline: Raytracing_Pipeline2,

	// TODO: remove this in the future
	shaders:             [4]Shader_Module,
	pipeline_layout:     Pipeline_Layout,
}

GBuffers :: struct {
	world_position, normal, albedo, material_properties: Image_Set,
}

raytracing_renderer_init :: proc(
	renderer: ^Raytracing_Renderer,
	window: ^Window,
	allocator := context.allocator,
) {
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

	{ 	// initialize resources
		buffers := &renderer.gbuffers
		buffers.world_position = make_image_set(
			&renderer.ctx,
			.R32G32B32A32_SFLOAT,
			renderer.ctx.swapchain_manager.extent,
			MAX_FRAMES_IN_FLIGHT,
		)
		buffers.normal = make_image_set(
			&renderer.ctx,
			.R16G16B16A16_SFLOAT,
			renderer.ctx.swapchain_manager.extent,
			MAX_FRAMES_IN_FLIGHT,
		)
		buffers.albedo = make_image_set(
			&renderer.ctx,
			.R32G32B32A32_SFLOAT,
			renderer.ctx.swapchain_manager.extent,
			MAX_FRAMES_IN_FLIGHT,
		)
		buffers.material_properties = make_image_set(
			&renderer.ctx,
			.R32G32_SFLOAT,
			renderer.ctx.swapchain_manager.extent,
			MAX_FRAMES_IN_FLIGHT,
		)
	}

	{
		shader_module_init(&renderer.shaders[0], {.RAYGEN_KHR}, "shaders/rgen.spv", "main")
		shader_module_init(&renderer.shaders[1], {.MISS_KHR}, "shaders/rmiss.spv", "main")
		shader_module_init(&renderer.shaders[2], {.MISS_KHR}, "shaders/shadow.spv", "main")
		shader_module_init(&renderer.shaders[3], {.CLOSEST_HIT_KHR}, "shaders/rchit.spv", "main")
		pipeline_layout_init2(
			&renderer.pipeline_layout,
			&renderer.ctx,
			{
				&renderer.shaders[0],
				&renderer.shaders[1],
				&renderer.shaders[2],
				&renderer.shaders[3],
			},
		)

		raytracing_pipeline_init(
			&renderer.raytracing_pipeline,
			&renderer.ctx,
			{layout = &renderer.pipeline_layout, max_ray_recursion = 2},
		)
	}
}

raytracing_renderer_destroy :: proc(renderer: ^Raytracing_Renderer) {
	// TODO: remove this DeviceWaitIdle to the vulkan_context 
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)

	uniform_buffer_set_destroy(&renderer.ctx, &renderer.camera_ubo)
	image_set_destroy(&renderer.ctx, &renderer.output_images)
	{ 	// destroy gbuffers
		buffers := &renderer.gbuffers
		image_set_destroy(&renderer.ctx, &buffers.world_position)
		image_set_destroy(&renderer.ctx, &buffers.albedo)
		image_set_destroy(&renderer.ctx, &buffers.normal)
		image_set_destroy(&renderer.ctx, &buffers.material_properties)
	}

	ctx_destroy(&renderer.ctx)

	renderer^ = {}
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

	output_image_view := image_set_get_view(renderer.output_images, renderer.ctx.current_frame)
	command_buffer_bind_image(&renderer.current_cmd, output_image_view, 0, 2, 0, 0)
}

raytracing_renderer_render_scene :: proc(renderer: ^Raytracing_Renderer) {
	cmd := &renderer.current_cmd

	layout := vulkan_get_descriptor_set_layout(
		&renderer.ctx,
		{
			binding = 0,
			descriptorCount = 1,
			stageFlags = {.RAYGEN_KHR},
			descriptorType = .STORAGE_IMAGE,
		},
	)
	set := vulkan_get_descriptor_set(
		&renderer.ctx,
		&layout,
		{
			binding = 0,
			write_info = vk.DescriptorImageInfo {
				imageView = image_set_get_view(renderer.output_images, renderer.ctx.current_frame),
				imageLayout = .GENERAL,
			},
		},
	)

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		renderer.raytracing_pipeline.state.layout.handle,
		0,
		1,
		&set,
		0,
		nil,
	)
	//
	// vk.CmdPushConstants(
	// 	cmd.buffer,
	// 	renderer.raytracing_pipeline.layout,
	// 	{.RAYGEN_KHR},
	// 	0,
	// 	size_of(Raytracing_Push_Constant),
	// 	&Raytracing_Push_Constant{clear_color = {0.2, 0.2, 0.2}, accumulation_frame = 1},
	// )

	vk.CmdBindPipeline(cmd.buffer, .RAY_TRACING_KHR, renderer.raytracing_pipeline.handle)

	extent := renderer.ctx.swapchain_manager.extent
	vk.CmdTraceRaysKHR(
		cmd.buffer,
		&renderer.raytracing_pipeline.sbt.regions[.Ray_Gen],
		&renderer.raytracing_pipeline.sbt.regions[.Miss],
		&renderer.raytracing_pipeline.sbt.regions[.Hit],
		&renderer.raytracing_pipeline.sbt.regions[.Callable],
		extent.width,
		extent.height,
		1,
	)

	output_image := image_set_get(&renderer.output_images, renderer.ctx.current_frame)
	image_index := renderer.current_image_index
	storage_image := output_image.handle
	swapchain_image := renderer.ctx.swapchain_manager.images[image_index]
	ctx_transition_swapchain_image(
		renderer.ctx,
		cmd^,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		{.TRANSFER_WRITE},
	)
	// image_transition_layout(cmd, swapchain_image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	image_transition_layout_stage_access(
		cmd.buffer,
		storage_image,
		.GENERAL,
		.TRANSFER_SRC_OPTIMAL,
		{.ALL_COMMANDS},
		{.TRANSFER},
		{},
		{.TRANSFER_READ},
	)

	blit_region := vk.ImageBlit {
		srcSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		srcOffsets = [2]vk.Offset3D{{0, 0, 0}, {i32(extent.width), i32(extent.height), 1}},
		dstSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		dstOffsets = [2]vk.Offset3D{{0, 0, 0}, {i32(extent.width), i32(extent.height), 1}},
	}

	// Perform blit operation
	vk.CmdBlitImage(
		cmd.buffer,
		storage_image,
		.TRANSFER_SRC_OPTIMAL,
		swapchain_image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&blit_region,
		.LINEAR, // Use LINEAR for better quality conversion
	)
	ctx_transition_swapchain_image(
		renderer.ctx,
		cmd^,
		.TRANSFER_DST_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.TRANSFER},
		{.BOTTOM_OF_PIPE},
		{.TRANSFER_WRITE},
		{},
	)

	// Transition ray tracing output image back to general layout
	image_transition_layout_stage_access(
		cmd.buffer,
		storage_image,
		.TRANSFER_SRC_OPTIMAL,
		.GENERAL,
		{.TRANSFER},
		{.ALL_COMMANDS},
		{.TRANSFER_READ},
		{},
	)
}

raytracing_renderer_end_frame :: proc(renderer: ^Raytracing_Renderer) {
	ctx_transition_swapchain_image(
		renderer.ctx,
		renderer.current_cmd,
		.UNDEFINED,
		.PRESENT_SRC_KHR,
		{.TRANSFER},
		{.BOTTOM_OF_PIPE},
		{.TRANSFER_WRITE},
		{},
	)
	_ = vk_check(vk.EndCommandBuffer(renderer.current_cmd.buffer), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, renderer.current_cmd.buffer, renderer.current_image_index)

	command_buffer_destroy(&renderer.current_cmd)
}
