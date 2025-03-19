package raytracer

import "core:fmt"
import "core:log"
import glm "core:math/linalg"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Render_Error :: union {
	Pipeline_Error,
	Shader_Error,
	Swapchain_Error,
}

Renderer :: struct {
	ctx:                          Vulkan_Context,
	window:                       ^Window,
	// TODO: remove the scene

	// GPU representation of the scene for now
	raytracing_pass:              Raytracing_Pass,
	scene_raytracing:             Raytracing_Builder,
	gpu_scene:                    ^GPU_Scene,

	// Camera stuff
	camera_descriptor_set_layout: vk.DescriptorSetLayout,
	camera_descriptor_set:        vk.DescriptorSet,
	camera_ubo:                   Buffer,

	// vulkan stuff
	current_cmd:                  Command_Buffer,
	current_image:                u32,

	// ray tracing properties
	ui_ctx:                       UI_Context,

	// time
	accumulation_frame:           u32,
}

renderer_init :: proc(renderer: ^Renderer, window: ^Window, allocator := context.allocator) {
	renderer.window = window
	vulkan_context_init(&renderer.ctx, window, allocator)

	renderer.gpu_scene = new(GPU_Scene)
	gpu_scene_init(renderer.gpu_scene, &renderer.ctx)

	{ 	// Initialize camera stuff
		device := renderer.ctx.device
		camera_ubo := &renderer.camera_ubo
		camera_descriptor_set_layout := &renderer.camera_descriptor_set_layout
		camera_descriptor_set := &renderer.camera_descriptor_set

		buffer_init(camera_ubo, &renderer.ctx, size_of(Camera_UBO), {.UNIFORM_BUFFER}, .Gpu_To_Cpu)
		buffer_map(camera_ubo)
		camera_descriptor_set_layout^, _ = create_descriptor_set_layout(
			[]vk.DescriptorSetLayoutBinding {
				{
					binding = 0,
					descriptorType = .UNIFORM_BUFFER,
					descriptorCount = 1,
					stageFlags = {.VERTEX, .FRAGMENT, .RAYGEN_KHR},
				},
			},
			device.logical_device.ptr,
		)


		camera_descriptor_set^, _ = allocate_single_descriptor_set(
			renderer.ctx.descriptor_pool,
			camera_descriptor_set_layout,
			device.logical_device.ptr,
		)

		buffer_info := vk.DescriptorBufferInfo {
			buffer = camera_ubo.handle,
			offset = 0,
			range  = size_of(Camera_UBO),
		}

		write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = camera_descriptor_set^,
			dstBinding      = 0,
			dstArrayElement = 0,
			descriptorType  = .UNIFORM_BUFFER,
			descriptorCount = 1,
			pBufferInfo     = &buffer_info,
		}

		vk.UpdateDescriptorSets(device.logical_device.ptr, 1, &write, 0, nil)

	}

	{
		shaders: [3]Shader
		shader_init(
			&shaders[0],
			renderer.ctx.device,
			"main",
			"main",
			"shaders/rgen.spv",
			{.RAYGEN_KHR},
		)
		shader_init(
			&shaders[1],
			renderer.ctx.device,
			"main",
			"main",
			"shaders/rmiss.spv",
			{.MISS_KHR},
		)
		shader_init(
			&shaders[2],
			renderer.ctx.device,
			"main",
			"main",
			"shaders/rchit.spv",
			{.CLOSEST_HIT_KHR},
		)

		defer for &s in shaders {
			shader_destroy(&s)
		}
		raytracing_pass_init(
			&renderer.raytracing_pass,
			&renderer.ctx,
			shaders[:],
			renderer.gpu_scene.descriptor_set_layout,
			renderer.camera_descriptor_set_layout,
		)
	}

	ui_context_init(
		&renderer.ui_ctx,
		renderer.ctx.device,
		renderer.window^,
		renderer.ctx.swapchain_manager.format,
	)
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)
	ui_context_destroy(&renderer.ui_ctx, renderer.ctx.device)

	buffer_destroy(&renderer.camera_ubo)
	vk.DestroyDescriptorSetLayout(
		vulkan_get_device_handle(&renderer.ctx),
		renderer.camera_descriptor_set_layout,
		nil,
	)

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
		free(renderer.gpu_scene)
	}

	raytracing_pass_destroy(&renderer.raytracing_pass)

	ctx_destroy(&renderer.ctx)
}

renderer_begin_frame :: proc(renderer: ^Renderer) {
	if renderer.window.framebuffer_resized {
		renderer.window.framebuffer_resized = false
		renderer_handle_resizing(renderer)
	}

	renderer.current_image, _ = ctx_begin_frame(&renderer.ctx)
	renderer.current_cmd = ctx_request_command_buffer(&renderer.ctx)
}

renderer_render_ui :: proc(renderer: ^Renderer, scene: ^Scene) {
	ui_render(renderer, scene)
}

renderer_end_frame :: proc(renderer: ^Renderer) {
	_ = vk_check(vk.EndCommandBuffer(renderer.current_cmd.buffer), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, renderer.current_cmd.buffer, renderer.current_image)
	renderer.current_cmd = {}
}

renderer_render :: proc(renderer: ^Renderer, scene: ^Scene, camera: ^Camera) {
	if renderer.window.framebuffer_resized {
		renderer.window.framebuffer_resized = false
		renderer_handle_resizing(renderer)
	}

	if scene.dirty != {} {
		update_scene(renderer, scene)
		renderer.accumulation_frame = 0
	}

	if camera.dirty {
		ubo_data := Camera_UBO {
			projection         = camera.proj,
			view               = camera.view,
			inverse_view       = camera.inverse_view,
			inverse_projection = camera.inverse_proj,
		}

		data := &ubo_data
		buffer := &renderer.camera_ubo
		buffer_write(buffer, data)
		buffer_flush(buffer)

		camera.dirty = false
		renderer.accumulation_frame = 0
	}

	raytracing_pass_render(
		&renderer.raytracing_pass,
		&renderer.current_cmd,
		renderer.gpu_scene.descriptor_set,
		renderer.camera_descriptor_set,
		renderer.accumulation_frame,
		renderer.current_image,
	)

	renderer.accumulation_frame += 1
}

@(private = "file")
renderer_handle_resizing :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> Swapchain_Error {
	extent := window_get_extent(renderer.window^)
	ctx_handle_resize(&renderer.ctx, extent.width, extent.height, allocator) or_return

	renderer.accumulation_frame = 0
	return nil
}

@(private)
@(require_results)
vk_check :: proc(result: vk.Result, message: string) -> vk.Result {
	if result != .SUCCESS {
		log.errorf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		return result
	}
	return nil
}

renderer_create_top_level_as :: proc(renderer: ^Renderer, scene: Scene) {
	tlas := make(
		[dynamic]vk.AccelerationStructureInstanceKHR,
		0,
		len(scene.objects),
		context.temp_allocator,
	)

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

		append(&tlas, ray_inst)
	}

	renderer_build_tlas(renderer, tlas[:])
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
		size_of(vk.AccelerationStructureInstanceKHR),
		int(count_instance),
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	)
	defer buffer_destroy(&instances_buffer)
	scratch_buffer: Buffer
	defer buffer_destroy(&scratch_buffer)
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
			update,
			false,
			&renderer.ctx,
		)
	}
}

@(private = "file")
update_scene :: proc(renderer: ^Renderer, scene: ^Scene) {
	if scene_check_dirty_flags_and_clear(scene, {.Updated_Material, .Deleted_Material}) {
		log.debug("Updating material")
		gpu_scene_update_materials_buffer(renderer.gpu_scene, scene)
	}

	if scene_check_dirty_flags_and_clear(scene, {.Added_Material}) {
		log.debug("Added new material")

		gpu_scene_recreate_materials_buffer(renderer.gpu_scene, scene^)
	}

	if scene_check_dirty_flags_and_clear(scene, {.Updated_Object}) {
		log.debug("Updating object")
		gpu_scene_update_objects_buffer(renderer.gpu_scene, scene)
	}

	if scene_check_dirty_flags_and_clear(scene, {.Acceleration_Structure}) {
		log.debug("Recreating scene acceleration structure")
		// TODO: handle the destruction of the old scene by now
		scene_compile(renderer.gpu_scene, scene^)

		renderer_create_bottom_level_as(renderer)
		renderer_create_top_level_as(renderer, scene^)

		as_write_info := vk.WriteDescriptorSetAccelerationStructureKHR {
			sType                      = .WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
			accelerationStructureCount = 1,
			pAccelerationStructures    = &renderer.scene_raytracing.tlas.handle,
		}
		write_info := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			pNext           = &as_write_info,
			descriptorType  = .ACCELERATION_STRUCTURE_KHR,
			dstSet          = renderer.gpu_scene.descriptor_set,
			descriptorCount = 1,
		}
		vk.UpdateDescriptorSets(vulkan_get_device_handle(&renderer.ctx), 1, &write_info, 0, nil)
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
		max_scratch_size,
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
