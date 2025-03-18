package raytracer

import "base:runtime"
import "core:log"
import "core:mem/tlsf"
import "core:strings"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: log

// Object_Data :: struct {
// 	vertex_buffer_address, index_buffer_address: vk.DeviceAddress,
// 	material_index:                              u32,
// }

Raytracing_Push_Constant :: struct {
	clear_color:        Vec3,
	accumulation_frame: u32,
}

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
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
}

Descriptor_Set_Resource_Type :: enum {
	Scene,
	Storage_Image,
}

Raytracing_Resources :: struct {
	//Scene Buffers
	objects_buffer, materials_buffer: Buffer,
	// TLAS
	rt_builder:                       Raytracing_Builder,

	// Storage image for ray tracing output
	storage_image:                    Image,
	storage_image_view:               vk.ImageView,

	// Descriptor sets layouts
	descriptor_sets_layouts:          [Descriptor_Set_Resource_Type]vk.DescriptorSetLayout,

	// Descriptor sets
	descriptor_sets:                  [Descriptor_Set_Resource_Type]vk.DescriptorSet,

	// for resource management
	device:                           ^Device,
}

Raytracing_Context :: struct {
	pipeline:      Pipeline,
	sbt:           Shader_Binding_Table,
	rt_properties: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	vk_ctx:        ^Vulkan_Context,
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
	layouts: []vk.DescriptorSetLayout,
	push_constants: []vk.PushConstantRange,
	shaders: []Shader,
) {
	rt_ctx.vk_ctx = vk_ctx
	device := rt_ctx.vk_ctx.device.logical_device.ptr

	rt_ctx.rt_properties.sType = .PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR
	props := vk.PhysicalDeviceProperties2 {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &rt_ctx.rt_properties,
	}
	vk.GetPhysicalDeviceProperties2(rt_ctx.vk_ctx.device.physical_device.ptr, &props)
	{
		create_info := vk.PipelineLayoutCreateInfo {
			sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount         = u32(len(layouts)),
			pSetLayouts            = raw_data(layouts),
			pushConstantRangeCount = u32(len(push_constants)),
			pPushConstantRanges    = raw_data(push_constants),
		}
		vk.CreatePipelineLayout(
			rt_ctx.vk_ctx.device.logical_device.ptr,
			&create_info,
			nil,
			&rt_ctx.pipeline.layout,
		)
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
			&rt_ctx.pipeline.pipeline,
		),
		"Failed to create raytracing pipeline",
	)

	rt_create_shader_binding_table(rt_ctx, rt_ctx.vk_ctx.device)
}

rt_destroy :: proc(rt_ctx: ^Raytracing_Context) {
	buffer_destroy(&rt_ctx.sbt.raygen_buffer, rt_ctx.vk_ctx.device)
	buffer_destroy(&rt_ctx.sbt.miss_buffer, rt_ctx.vk_ctx.device)
	buffer_destroy(&rt_ctx.sbt.hit_buffer, rt_ctx.vk_ctx.device)

	vk.DestroyPipelineLayout(rt_ctx.vk_ctx.device.logical_device.ptr, rt_ctx.pipeline.layout, nil)
	vk.DestroyPipeline(rt_ctx.vk_ctx.device.logical_device.ptr, rt_ctx.pipeline.pipeline, nil)
}

rt_resources_init :: proc(
	resources: ^Raytracing_Resources,
	ctx: ^Vulkan_Context,
	scene: Scene,
	descriptor_pool: vk.DescriptorPool,
	extent: vk.Extent2D,
) {
	device := ctx.device.logical_device.ptr
	resources.device = ctx.device
	resources.descriptor_sets_layouts[.Scene], _ = create_descriptor_set_layout(
		[]vk.DescriptorSetLayoutBinding {
			{
				binding = 0,
				descriptorType = .ACCELERATION_STRUCTURE_KHR,
				descriptorCount = 1,
				stageFlags = {.RAYGEN_KHR},
			},
			{
				binding = 1,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.CLOSEST_HIT_KHR},
			},
			{
				binding = 2,
				descriptorType = .STORAGE_BUFFER,
				descriptorCount = 1,
				stageFlags = {.CLOSEST_HIT_KHR},
			},
		},
		device,
	)


	resources.descriptor_sets_layouts[.Storage_Image], _ = create_descriptor_set_layout(
		[]vk.DescriptorSetLayoutBinding {
			{
				binding = 0,
				descriptorType = .STORAGE_IMAGE,
				descriptorCount = 1,
				stageFlags = {.RAYGEN_KHR},
			},
		},
		device,
	)

	image_init(&resources.storage_image, ctx, .R32G32B32A32_SFLOAT, extent)
	image_view_init(&resources.storage_image_view, resources.storage_image, ctx)

	{
		cmd := device_begin_single_time_commands(ctx.device, ctx.device.command_pool)
		defer device_end_single_time_commands(ctx.device, ctx.device.command_pool, cmd)
		image_transition_layout_stage_access(
			cmd,
			resources.storage_image.handle,
			.UNDEFINED,
			.GENERAL,
			{.ALL_COMMANDS},
			{.ALL_COMMANDS},
			{},
			{},
		)
	}

	when false {
		create_bottom_level_as(&resources.rt_builder, scene, resources.device)
		create_top_level_as(&resources.rt_builder, scene, resources.device)
		raytracing_create_scene_buffers(resources, scene)
	}

	for &d, i in resources.descriptor_sets {
		d, _ = allocate_single_descriptor_set(
			descriptor_pool,
			&resources.descriptor_sets_layouts[i],
			device,
		)
	}


	update_descriptor_sets(resources)
}

rt_resources_destroy :: proc(rt_resources: ^Raytracing_Resources, vk_ctx: Vulkan_Context) {
	buffer_destroy(&rt_resources.rt_builder.tlas.buffer, rt_resources.device)
	vk.DestroyAccelerationStructureKHR(
		rt_resources.device.logical_device.ptr,
		rt_resources.rt_builder.tlas.handle,
		nil,
	)

	for &as in rt_resources.rt_builder.as {
		buffer_destroy(&as.buffer, rt_resources.device)
		vk.DestroyAccelerationStructureKHR(rt_resources.device.logical_device.ptr, as.handle, nil)
	}
	delete(rt_resources.rt_builder.as)

	buffer_destroy(&rt_resources.objects_buffer, rt_resources.device)
	buffer_destroy(&rt_resources.materials_buffer, rt_resources.device)
	image_destroy(&rt_resources.storage_image, vk_ctx)
	image_view_destroy(rt_resources.storage_image_view, vk_ctx)

	for d in rt_resources.descriptor_sets_layouts {
		descriptor_set_layout_destroy(d, rt_resources.device.logical_device.ptr)
	}

	rt_resources^ = {}
}

rt_handle_resize :: proc(
	rt_resources: ^Raytracing_Resources,
	vk_ctx: ^Vulkan_Context,
	new_extent: vk.Extent2D,
) {
	image_destroy(&rt_resources.storage_image, vk_ctx^)
	image_view_destroy(rt_resources.storage_image_view, vk_ctx^)

	image_init(&rt_resources.storage_image, vk_ctx, .R32G32B32A32_SFLOAT, new_extent)
	image_view_init(&rt_resources.storage_image_view, rt_resources.storage_image, vk_ctx)

	{
		cmd := device_begin_single_time_commands(vk_ctx.device, vk_ctx.device.command_pool)
		defer device_end_single_time_commands(vk_ctx.device, vk_ctx.device.command_pool, cmd)
		image_transition_layout_stage_access(
			cmd,
			rt_resources.storage_image.handle,
			.UNDEFINED,
			.GENERAL,
			{.ALL_COMMANDS},
			{.ALL_COMMANDS},
			{},
			{},
		)
	}


	update_storage_image_descriptor(rt_resources)
}

update_descriptor_sets :: proc(rt_resources: ^Raytracing_Resources) {
	update_scene_descriptor(rt_resources)
	update_storage_image_descriptor(rt_resources)
}

update_scene_descriptor :: proc(rt_resources: ^Raytracing_Resources) {
	update_tlas_descriptor(rt_resources)
	update_objects_buffer(rt_resources)
	update_materials_buffer(rt_resources)
}

update_objects_buffer :: proc(rt_resources: ^Raytracing_Resources) {
	device := rt_resources.device.logical_device.ptr

	write_info := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = rt_resources.descriptor_sets[.Scene],
		dstBinding      = 1,
		descriptorType  = .STORAGE_BUFFER,
		descriptorCount = 1,
		pBufferInfo     = &vk.DescriptorBufferInfo {
			buffer = rt_resources.objects_buffer.handle,
			offset = 0,
			range = vk.DeviceSize(vk.WHOLE_SIZE),
		},
	}
	vk.UpdateDescriptorSets(device, 1, &write_info, 0, nil)
}

update_materials_buffer :: proc(rt_resources: ^Raytracing_Resources) {
	device := rt_resources.device.logical_device.ptr

	write_info := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = rt_resources.descriptor_sets[.Scene],
		dstBinding      = 2,
		descriptorType  = .STORAGE_BUFFER,
		descriptorCount = 1,
		pBufferInfo     = &vk.DescriptorBufferInfo {
			buffer = rt_resources.materials_buffer.handle,
			offset = 0,
			range = vk.DeviceSize(vk.WHOLE_SIZE),
		},
	}
	vk.UpdateDescriptorSets(device, 1, &write_info, 0, nil)
}

update_tlas_descriptor :: proc(rt_resources: ^Raytracing_Resources) {
	device := rt_resources.device.logical_device.ptr

	// Create write descriptor for TLAS
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = rt_resources.descriptor_sets[.Scene],
		dstBinding      = 0, // Assuming binding 0 is for TLAS
		descriptorType  = .ACCELERATION_STRUCTURE_KHR,
		descriptorCount = 1,
	}

	// Special handling for acceleration structure
	as_info := vk.WriteDescriptorSetAccelerationStructureKHR {
		sType                      = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
		accelerationStructureCount = 1,
		pAccelerationStructures    = &rt_resources.rt_builder.tlas.handle,
	}

	// Connect the acceleration structure info to the write descriptor
	write.pNext = &as_info

	// Update the descriptor set
	vk.UpdateDescriptorSets(device, 1, &write, 0, nil)
}

update_storage_image_descriptor :: proc(rt_resources: ^Raytracing_Resources) {
	device := rt_resources.device.logical_device.ptr

	// Create image info for the storage image
	image_info := vk.DescriptorImageInfo {
		imageView   = rt_resources.storage_image_view,
		imageLayout = .GENERAL,
		// No sampler needed for storage image
	}

	// Create write descriptor for storage image
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = rt_resources.descriptor_sets[.Storage_Image],
		dstBinding      = 0, // Assuming binding 0 is for storage image
		descriptorType  = .STORAGE_IMAGE,
		descriptorCount = 1,
		pImageInfo      = &image_info,
	}

	// Update the descriptor set
	vk.UpdateDescriptorSets(device, 1, &write, 0, nil)
}

raytracing_render :: proc(
	rt_ctx: Raytracing_Context,
	cmd: ^Command_Buffer,
	image_index: u32,
	camera: ^Camera,
	rt_resources: ^Raytracing_Resources,
	accumulation_frame: u32,
) {
	descriptor_sets := [?]vk.DescriptorSet {
		camera.descriptor_sets,
		rt_resources.descriptor_sets[.Scene],
		rt_resources.descriptor_sets[.Storage_Image],
	}

	vk.CmdBindDescriptorSets(
		cmd.buffer,
		.RAY_TRACING_KHR,
		rt_ctx.pipeline.layout,
		0,
		u32(len(descriptor_sets)),
		raw_data(descriptor_sets[:]),
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
			accumulation_frame = accumulation_frame,
		},
	)

	vk.CmdBindPipeline(cmd.buffer, .RAY_TRACING_KHR, rt_ctx.pipeline.pipeline)

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

	extent := rt_ctx.vk_ctx.swapchain_manager.extent
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

	storage_image := rt_resources.storage_image.handle
	swapchain_image := rt_ctx.vk_ctx.swapchain_manager.images[image_index]
	ctx_transition_swapchain_image(
		rt_ctx.vk_ctx^,
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
		rt_ctx.vk_ctx^,
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

	shader_handle_storage := make([]u8, sbt_size, context.temp_allocator)

	_ = vk_check(
		vk.GetRayTracingShaderGroupHandlesKHR(
			device.logical_device.ptr,
			rt_ctx.pipeline.pipeline,
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
