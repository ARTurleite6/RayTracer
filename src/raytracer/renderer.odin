package raytracer

import "core:fmt"
import "core:log"
import glm "core:math/linalg"
import "core:os"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Render_Error :: union {
	Pipeline_Error,
	Shader_Error,
	Swapchain_Error,
}

Descriptor_Set_Type :: enum {
	Global,
	Per_Frame, // This is actually not needed as I am only having a frame but ok
	Per_Pass,
}

Renderer :: struct {
	ctx:                    Vulkan_Context,
	window:                 ^Window,

	// GPU representation of the scene for now
	scene:                  ^Scene,
	raytracing_pass:        Raytracing_Pass,
	scene_raytracing:       Raytracing_Builder,
	gpu_scene:              ^GPU_Scene,
	descriptor_set_layouts: [Descriptor_Set_Type]Descriptor_Set_Layout,
	camera_ubo:             Uniform_Buffer_Set,
	output_images:          Image_Set,

	// frame data
	per_frame_data:         Frame_Data,

	// vulkan stuff
	current_cmd:            Command_Buffer,
	current_image:          u32,

	// ray tracing properties
	ui_ctx:                 UI_Context,

	// time
	accumulation_frame:     u32,
}

Frame_Data :: struct {
	// raytracing image
	per_pass_descriptor_set:    vk.DescriptorSet,

	// gbuffer restir
	position_gbuffer:           Image,
	normal_gbuffer:             Image,
	albedo_gbuffer:             Image,
	roughness_metallic_gbuffer: Image,
}

renderer_init :: proc(renderer: ^Renderer, window: ^Window, allocator := context.allocator) {
	renderer.window = window
	vulkan_context_init(&renderer.ctx, window, allocator)

	init_descriptor_set_layouts(renderer)

	renderer.gpu_scene = new(GPU_Scene)
	gpu_scene_init(renderer.gpu_scene, &renderer.descriptor_set_layouts[.Global], &renderer.ctx)

	{
		program := make_program(
			&renderer.ctx,
			{"shaders/rgen.spv", "shaders/rmiss.spv", "shaders/shadow.spv", "shaders/rchit.spv"},
			allocator,
		)

		raytracing_pass_init(
			&renderer.raytracing_pass,
			&renderer.ctx,
			program.shaders[:],
			{
				renderer.descriptor_set_layouts[.Global].handle,
				renderer.descriptor_set_layouts[.Per_Frame].handle,
				renderer.descriptor_set_layouts[.Per_Pass].handle,
			},
		)
	}

	ui_context_init(&renderer.ui_ctx, renderer.ctx.device, renderer.window^)

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
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)
	ui_context_destroy(&renderer.ui_ctx, renderer.ctx.device)

	for &layout in renderer.descriptor_set_layouts {
		descriptor_set_layout_destroy(&layout)
	}

	if renderer.gpu_scene != nil {
		gpu_scene_destroy(renderer.gpu_scene)

		device := vulkan_get_device_handle(&renderer.ctx)
		for &as in renderer.scene_raytracing.as {
			buffer_destroy(&as.buffer)
			vk.DestroyAccelerationStructureKHR(device, as.handle, nil)
		}

		buffer_destroy(&renderer.scene_raytracing.tlas.buffer)
		vk.DestroyAccelerationStructureKHR(device, renderer.scene_raytracing.tlas.handle, nil)

		delete(renderer.scene_raytracing.as)
		delete(renderer.scene_raytracing.tlas_infos)
		free(renderer.gpu_scene)
	}

	raytracing_pass_destroy(&renderer.raytracing_pass)

	uniform_buffer_set_destroy(&renderer.ctx, &renderer.camera_ubo)
	image_set_destroy(&renderer.ctx, &renderer.output_images)

	ctx_destroy(&renderer.ctx)

	renderer^ = {}
}

renderer_set_scene :: proc(renderer: ^Renderer, scene: ^Scene) {
	renderer.scene = scene
	renderer_rebuild_scene(renderer)
}

renderer_rebuild_scene :: proc(renderer: ^Renderer) {
	scene := renderer.scene
	scene_compile(renderer.gpu_scene, scene^)

	renderer_create_bottom_level_as(renderer)
	renderer_create_top_level_as(renderer, scene^)

	descriptor_set_update(
		renderer.gpu_scene.descriptor_set,
		&renderer.ctx,
		renderer.gpu_scene.descriptor_set_layout^,
		{
			binding = 0,
			write_info = vk.WriteDescriptorSetAccelerationStructureKHR {
				sType = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
				accelerationStructureCount = 1,
				pAccelerationStructures = &renderer.scene_raytracing.tlas.handle,
			},
		},
	)

	renderer.accumulation_frame = 0
}

renderer_update :: proc(renderer: ^Renderer) {
}

renderer_begin_frame :: proc(renderer: ^Renderer) {
	renderer.current_image, _ = ctx_begin_frame(&renderer.ctx)
	renderer.current_cmd = ctx_request_command_buffer(&renderer.ctx)
}

renderer_render_ui :: proc(renderer: ^Renderer) {
	ui_render(renderer)
}

renderer_end_frame :: proc(renderer: ^Renderer) {
	_ = vk_check(vk.EndCommandBuffer(renderer.current_cmd.buffer), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, renderer.current_cmd.buffer, renderer.current_image)
	renderer.current_cmd = {}
}

renderer_render :: proc(renderer: ^Renderer, camera: ^Camera) {
	ubo_data := Camera_UBO {
		projection         = camera.proj,
		view               = camera.view,
		inverse_view       = camera.inverse_view,
		inverse_projection = camera.inverse_proj,
	}

	ubo_buffer := uniform_buffer_set_get(&renderer.camera_ubo, renderer.ctx.current_frame)
	buffer_map(ubo_buffer)
	buffer_write(ubo_buffer, &ubo_data)

	if camera.dirty {
		camera.dirty = false
		renderer.accumulation_frame = 0
	}

	if renderer.scene != nil {
		scene_bake_storage_buffers(renderer.gpu_scene, renderer.scene^, renderer.current_cmd)
	}

	output_image := image_set_get(&renderer.output_images, renderer.ctx.current_frame)

	output_image_view := image_set_get_view(renderer.output_images, renderer.ctx.current_frame)
	renderer.per_frame_data.per_pass_descriptor_set = vulkan_get_descriptor_set(
		&renderer.ctx,
		&renderer.descriptor_set_layouts[.Per_Pass],
		{
			binding = 0,
			write_info = vk.DescriptorImageInfo {
				imageView = output_image_view,
				imageLayout = .GENERAL,
			},
		},
	)
	raytracing_pass_execute(
		&renderer.raytracing_pass,
		&renderer.current_cmd,
		{
			renderer.gpu_scene.descriptor_set,
			vulkan_get_descriptor_set(
				&renderer.ctx,
				&renderer.descriptor_set_layouts[.Per_Frame],
				{binding = 0, write_info = buffer_descriptor_info(ubo_buffer^)},
			),
			renderer.per_frame_data.per_pass_descriptor_set,
		},
		output_image^,
		renderer.accumulation_frame,
		renderer.current_image,
	)

	renderer.accumulation_frame += 1
}

renderer_on_resize :: proc(
	renderer: ^Renderer,
	width, height: u32,
	allocator := context.allocator,
) -> Swapchain_Error {
	ctx_handle_resize(&renderer.ctx, width, height, allocator) or_return
	// raytracing_pass_resize_image(&renderer.raytracing_pass)

	renderer.accumulation_frame = 0
	return nil
}

@(private)
@(require_results)
vk_check :: proc(result: vk.Result, message: string) -> vk.Result {
	if result != .SUCCESS {
		log.errorf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		os.exit(1)
		// return result
	}
	return nil
}

renderer_create_top_level_as :: proc(renderer: ^Renderer, scene: Scene) {
	tlas := &renderer.scene_raytracing.tlas_infos
	tlas^ = make([dynamic]vk.AccelerationStructureInstanceKHR, 0, len(scene.objects))

	for obj, i in scene.objects {
		model_matrix := obj.transform.model_matrix
		ray_inst := vk.AccelerationStructureInstanceKHR {
			transform                              = matrix_to_transform_matrix_khr(model_matrix),
			instanceCustomIndex                    = u32(i),
			mask                                   = 0xFF,
			instanceShaderBindingTableRecordOffset = 0,
			flags                                  = .TRIANGLE_FACING_CULL_DISABLE,
			accelerationStructureReference         = u64(
				get_blas_device_address(
					renderer.scene_raytracing.as[obj.mesh_index],
					renderer.ctx.device.logical_device.ptr,
				),
			),
		}

		append(tlas, ray_inst)
	}

	renderer_build_tlas(renderer, tlas[:], flags = {.PREFER_FAST_TRACE, .ALLOW_UPDATE})
}

renderer_build_tlas :: proc(
	renderer: ^Renderer,
	instances: []vk.AccelerationStructureInstanceKHR,
	flags: vk.BuildAccelerationStructureFlagsKHR = {.PREFER_FAST_TRACE},
	update := false,
) {
	assert(
		renderer.scene_raytracing.tlas.handle == 0 || update,
		"Cannot build tlas twice, only update",
	)
	device := renderer.ctx.device

	count_instance := u32(len(instances))

	instances_buffer: Buffer
	buffer_init_with_staging_buffer(
		&instances_buffer,
		&renderer.ctx,
		raw_data(instances),
		u64(size_of(vk.AccelerationStructureInstanceKHR) * int(count_instance)),
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	)
	defer buffer_destroy(&instances_buffer)
	scratch_buffer: Buffer
	{
		cmd := device_begin_single_time_commands(device, device.command_pool)
		defer device_end_single_time_commands(device, device.command_pool, cmd)


		cmd_create_tlas(
			&renderer.scene_raytracing,
			cmd,
			count_instance,
			buffer_get_device_address(instances_buffer),
			&scratch_buffer,
			flags,
			update = update,
			motion = false,
			ctx = &renderer.ctx,
		)
	}
}

renderer_create_bottom_level_as :: proc(renderer: ^Renderer) {
	inputs := make(
		[dynamic]Bottom_Level_Input,
		0,
		len(renderer.gpu_scene.meshes_data),
		context.temp_allocator,
	)
	device := renderer.ctx.device

	for &mesh in renderer.gpu_scene.meshes_data {
		append(&inputs, mesh_to_geometry(&mesh, device^))
	}

	renderer_build_blas(renderer, inputs[:], {.PREFER_FAST_TRACE})
}

renderer_build_blas :: proc(
	renderer: ^Renderer,
	inputs: []Bottom_Level_Input,
	flags: vk.BuildAccelerationStructureFlagsKHR,
) {
	device := renderer.ctx.device
	build_infos := make([]Build_Acceleration_Structure, len(inputs), context.temp_allocator)

	n_blas := u32(len(inputs))
	total_size: vk.DeviceSize
	max_scratch_size: vk.DeviceSize
	number_compactions: u32
	for &input, i in inputs {
		info := &build_infos[i]

		info.build_info = {
			sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
			type          = .BOTTOM_LEVEL,
			mode          = .BUILD,
			flags         = flags,
			geometryCount = 1,
			pGeometries   = &input.geometry,
		}

		info.range_info = input.offset

		max_prim_counts := [?]u32{info.range_info.primitiveCount}
		info.size_info.sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR
		vk.GetAccelerationStructureBuildSizesKHR(
			device.logical_device.ptr,
			.DEVICE,
			&info.build_info,
			raw_data(max_prim_counts[:]),
			&info.size_info,
		)

		total_size += info.size_info.accelerationStructureSize
		max_scratch_size = max(info.size_info.buildScratchSize, max_scratch_size)
		number_compactions += 1 if .ALLOW_COMPACTION in info.build_info.flags else 0
	}

	scratch_buffer: Buffer
	buffer_init(
		&scratch_buffer,
		&renderer.ctx,
		u64(max_scratch_size),
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		.Gpu_Only,
		alignment = 128, // TODO: THIS NEEDS TO BE CHANGED IN THE FUTURE
	)
	defer buffer_destroy(&scratch_buffer)

	query_pool: vk.QueryPool
	if number_compactions > 0 {
		assert(number_compactions == n_blas)
		create_info := vk.QueryPoolCreateInfo {
			sType      = .QUERY_POOL_CREATE_INFO,
			queryCount = n_blas,
			queryType  = .ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR,
		}

		_ = vk_check(
			vk.CreateQueryPool(device.logical_device.ptr, &create_info, nil, &query_pool),
			"Failed to create query_pool",
		)
	}

	indices := make([dynamic]u32, context.temp_allocator)

	batch_size: vk.DeviceSize
	batch_limit: vk.DeviceSize = 256_000_000
	for i in 0 ..< n_blas {
		append(&indices, i)

		batch_size += build_infos[i].size_info.accelerationStructureSize

		if batch_size >= batch_limit || i == n_blas - 1 {
			{
				cmd := device_begin_single_time_commands(device, device.command_pool)
				defer device_end_single_time_commands(device, device.command_pool, cmd)

				cmd_create_blas(
					cmd,
					indices[:],
					build_infos,
					buffer_get_device_address(scratch_buffer),
					query_pool,
					&renderer.ctx,
				)
			}

			if query_pool != 0 {
				// cmd := device_begin_single_time_commands(device, device.command_pool)
				// defer device_end_single_time_commands(device, device.command_pool, cmd)

				// compact
			}

			batch_size = 0
			clear(&indices)
		}
	}

	renderer.scene_raytracing.as = make([dynamic]Acceleration_Structure, 0, len(build_infos))

	for b in build_infos {
		append(&renderer.scene_raytracing.as, b.as)
	}

}

init_descriptor_set_layouts :: proc(renderer: ^Renderer) {
	renderer.descriptor_set_layouts[.Global] = vulkan_get_descriptor_set_layout(
		&renderer.ctx,
		{
			binding = 0,
			descriptorCount = 1,
			descriptorType = .ACCELERATION_STRUCTURE_KHR,
			stageFlags = {.RAYGEN_KHR, .CLOSEST_HIT_KHR},
		},
		{
			binding = 1,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			stageFlags = {.CLOSEST_HIT_KHR},
		},
		{
			binding = 2,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			stageFlags = {.CLOSEST_HIT_KHR},
		},
		{
			binding = 3,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			stageFlags = {.CLOSEST_HIT_KHR},
		},
	)

	renderer.descriptor_set_layouts[.Per_Frame] = vulkan_get_descriptor_set_layout(
		&renderer.ctx,
		{
			binding = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.RAYGEN_KHR},
		},
	)

	renderer.descriptor_set_layouts[.Per_Pass] = vulkan_get_descriptor_set_layout(
		&renderer.ctx,
		{
			binding = 0,
			descriptorCount = 1,
			descriptorType = .STORAGE_IMAGE,
			stageFlags = {.RAYGEN_KHR},
		},
		{
			binding = 1,
			descriptorCount = 1,
			descriptorType = .STORAGE_IMAGE,
			stageFlags = {.RAYGEN_KHR},
		},
		{
			binding = 2,
			descriptorCount = 1,
			descriptorType = .STORAGE_IMAGE,
			stageFlags = {.RAYGEN_KHR},
		},
		{
			binding = 3,
			descriptorCount = 1,
			descriptorType = .STORAGE_IMAGE,
			stageFlags = {.RAYGEN_KHR},
		},
		{
			binding = 4,
			descriptorCount = 1,
			descriptorType = .STORAGE_IMAGE,
			stageFlags = {.RAYGEN_KHR},
		},
	)
}
