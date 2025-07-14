#+feature dynamic-literals
package raytracer

import "core:log"
import "core:slice"
_ :: slice
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
	raytracing_pipeline: ^Raytracing_Pipeline2,

	// TODO: remove this in the future
	shaders:             [4]Shader_Module,
	pipeline_layout:     ^Pipeline_Layout,
	descriptor_sets:     [3]^Descriptor_Set2,
}

GBuffers :: struct {
	world_position, normal, albedo, material_properties: Image_Set,
}

raytracing_renderer_init :: proc(
	renderer: ^Raytracing_Renderer,
	window: ^Window,
	allocator := context.allocator,
) {
	renderer^ = {}
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
		renderer.pipeline_layout, _ = resource_cache_request_pipeline_layout(
			&renderer.ctx.cache,
			&renderer.ctx,
			{
				&renderer.shaders[0],
				&renderer.shaders[1],
				&renderer.shaders[2],
				&renderer.shaders[3],
			},
		)

		renderer.raytracing_pipeline, _ = resource_cache_request_raytracing_pipeline(
			&renderer.ctx.cache,
			&renderer.ctx,
			{layout = renderer.pipeline_layout, max_ray_recursion = 2},
		)

		log.debug(renderer.raytracing_pipeline)
	}

	// TODO: make all this bindings on the command buffer on flight
	{ 	// setting set 2
		image_set_layout := renderer.pipeline_layout.descriptor_set_layouts[2]
		b := make_binding_map(vk.DescriptorImageInfo)
		binding_map_set_binding(
			&b,
			0,
			vk.DescriptorImageInfo {
				imageView = image_set_get_view(renderer.output_images, 0),
				imageLayout = .GENERAL,
			},
		)
		renderer.descriptor_sets[2], _ = resource_cache_request_descriptor_set2(
			&renderer.ctx.cache,
			&renderer.ctx,
			layout = image_set_layout,
			buffer_infos = {},
			image_infos = b,
			acceleration_structure_infos = {},
		)
		descriptor_set_update2(renderer.descriptor_sets[2], &renderer.ctx)
	}

	{ 	// camera set
		set_layout := renderer.pipeline_layout.descriptor_set_layouts[1]
		buffer_b := make_binding_map(vk.DescriptorBufferInfo)
		binding_map_set_binding(
			&buffer_b,
			0,
			buffer_descriptor_info(renderer.camera_ubo.buffers[0]),
		)

		renderer.descriptor_sets[1], _ = resource_cache_request_descriptor_set2(
			&renderer.ctx.cache,
			&renderer.ctx,
			set_layout,
			buffer_infos = buffer_b,
			image_infos = {},
			acceleration_structure_infos = {},
		)
		descriptor_set_update2(renderer.descriptor_sets[1], &renderer.ctx)
	}

}

raytracing_renderer_destroy :: proc(renderer: ^Raytracing_Renderer) {
	// TODO: remove this DeviceWaitIdle to the vulkan_context 
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)

	if renderer.scene != nil {
		gpu_scene2_destroy(&renderer.gpu_scene, &renderer.ctx)
	}

	uniform_buffer_set_destroy(&renderer.ctx, &renderer.camera_ubo)
	image_set_destroy(&renderer.ctx, &renderer.output_images)
	{ 	// destroy gbuffers
		buffers := &renderer.gbuffers
		image_set_destroy(&renderer.ctx, &buffers.world_position)
		image_set_destroy(&renderer.ctx, &buffers.albedo)
		image_set_destroy(&renderer.ctx, &buffers.normal)
		image_set_destroy(&renderer.ctx, &buffers.material_properties)
	}

	for &shader in renderer.shaders {
		shader_module_destroy(&shader)
	}
	ctx_destroy(&renderer.ctx)
}

raytracing_renderer_set_scene :: proc(renderer: ^Raytracing_Renderer, scene: ^Scene) {
	renderer.scene = scene
	if renderer.scene != nil {
		gpu_scene2_init(&renderer.gpu_scene, &renderer.ctx, renderer.scene^)

		{ 	// setting set 0
			set_layout := renderer.pipeline_layout.descriptor_set_layouts[0]
			as_b := make_binding_map(vk.WriteDescriptorSetAccelerationStructureKHR)
			binding_map_set_binding(
				&as_b,
				0,
				vk.WriteDescriptorSetAccelerationStructureKHR {
					sType = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
					accelerationStructureCount = 1,
					pAccelerationStructures = &renderer.gpu_scene.tlas.handle,
				},
			)

			buffer_b := make_binding_map(vk.DescriptorBufferInfo)
			binding_map_set_binding(
				&buffer_b,
				1,
				buffer_descriptor_info(renderer.gpu_scene.objects_buffer.buffers[0]),
			)
			binding_map_set_binding(
				&buffer_b,
				2,
				buffer_descriptor_info(renderer.gpu_scene.materials_buffer.buffers[0]),
			)
			binding_map_set_binding(
				&buffer_b,
				3,
				buffer_descriptor_info(renderer.gpu_scene.lights_buffer.buffers[0]),
			)

			renderer.descriptor_sets[0], _ = resource_cache_request_descriptor_set2(
				&renderer.ctx.cache,
				&renderer.ctx,
				layout = set_layout,
				buffer_infos = buffer_b,
				image_infos = {},
				acceleration_structure_infos = as_b,
			)
			// descriptor_set_update2(renderer.descriptor_sets[0], &renderer.ctx)

			device := vulkan_get_device_handle(&renderer.ctx)
			as_info := vk.WriteDescriptorSetAccelerationStructureKHR {
				sType                      = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
				accelerationStructureCount = 1,
				pAccelerationStructures    = &renderer.gpu_scene.tlas.handle,
			}
			objects_buffer_info := buffer_descriptor_info(
				renderer.gpu_scene.objects_buffer.buffers[0],
			)
			materials_buffer_info := buffer_descriptor_info(
				renderer.gpu_scene.materials_buffer.buffers[0],
			)
			lights_buffer_info := buffer_descriptor_info(
				renderer.gpu_scene.lights_buffer.buffers[0],
			)
			writes := [?]vk.WriteDescriptorSet {
				{
					sType = .WRITE_DESCRIPTOR_SET,
					pNext = &as_info,
					dstSet = renderer.descriptor_sets[0].handle,
					dstBinding = 0,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .ACCELERATION_STRUCTURE_KHR,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = renderer.descriptor_sets[0].handle,
					dstBinding = 1,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .STORAGE_BUFFER,
					pBufferInfo = &objects_buffer_info,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = renderer.descriptor_sets[0].handle,
					dstBinding = 2,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .STORAGE_BUFFER,
					pBufferInfo = &materials_buffer_info,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = renderer.descriptor_sets[0].handle,
					dstBinding = 3,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = .STORAGE_BUFFER,
					pBufferInfo = &lights_buffer_info,
				},
			}
			vk.UpdateDescriptorSets(device, len(writes), raw_data(writes[:]), 0, nil)
		}

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

	descriptor_sets := slice.mapper(
		renderer.descriptor_sets[:],
		proc(set: ^Descriptor_Set2) -> vk.DescriptorSet {
			return set.handle
		},
		allocator = context.temp_allocator,
	)

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		renderer.raytracing_pipeline.state.layout.handle,
		0,
		3,
		raw_data(descriptor_sets),
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd.buffer,
		renderer.raytracing_pipeline.state.layout.handle,
		{.RAYGEN_KHR},
		0,
		size_of(Raytracing_Push_Constant),
		&Raytracing_Push_Constant{clear_color = {0.2, 0.2, 0.2}, accumulation_frame = 1},
	)

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
	// ctx_transition_swapchain_image(
	// 	renderer.ctx,
	// 	renderer.current_cmd,
	// 	.UNDEFINED,
	// 	.PRESENT_SRC_KHR,
	// 	{.TRANSFER},
	// 	{.BOTTOM_OF_PIPE},
	// 	{.TRANSFER_WRITE},
	// 	{},
	// )
	_ = vk_check(vk.EndCommandBuffer(renderer.current_cmd.buffer), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, renderer.current_cmd.buffer, renderer.current_image_index)

	command_buffer_destroy(&renderer.current_cmd)
}
