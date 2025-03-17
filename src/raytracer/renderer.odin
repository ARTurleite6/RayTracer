package raytracer

import "core:container/queue"
import "core:fmt"
import "core:log"
import glm "core:math/linalg"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Render_Error :: union {
	Pipeline_Error,
	Shader_Error,
	Swapchain_Error,
}

Renderer :: struct {
	ctx:                Vulkan_Context,
	window:             ^Window,
	// TODO: remove the scene
	scene:              ^Scene,

	// GPU representation of the scene for now
	scene_raytracing:   Raytracing_Builder,
	gpu_scene:          ^GPU_Scene,
	camera:             Camera,
	// TODO: probably move this in the future
	shaders:            [dynamic]Shader,
	events:             queue.Queue(Event),

	// vulkan stuff
	current_cmd:        Command_Buffer,
	current_image:      u32,

	// ray tracing properties
	ui_ctx:             UI_Context,
	rt_resources:       Raytracing_Resources,
	rt_ctx:             Raytracing_Context,

	// time
	last_frame_time:    f64,
	delta_time:         f32,
	accumulation_frame: u32,
}

renderer_init :: proc(renderer: ^Renderer, window: ^Window, allocator := context.allocator) {
	renderer.window = window
	vulkan_context_init(&renderer.ctx, window, allocator)

	ui_context_init(
		&renderer.ui_ctx,
		renderer.ctx.device,
		renderer.window^,
		renderer.ctx.swapchain_manager.format,
	)

	when false {
		// renderer.scene = create_scene(renderer.ctx.device)
		rt_resources_init(
			&renderer.rt_resources,
			&renderer.ctx,
			renderer.scene,
			renderer.ctx.descriptor_pool,
			renderer.ctx.swapchain_manager.extent,
		)

		camera_init(
			&renderer.camera,
			{0, 0, -3},
			window_aspect_ratio(window^),
			renderer.ctx.device,
			renderer.ctx.descriptor_pool,
		)

		{
			shader: [3]Shader
			shader_init(
				&shader[0],
				renderer.ctx.device,
				"main",
				"main",
				"shaders/rgen.spv",
				{.RAYGEN_KHR},
			)
			shader_init(
				&shader[1],
				renderer.ctx.device,
				"main",
				"main",
				"shaders/rmiss.spv",
				{.MISS_KHR},
			)
			shader_init(
				&shader[2],
				renderer.ctx.device,
				"main",
				"main",
				"shaders/rchit.spv",
				{.CLOSEST_HIT_KHR},
			)

			defer for &s in shader {
				shader_destroy(&s)
			}

			rt_init(
				&renderer.rt_ctx,
				&renderer.ctx,
				{
					renderer.camera.descriptor_set_layout,
					renderer.rt_resources.descriptor_sets_layouts[.Scene],
					renderer.rt_resources.descriptor_sets_layouts[.Storage_Image],
				},
				{
					vk.PushConstantRange {
						stageFlags = {.RAYGEN_KHR},
						offset = 0,
						size = size_of(Raytracing_Push_Constant),
					},
				},
				shader[:],
			)
		}
	}
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)

	// scene_destroy(&renderer.scene, renderer.ctx.device)

	// for &shader in renderer.shaders {
	// 	shader_destroy(&shader)
	// }

	// delete(renderer.shaders)
	ui_context_destroy(&renderer.ui_ctx, renderer.ctx.device)
	// rt_destroy(&renderer.rt_ctx)
	// rt_resources_destroy(&renderer.rt_resources, renderer.ctx)
	// window_destroy(renderer.window^)

	if renderer.gpu_scene != nil {
		gpu_scene_destroy(renderer.gpu_scene)
		free(renderer.gpu_scene)
	}

	// camera_destroy(&renderer.camera)
	ctx_destroy(&renderer.ctx)

	// queue.destroy(&renderer.events)
}

renderer_set_scene :: proc(renderer: ^Renderer, scene: ^Scene) {
	// TODO: change this part
	renderer.scene = scene
	renderer.gpu_scene = new(GPU_Scene)
	renderer.gpu_scene^ = scene_compile(scene^, &renderer.ctx)

	renderer_create_bottom_level_as(renderer)
	renderer_create_top_level_as(renderer)
}

renderer_run :: proc(renderer: ^Renderer) {
	for !window_should_close(renderer.window^) {
		free_all(context.temp_allocator)
		renderer_update(renderer)
		renderer_render(renderer)
	}
}

renderer_update :: proc(renderer: ^Renderer) {
	current_time := glfw.GetTime()
	renderer.delta_time = f32(current_time - renderer.last_frame_time)
	renderer.last_frame_time = current_time
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
}

renderer_render :: proc(renderer: ^Renderer) {
	if renderer.window.framebuffer_resized {
		renderer.window.framebuffer_resized = false
		renderer_handle_resizing(renderer)
	}

	camera_update_buffers(&renderer.camera)

	image_index, err := ctx_begin_frame(&renderer.ctx)

	cmd := ctx_request_command_buffer(&renderer.ctx)
	if err != nil do return

	raytracing_render(
		renderer.rt_ctx,
		&cmd,
		image_index,
		&renderer.camera,
		&renderer.rt_resources,
		renderer.accumulation_frame,
	)
	// ui_render(renderer.ctx, &cmd, renderer)

	_ = vk_check(vk.EndCommandBuffer(cmd.buffer), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, cmd.buffer, image_index)

	renderer.accumulation_frame += 1
}

@(private = "file")
renderer_handle_resizing :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> Swapchain_Error {
	extent := window_get_extent(renderer.window^)
	camera_update_aspect_ratio(&renderer.camera, window_aspect_ratio(renderer.window^))
	ctx_handle_resize(&renderer.ctx, extent.width, extent.height, allocator) or_return

	// rt_handle_resize(&renderer.rt_resources, &renderer.ctx, extent)

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

renderer_create_top_level_as :: proc(renderer: ^Renderer) {
	tlas := make(
		[dynamic]vk.AccelerationStructureInstanceKHR,
		0,
		len(renderer.gpu_scene.objects_data),
		context.temp_allocator,
	)

	for obj, i in renderer.gpu_scene.objects_data {
		model_matrix := renderer.scene.objects[i].transform.model_matrix
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
	assert(renderer.scene_raytracing.tlas.handle == 0 || update, "Cannot build tlas twice, only update")
	device := renderer.ctx.device

	count_instance := u32(len(instances))

	instances_buffer: Buffer
	buffer_init_with_staging_buffer(
		&instances_buffer,
		device,
		raw_data(instances),
		size_of(vk.AccelerationStructureInstanceKHR),
		int(count_instance),
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	)
	defer buffer_destroy(&instances_buffer, device)
	scratch_buffer: Buffer
	defer buffer_destroy(&scratch_buffer, device)
	{
		cmd := device_begin_single_time_commands(device, device.command_pool)
		defer device_end_single_time_commands(device, device.command_pool, cmd)


		cmd_create_tlas(
			&renderer.scene_raytracing,
			cmd,
			count_instance,
			buffer_get_device_address(instances_buffer, device^),
			&scratch_buffer,
			flags,
			update,
			false,
			device,
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
		device,
		max_scratch_size,
		1,
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		.Gpu_Only,
		alignment = 128, // TODO: THIS NEEDS TO BE CHANGED IN THE FUTURE
	)
	defer buffer_destroy(&scratch_buffer, device)

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
					buffer_get_device_address(scratch_buffer, device^),
					query_pool,
					device,
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
