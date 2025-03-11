package raytracer

import "base:runtime"
import "core:fmt"
import glm "core:math/linalg"
import "core:mem/tlsf"
import "core:strings"
import vma "external:odin-vma"
import vk "vendor:vulkan"

align_up :: proc(x, align: u32) -> u32 {
	return u32(tlsf.align_up(uint(x), uint(align)))
}

Raytracing_Stage :: struct {
	using base:    Render_Stage,
	shaders:       []vk.PipelineShaderStageCreateInfo,
	pipeline:      Pipeline,
	rt_properties: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	sbt:           Shader_Binding_Table,
}

Shader_Binding_Table :: struct {
	raygen_buffer, miss_buffer, hit_buffer: Buffer,
}


Stage_Indices :: enum {
	Raygen = 0,
	Miss,
	Closest_Hit,
}

raytracing_init :: proc(
	stage: ^Raytracing_Stage,
	name: string,
	shaders: []Shader,
	rt_properties: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
) {
	render_stage_init(stage, name, stage)

	stage.shaders = make([]vk.PipelineShaderStageCreateInfo, len(shaders))
	stage.rt_properties = rt_properties

	for shader, i in shaders {
		stage.shaders[i] = {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = shader.type,
			module = shader.module,
			pName  = strings.clone_to_cstring(shader.name),
		}
	}
}

raytracing_destroy :: proc(stage: ^Raytracing_Stage, device: ^Device) {
	for shader in stage.shaders {
		delete(shader.pName)
	}

	delete(stage.shaders)
	buffer_destroy(&stage.sbt.raygen_buffer, device)
	buffer_destroy(&stage.sbt.miss_buffer, device)
	buffer_destroy(&stage.sbt.hit_buffer, device)
}

raytracing_render :: proc(
	graph: Render_Graph,
	stage: ^Raytracing_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	cmd := Command_Buffer {
		buffer = cmd,
	}
	descs := [?]vk.DescriptorSet {
		descriptor_manager_get_descriptor_set_index(
			render_data.descriptor_manager^,
			"raytracing_main",
			render_data.frame_index,
		),
		descriptor_manager_get_descriptor_set_index(
			render_data.descriptor_manager^,
			"camera",
			render_data.frame_index,
		),
		descriptor_manager_get_descriptor_set_index(
			render_data.descriptor_manager^,
			"scene_data",
			render_data.frame_index,
		),
	}

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		stage.pipeline.layout,
		0,
		u32(len(descs)),
		raw_data(descs[:]),
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd.buffer,
		stage.pipeline.layout,
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

	vk.CmdBindPipeline(cmd.buffer, .RAY_TRACING_KHR, stage.pipeline.handle)

	handle_size_aligned := align_up(
		stage.rt_properties.shaderGroupHandleSize,
		stage.rt_properties.shaderGroupHandleAlignment,
	)

	raygen_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(stage.sbt.raygen_buffer, graph.ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}

	miss_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(stage.sbt.miss_buffer, graph.ctx.device^),
		stride        = vk.DeviceSize(handle_size_aligned),
		size          = vk.DeviceSize(handle_size_aligned),
	}

	hit_sbt_entry := vk.StridedDeviceAddressRegionKHR {
		deviceAddress = buffer_get_device_address(stage.sbt.hit_buffer, graph.ctx.device^),
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
		graph.ctx^,
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
		graph.ctx^,
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

create_rt_pipeline :: proc(stage: ^Raytracing_Stage, device: ^Device) {
	layout_create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(stage.descriptor_layouts)),
		pSetLayouts            = raw_data(stage.descriptor_layouts),
		pushConstantRangeCount = u32(len(stage.push_constants)),
		pPushConstantRanges    = raw_data(stage.push_constants),
	}

	_ = vk_check(
		vk.CreatePipelineLayout(
			device.logical_device.ptr,
			&layout_create_info,
			nil,
			&stage.pipeline.layout,
		),
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

	create_info := vk.RayTracingPipelineCreateInfoKHR {
		sType                        = .RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
		stageCount                   = u32(len(stage.shaders)),
		pStages                      = raw_data(stage.shaders),
		groupCount                   = u32(len(groups)),
		pGroups                      = raw_data(groups[:]),
		maxPipelineRayRecursionDepth = 1,
		layout                       = stage.pipeline.layout,
	}

	_ = vk_check(
		vk.CreateRayTracingPipelinesKHR(
			device.logical_device.ptr,
			0,
			0,
			1,
			&create_info,
			nil,
			&stage.pipeline.handle,
		),
		"Failed to create raytracing pipeline",
	)

	create_shader_binding_table(stage, device)

	fmt.println(stage.sbt)
}

create_shader_binding_table :: proc(stage: ^Raytracing_Stage, device: ^Device) {
	handle_size := stage.rt_properties.shaderGroupHandleSize
	handle_alignment := stage.rt_properties.shaderGroupHandleAlignment
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
		&stage.sbt.raygen_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)
	buffer_init(
		&stage.sbt.miss_buffer,
		device,
		vk.DeviceSize(handle_size),
		1,
		sbt_buffer_usage_flags,
		sbt_memory_usage,
	)
	buffer_init(
		&stage.sbt.hit_buffer,
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
			stage.pipeline.handle,
			0,
			group_count,
			int(sbt_size),
			raw_data(shader_handle_storage),
		),
		"Failed to get shader handles",
	)

	data: rawptr
	data, _ = buffer_map(&stage.sbt.raygen_buffer, device)
	runtime.mem_copy(data, raw_data(shader_handle_storage), int(handle_size))

	data, _ = buffer_map(&stage.sbt.miss_buffer, device)
	runtime.mem_copy(
		data,
		rawptr(uintptr(raw_data(shader_handle_storage)) + uintptr(handle_size_aligned)),
		int(handle_size),
	)

	data, _ = buffer_map(&stage.sbt.hit_buffer, device)
	runtime.mem_copy(
		data,
		rawptr(uintptr(raw_data(shader_handle_storage)) + uintptr(handle_size_aligned * 2)),
		int(handle_size),
	)

	buffer_unmap(&stage.sbt.raygen_buffer, device)
	buffer_unmap(&stage.sbt.miss_buffer, device)
	buffer_unmap(&stage.sbt.hit_buffer, device)
}
