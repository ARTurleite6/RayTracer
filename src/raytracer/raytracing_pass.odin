package raytracer

import "core:mem"

import vk "vendor:vulkan"

Raytracing_Push_Constant :: struct {
	clear_color:        Vec3,
	accumulation_frame: u32,
}

align_up :: proc(x, align: u32) -> u32 {
	return u32(mem.align_forward_uint(uint(x), uint(align)))
}

Raytracing_Pass :: struct {
	rt_pipeline:                 Raytracing_Pipeline,

	// output image
	image:                       Image,
	image_view:                  vk.ImageView,

	// TODO: this will change in the future with descriptor caching
	image_descriptor_set_layout: Descriptor_Set_Layout,
	image_descriptor_set:        Descriptor_Set,
	ctx:                         ^Vulkan_Context,
}

raytracing_pass_init :: proc(
	rt: ^Raytracing_Pass,
	ctx: ^Vulkan_Context,
	shaders: []Shader,
	scene_descriptor_set_layout, camera_descriptor_set_layout: vk.DescriptorSetLayout,
) {
	rt.ctx = ctx

	{ 	// create image descriptor set layout
		rt.image_descriptor_set_layout = create_descriptor_set_layout(
			ctx,
			{
				binding = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_IMAGE,
				stageFlags = {.RAYGEN_KHR},
			},
		)

		rt.image_descriptor_set = descriptor_set_allocate(&rt.image_descriptor_set_layout)
		raytracing_pass_create_image(rt)
	}

	{ 	// create raytracing pipeline
		rt_pipeline_init(&rt.rt_pipeline, ctx)

		for shader, i in shaders {
			rt_pipeline_add_shader(&rt.rt_pipeline, shader, i)
		}
		pipeline_add_descriptor_set_layout(&rt.rt_pipeline, rt.image_descriptor_set_layout.handle)
		pipeline_add_descriptor_set_layout(&rt.rt_pipeline, scene_descriptor_set_layout)
		pipeline_add_descriptor_set_layout(&rt.rt_pipeline, camera_descriptor_set_layout)
		pipeline_add_push_constant_range(
			&rt.rt_pipeline,
			{stageFlags = {.RAYGEN_KHR}, offset = 0, size = size_of(Raytracing_Push_Constant)},
		)
		rt_pipeline_build(&rt.rt_pipeline, rt.ctx, max_pipeline_recursion = 2)
	}
}

raytracing_pass_destroy :: proc(rt: ^Raytracing_Pass) {
	device := vulkan_get_device_handle(rt.ctx)
	rt_pipeline_destroy(&rt.rt_pipeline, device)
	image_destroy(&rt.image, rt.ctx^)
	image_view_destroy(rt.image_view, rt.ctx^)

	descriptor_set_layout_destroy(&rt.image_descriptor_set_layout)
}

raytracing_pass_resize_image :: proc(rt: ^Raytracing_Pass) {
	image_destroy(&rt.image, rt.ctx^)
	image_view_destroy(rt.image_view, rt.ctx^)

	raytracing_pass_create_image(rt)
}

raytracing_pass_create_image :: proc(rt: ^Raytracing_Pass) {
	ctx := rt.ctx

	image_init(&rt.image, ctx, .R32G32B32A32_SFLOAT, ctx.swapchain_manager.extent)
	image_view_init(&rt.image_view, rt.image, ctx)

	{
		cmd := device_begin_single_time_commands(ctx.device, ctx.device.command_pool)
		defer device_end_single_time_commands(ctx.device, ctx.device.command_pool, cmd)
		image_transition_layout_stage_access(
			cmd,
			rt.image.handle,
			.UNDEFINED,
			.GENERAL,
			{.ALL_COMMANDS},
			{.ALL_COMMANDS},
			{},
			{},
		)
	}

	descriptor_set_update(
		&rt.image_descriptor_set,
		{
			binding = 0,
			write_info = vk.DescriptorImageInfo{imageView = rt.image_view, imageLayout = .GENERAL},
		},
	)
}

raytracing_pass_render :: proc(
	rt: ^Raytracing_Pass,
	cmd: ^Command_Buffer,
	scene_descriptor_set, camera_descriptor_set: vk.DescriptorSet,
	accumulation_frame, image_index: u32,
) {
	descriptor_sets := [?]vk.DescriptorSet {
		rt.image_descriptor_set.handle,
		scene_descriptor_set,
		camera_descriptor_set,
	}

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		rt.rt_pipeline.layout,
		0,
		u32(len(descriptor_sets)),
		raw_data(descriptor_sets[:]),
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd.buffer,
		rt.rt_pipeline.layout,
		{.RAYGEN_KHR},
		0,
		size_of(Raytracing_Push_Constant),
		&Raytracing_Push_Constant {
			clear_color = {0.2, 0.2, 0.2},
			accumulation_frame = accumulation_frame,
		},
	)

	vk.CmdBindPipeline(cmd.buffer, .RAY_TRACING_KHR, rt.rt_pipeline.handle)

	extent := rt.ctx.swapchain_manager.extent
	vk.CmdTraceRaysKHR(
		cmd.buffer,
		&rt.rt_pipeline.shader_binding_table.regions[.Ray_Gen],
		&rt.rt_pipeline.shader_binding_table.regions[.Miss],
		&rt.rt_pipeline.shader_binding_table.regions[.Hit],
		&rt.rt_pipeline.shader_binding_table.regions[.Callable],
		extent.width,
		extent.height,
		1,
	)

	storage_image := rt.image.handle
	swapchain_image := rt.ctx.swapchain_manager.images[image_index]
	ctx_transition_swapchain_image(
		rt.ctx^,
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
		rt.ctx^,
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
