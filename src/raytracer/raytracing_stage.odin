package raytracer

import "base:runtime"
import "core:log"
import glm "core:math/linalg"
import "core:mem/tlsf"
import "core:strings"
import vma "external:odin-vma"
import vk "vendor:vulkan"

align_up :: proc(x, align: u32) -> u32 {
	return u32(tlsf.align_up(uint(x), uint(align)))
}

// TODO: see if this is needed
Render_Data :: struct {
	renderer: ^Renderer,
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
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

Raytracing_Context :: struct {
	pipeline:        Pipeline,
	sbt:             Shader_Binding_Table,
	rt_properties:   vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	descriptor_sets: []vk.DescriptorSet,
	vk_ctx:          ^Vulkan_Context,
}

Shader_Binding_Table :: struct {
	raygen_buffer, miss_buffer, hit_buffer: Buffer,
}


Stage_Indices :: enum {
	Raygen = 0,
	Miss,
	Closest_Hit,
}

rt_init :: proc(
	rt_ctx: ^Raytracing_Context,
	vk_ctx: ^Vulkan_Context,
	descriptor_manager: Descriptor_Set_Manager,
	push_constants: []vk.PushConstantRange,
	shaders: []Shader,
) {
	rt_ctx.vk_ctx = vk_ctx
	device := rt_ctx.vk_ctx.device.logical_device.ptr
	descriptor_layouts := descriptor_set_manager_get_descriptor_layouts(
		descriptor_manager,
		context.temp_allocator,
	)
	log.debug(descriptor_layouts)

	layout_create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(descriptor_layouts)),
		pSetLayouts            = raw_data(descriptor_layouts[:]),
		pushConstantRangeCount = u32(len(push_constants)),
		pPushConstantRanges    = raw_data(push_constants),
	}

	_ = vk_check(
		vk.CreatePipelineLayout(device, &layout_create_info, nil, &rt_ctx.pipeline.layout),
		"Failed to create pipeline layout",
	)

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
		layout                       = rt_ctx.pipeline.layout,
	}

	_ = vk_check(
		vk.CreateRayTracingPipelinesKHR(
			device,
			0,
			0,
			1,
			&create_info,
			nil,
			&rt_ctx.pipeline.handle,
		),
		"Failed to create raytracing pipeline",
	)

	rt_ctx.descriptor_sets = descriptor_set_manager_allocate_descriptor_sets(descriptor_manager)

	rt_create_shader_binding_table(rt_ctx, rt_ctx.vk_ctx.device)
}

rt_destroy :: proc(rt_ctx: ^Raytracing_Context) {
	buffer_destroy(&rt_ctx.sbt.raygen_buffer, rt_ctx.vk_ctx.device)
	buffer_destroy(&rt_ctx.sbt.miss_buffer, rt_ctx.vk_ctx.device)
	buffer_destroy(&rt_ctx.sbt.hit_buffer, rt_ctx.vk_ctx.device)
}

raytracing_render :: proc(
	rt_ctx: Raytracing_Context,
	cmd: Command_Buffer,
	image_index: u32,
	render_data: Render_Data,
) {
	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		rt_ctx.pipeline.layout,
		0,
		u32(len(rt_ctx.descriptor_sets)),
		raw_data(rt_ctx.descriptor_sets),
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd.buffer,
		rt_ctx.pipeline.layout,
		{.RAYGEN_KHR},
		0,
		size_of(Raytracing_Push_Constant),
		&Raytracing_Push_Constant {
			clear_color = {0.2, 0.2, 0.2},
			light_pos = glm.vector_normalize(Vec3{-1.0, -4.0, -1.0}),
			light_intensity = 1,
			ambient_strength = 0.1,
			accumulation_frame = render_data.renderer.accumulation_frame,
		},
	)

	vk.CmdBindPipeline(cmd.buffer, .RAY_TRACING_KHR, rt_ctx.pipeline.handle)

	handle_size_aligned := align_up(
		rt_ctx.rt_properties.shaderGroupHandleSize,
		rt_ctx.rt_properties.shaderGroupHandleAlignment,
	)

	raygen_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(rt_ctx.sbt.raygen_buffer, rt_ctx.vk_ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}

	miss_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(rt_ctx.sbt.miss_buffer, rt_ctx.vk_ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}

	hit_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(rt_ctx.sbt.hit_buffer, rt_ctx.vk_ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}
	callable_entry := vk.StridedDeviceAddressRegionKHR{}

	extent := render_data.renderer.ctx.swapchain_manager.extent
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

	storage_image := render_data.renderer.ctx.raytracing_image.handle
	swapchain_image := render_data.renderer.ctx.swapchain_manager.images[image_index]
	ctx_transition_swapchain_image(
		rt_ctx.vk_ctx^,
		cmd,
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
		rt_ctx.vk_ctx^,
		cmd,
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

rt_create_shader_binding_table :: proc(rt_ctx: ^Raytracing_Context, device: ^Device) {
	handle_size := rt_ctx.rt_properties.shaderGroupHandleSize
	handle_alignment := rt_ctx.rt_properties.shaderGroupHandleAlignment
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
		&rt_ctx.sbt.raygen_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)
	buffer_init(
		&rt_ctx.sbt.miss_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)
	buffer_init(
		&rt_ctx.sbt.hit_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)

	shader_handle_storage := make([]u8, sbt_size)

	_ = vk_check(
		vk.GetRayTracingShaderGroupHandlesKHR(
			device.logical_device.ptr,
			rt_ctx.pipeline.handle,
			0,
			group_count,
			int(sbt_size),
			raw_data(shader_handle_storage),
		),
		"Failed to get shader handles",
	)

	data: rawptr
	data, _ = buffer_map(&rt_ctx.sbt.raygen_buffer, device)
	runtime.mem_copy(data, raw_data(shader_handle_storage), int(handle_size))

	data, _ = buffer_map(&rt_ctx.sbt.miss_buffer, device)
	runtime.mem_copy(
		data,
		rawptr(uintptr(raw_data(shader_handle_storage)) + uintptr(handle_size_aligned)),
		int(handle_size),
	)

	data, _ = buffer_map(&rt_ctx.sbt.hit_buffer, device)
	runtime.mem_copy(
		data,
		rawptr(uintptr(raw_data(shader_handle_storage)) + uintptr(handle_size_aligned * 2)),
		int(handle_size),
	)

	buffer_unmap(&rt_ctx.sbt.raygen_buffer, device)
	buffer_unmap(&rt_ctx.sbt.miss_buffer, device)
	buffer_unmap(&rt_ctx.sbt.hit_buffer, device)
}
