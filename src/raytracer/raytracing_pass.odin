package raytracer

import "core:mem"
import "core:mem/tlsf"
import "core:strings"
import vma "external:odin-vma"
import vk "vendor:vulkan"

Shader_Binding_Table :: struct {
	raygen_buffer, miss_buffer, hit_buffer: Buffer,
}

Stage_Indices :: enum {
	Raygen = 0,
	Miss,
	Closest_Hit,
}

Pipeline_Error :: enum {
	None = 0,
	Cache_Creation_Failed,
	Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Descriptor_Set_Creation_Failed,
	Pool_Creation_Failed,
	Shader_Creation_Failed,
}

Pipeline :: struct {
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
}

Raytracing_Push_Constant :: struct {
	clear_color:        Vec3,
	accumulation_frame: u32,
}

align_up :: proc(x, align: u32) -> u32 {
	return u32(tlsf.align_up(uint(x), uint(align)))
}

Raytracing_Pass :: struct {
	pipeline:                    Pipeline,

	// output image
	image:                       Image,
	image_view:                  vk.ImageView,

	// TODO: this will change in the future with descriptor caching
	image_descriptor_set_layout: vk.DescriptorSetLayout,
	image_descriptor_set:        vk.DescriptorSet,
	ctx:                         ^Vulkan_Context,
	rt_props:                    vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	sbt:                         Shader_Binding_Table,
}

raytracing_pass_init :: proc(
	rt: ^Raytracing_Pass,
	ctx: ^Vulkan_Context,
	shaders: []Shader,
	scene_descriptor_set_layout, camera_descriptor_set_layout: vk.DescriptorSetLayout,
) {
	rt.ctx = ctx
	rt.rt_props = vulkan_get_raytracing_pipeline_propertis(rt.ctx)

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

	device := vulkan_get_device_handle(ctx)
	{ 	// create image descriptor set layout
		bindings := [?]vk.DescriptorSetLayoutBinding {
			{
				binding = 0,
				descriptorCount = 1,
				descriptorType = .STORAGE_IMAGE,
				stageFlags = {.RAYGEN_KHR},
			},
		}

		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = u32(len(bindings)),
			pBindings    = raw_data(bindings[:]),
		}

		vk.CreateDescriptorSetLayout(device, &create_info, nil, &rt.image_descriptor_set_layout)

		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = rt.ctx.descriptor_pool,
			descriptorSetCount = 1,
			pSetLayouts        = &rt.image_descriptor_set_layout,
		}

		vk.AllocateDescriptorSets(
			vulkan_get_device_handle(rt.ctx),
			&alloc_info,
			&rt.image_descriptor_set,
		)

		image_info := vk.DescriptorImageInfo {
			imageView   = rt.image_view,
			imageLayout = .GENERAL,
		}

		write_info := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = rt.image_descriptor_set,
			dstBinding      = 0, // Assuming binding 0 is for storage image
			descriptorType  = .STORAGE_IMAGE,
			descriptorCount = 1,
			pImageInfo      = &image_info,
		}

		// Update the descriptor set
		vk.UpdateDescriptorSets(vulkan_get_device_handle(rt.ctx), 1, &write_info, 0, nil)
	}

	{ 	// create pipeline layout
		layouts := [?]vk.DescriptorSetLayout {
			rt.image_descriptor_set_layout,
			scene_descriptor_set_layout,
			camera_descriptor_set_layout,
		}
		range := vk.PushConstantRange {
			stageFlags = {.RAYGEN_KHR},
			offset     = 0,
			size       = size_of(Raytracing_Push_Constant),
		}

		create_info := vk.PipelineLayoutCreateInfo {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = u32(len(layouts)),
			pSetLayouts            = raw_data(layouts[:]),
			pushConstantRangeCount = 1,
			pPushConstantRanges    = &range,
		}

		vk.CreatePipelineLayout(device, &create_info, nil, &rt.pipeline.layout)
	}

	// TODO: probably this should be appart of the setup on the raytracing_stage_init
	groups := [?]vk.RayTracingShaderGroupCreateInfoKHR {
		{
			sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
			type = .GENERAL,
			generalShader = u32(Stage_Indices.Raygen),
			closestHitShader = ~u32(0),
			anyHitShader = ~u32(0),
			intersectionShader = ~u32(0),
		},
		{
			sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
			type = .GENERAL,
			generalShader = u32(Stage_Indices.Miss),
			closestHitShader = ~u32(0),
			anyHitShader = ~u32(0),
			intersectionShader = ~u32(0),
		},
		{
			sType = .RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
			type = .TRIANGLES_HIT_GROUP,
			generalShader = ~u32(0),
			closestHitShader = u32(Stage_Indices.Closest_Hit),
			anyHitShader = ~u32(0),
			intersectionShader = ~u32(0),
		},
	}

	shader_stages := make([]vk.PipelineShaderStageCreateInfo, len(shaders), context.temp_allocator)
	for shader, i in shaders {
		shader_stages[i] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = shader.type,
			module = shader.module,
			pName  = strings.clone_to_cstring(shader.name, context.temp_allocator),
		}
	}
	create_info := vk.RayTracingPipelineCreateInfoKHR {
		sType                        = .RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
		stageCount                   = u32(len(shader_stages)),
		pStages                      = raw_data(shader_stages),
		groupCount                   = u32(len(groups)),
		pGroups                      = raw_data(groups[:]),
		maxPipelineRayRecursionDepth = 1,
		layout                       = rt.pipeline.layout,
	}

	_ = vk_check(
		vk.CreateRayTracingPipelinesKHR(device, 0, 0, 1, &create_info, nil, &rt.pipeline.pipeline),
		"Failed to create raytracing pipeline",
	)

	raytracing_pass_create_shader_binding_table(rt)
}

raytracing_pass_destroy :: proc(rt: ^Raytracing_Pass) {
	device := vulkan_get_device_handle(rt.ctx)
	vk.DestroyPipeline(device, rt.pipeline.pipeline, nil)
	vk.DestroyPipelineLayout(device, rt.pipeline.layout, nil)
	image_destroy(&rt.image, rt.ctx^)
	image_view_destroy(rt.image_view, rt.ctx^)

	vk.DestroyDescriptorSetLayout(device, rt.image_descriptor_set_layout, nil)
	buffer_destroy(&rt.sbt.raygen_buffer, rt.ctx.device)
	buffer_destroy(&rt.sbt.hit_buffer, rt.ctx.device)
	buffer_destroy(&rt.sbt.miss_buffer, rt.ctx.device)
}

raytracing_pass_render :: proc(
	rt: ^Raytracing_Pass,
	cmd: ^Command_Buffer,
	scene_descriptor_set, camera_descriptor_set: vk.DescriptorSet,
	accumulation_frame, image_index: u32,
) {
	descriptor_sets := [?]vk.DescriptorSet {
		rt.image_descriptor_set,
		scene_descriptor_set,
		camera_descriptor_set,
	}

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		rt.pipeline.layout,
		0,
		u32(len(descriptor_sets)),
		raw_data(descriptor_sets[:]),
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd.buffer,
		rt.pipeline.layout,
		{.RAYGEN_KHR},
		0,
		size_of(Raytracing_Push_Constant),
		&Raytracing_Push_Constant {
			clear_color = {0.2, 0.2, 0.2},
			accumulation_frame = accumulation_frame,
		},
	)

	vk.CmdBindPipeline(cmd.buffer, .RAY_TRACING_KHR, rt.pipeline.pipeline)

	handle_size_aligned := align_up(
		rt.rt_props.shaderGroupHandleSize,
		rt.rt_props.shaderGroupHandleAlignment,
	)

	raygen_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(rt.sbt.raygen_buffer, rt.ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}

	miss_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(rt.sbt.miss_buffer, rt.ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}

	hit_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(rt.sbt.hit_buffer, rt.ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}
	callable_entry := vk.StridedDeviceAddressRegionKHR{}

	extent := rt.ctx.swapchain_manager.extent
	vk.CmdTraceRaysKHR(
		cmd.buffer,
		&raygen_sbt_entry,
		&miss_sbt_entry,
		&hit_sbt_entry,
		&callable_entry,
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

raytracing_pass_create_shader_binding_table :: proc(rt: ^Raytracing_Pass) {
	device := rt.ctx.device
	handle_size := rt.rt_props.shaderGroupHandleSize
	handle_alignment := rt.rt_props.shaderGroupHandleAlignment
	handle_size_aligned := align_up(handle_size, handle_alignment)

	group_count: u32 = 3
	sbt_size := group_count * handle_size_aligned

	sbt_buffer_usage_flags: vk.BufferUsageFlags = {
		.SHADER_BINDING_TABLE_KHR,
		.TRANSFER_SRC,
		.SHADER_DEVICE_ADDRESS,
	}

	sbt_memory_usage: vma.Memory_Usage = .Cpu_To_Gpu

	buffer_init(
		&rt.sbt.raygen_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)
	buffer_init(
		&rt.sbt.miss_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)
	buffer_init(
		&rt.sbt.hit_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)

	shader_handle_storage := make([]u8, sbt_size, context.temp_allocator)

	_ = vk_check(
		vk.GetRayTracingShaderGroupHandlesKHR(
			device.logical_device.ptr,
			rt.pipeline.pipeline,
			0,
			group_count,
			int(sbt_size),
			raw_data(shader_handle_storage),
		),
		"Failed to get shader handles",
	)

	data: rawptr
	data, _ = buffer_map(&rt.sbt.raygen_buffer, device)
	mem.copy(data, raw_data(shader_handle_storage), int(handle_size))

	data, _ = buffer_map(&rt.sbt.miss_buffer, device)
	mem.copy(
		data,
		rawptr(uintptr(raw_data(shader_handle_storage)) + uintptr(handle_size_aligned)),
		int(handle_size),
	)

	data, _ = buffer_map(&rt.sbt.hit_buffer, device)
	mem.copy(
		data,
		rawptr(uintptr(raw_data(shader_handle_storage)) + uintptr(handle_size_aligned * 2)),
		int(handle_size),
	)

	buffer_unmap(&rt.sbt.raygen_buffer, device)
	buffer_unmap(&rt.sbt.miss_buffer, device)
	buffer_unmap(&rt.sbt.hit_buffer, device)
}
