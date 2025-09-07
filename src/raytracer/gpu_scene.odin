package raytracer

import "base:intrinsics"
import "core:log"
import vk "vendor:vulkan"
_ :: log

GPU_Scene :: struct {
	tlas:                                            Acceleration_Structure,
	tlas_infos:                                      [dynamic]vk.AccelerationStructureInstanceKHR,
	acceleration_structures:                         [dynamic]Acceleration_Structure,
	meshes_data:                                     []Mesh_GPU_Data,
	objects_buffer, lights_buffer, materials_buffer: Storage_Buffer_Set,
}

Material_Data :: struct {
	albedo:                                                 Vec3,
	emission_color:                                         Vec3,
	emission_power, roughness, metallic, transmission, ior: f32,
}

Object_GPU_Data :: struct {
	vertex_buffer_address: vk.DeviceAddress,
	index_buffer_address:  vk.DeviceAddress,
	material_index:        u32,
	mesh_index:            u32,
}

Light_GPU_Data :: struct {
	transform:     [16]f32,
	object_index:  u32,
	num_triangles: u32,
	instance_mask: u32,
}

// Change this in the future
Mesh_GPU_Data :: struct {
	vertex_buffer, index_buffer: Buffer,
	num_vertices, num_indices:   int,
}


gpu_scene_init :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	gpu_scene_bake(gpu_scene, ctx, scene)
}

gpu_scene_destroy :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context) {
	device := vulkan_get_device_handle(ctx)

	{ 	// Destroying Bottom Level Acceleration Structure
		for &acceleration_structure in gpu_scene.acceleration_structures {
			vk.DestroyAccelerationStructureKHR(device, acceleration_structure.handle, nil)
			buffer_destroy(&acceleration_structure.buffer)
		}
		delete(gpu_scene.acceleration_structures)
	}

	{ 	// Destroying Top Level Acceleration Structures
		vk.DestroyAccelerationStructureKHR(device, gpu_scene.tlas.handle, nil)
		buffer_destroy(&gpu_scene.tlas.buffer)
		delete(gpu_scene.tlas_infos)
	}

	for &mesh in gpu_scene.meshes_data {
		buffer_destroy(&mesh.vertex_buffer)
		buffer_destroy(&mesh.index_buffer)
	}
	delete(gpu_scene.meshes_data)

	storage_buffer_set_destroy(ctx, &gpu_scene.objects_buffer)
	storage_buffer_set_destroy(ctx, &gpu_scene.lights_buffer)
	storage_buffer_set_destroy(ctx, &gpu_scene.materials_buffer)
}

gpu_scene_bake :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	gpu_scene.meshes_data = make([]Mesh_GPU_Data, len(scene.meshes))

	for mesh, i in scene.meshes {
		vertex_buffer, index_buffer: Buffer
		buffer_init_with_staging_buffer(
			&vertex_buffer,
			ctx,
			raw_data(mesh.vertices),
			u64(size_of(Vertex) * len(mesh.vertices)),
			{
				.SHADER_DEVICE_ADDRESS,
				.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
				.VERTEX_BUFFER,
			},
		)

		buffer_init_with_staging_buffer(
			&index_buffer,
			ctx,
			raw_data(mesh.indices),
			u64(size_of(u32) * len(mesh.indices)),
			{
				.SHADER_DEVICE_ADDRESS,
				.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
				.INDEX_BUFFER,
			},
		)

		gpu_scene.meshes_data[i] = Mesh_GPU_Data {
			vertex_buffer = vertex_buffer,
			index_buffer  = index_buffer,
			num_vertices  = len(mesh.vertices),
			num_indices   = len(mesh.indices),
		}
	}

	gpu_scene_compile_objects_data(gpu_scene, ctx, scene)
	gpu_scene_compile_materials(gpu_scene, ctx, scene)
	gpu_scene_compile_bottom_level_as(gpu_scene, ctx)
	gpu_scene_compile_top_level_as(gpu_scene, ctx, scene)
}

gpu_scene_compile_top_level_as :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	tlas := &gpu_scene.tlas_infos
	if len(tlas) > 0 {
		delete(tlas^)
	}
	tlas^ = make([dynamic]vk.AccelerationStructureInstanceKHR, 0, len(scene.objects))

	for obj, i in scene.objects {
		model_matrix := obj.transform.model_matrix
		mask: u32 = 0xFF
		if material := scene.materials[obj.material_index]; material.emission_power > 0 {
			mask = (1 << (u32(i) & 7))
		}
		ray_inst := vk.AccelerationStructureInstanceKHR {
			transform                              = matrix_to_transform_matrix_khr(model_matrix),
			instanceCustomIndex                    = u32(i),
			mask                                   = mask,
			instanceShaderBindingTableRecordOffset = 0,
			flags                                  = .TRIANGLE_FACING_CULL_DISABLE,
			accelerationStructureReference         = u64(
				get_blas_device_address(
					gpu_scene.acceleration_structures[obj.mesh_index],
					vulkan_get_device_handle(ctx),
				),
			),
		}
		append(tlas, ray_inst)
	}

	gpu_scene_build_tlas(gpu_scene, ctx, tlas[:], flags = {.PREFER_FAST_TRACE, .ALLOW_UPDATE})
}

gpu_scene_build_tlas :: proc(
	gpu_scene: ^GPU_Scene,
	ctx: ^Vulkan_Context,
	instances: []vk.AccelerationStructureInstanceKHR,
	flags: vk.BuildAccelerationStructureFlagsKHR = {.PREFER_FAST_TRACE},
	update := false,
) {
	assert(gpu_scene.tlas.handle == 0 || update, "Cannot build tlas twice, only update")
	device := ctx.device
	count_instance := u32(len(instances))

	instances_buffer: Buffer
	buffer_init_with_staging_buffer(
		&instances_buffer,
		ctx,
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
			&gpu_scene.tlas,
			cmd,
			count_instance,
			buffer_get_device_address(instances_buffer),
			&scratch_buffer,
			flags,
			update = update,
			motion = false,
			ctx = ctx,
		)
	}
}

gpu_scene_compile_bottom_level_as :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context) {
	inputs := make(
		[dynamic]Bottom_Level_Input,
		0,
		len(gpu_scene.meshes_data),
		allocator = context.temp_allocator,
	)
	device := ctx.device

	for &mesh in gpu_scene.meshes_data {
		append(&inputs, mesh_to_geometry(&mesh, device^))
	}

	gpu_scene_build_blas(gpu_scene, ctx, inputs[:], {.PREFER_FAST_TRACE})
}

gpu_scene_build_blas :: proc(
	gpu_scene: ^GPU_Scene,
	ctx: ^Vulkan_Context,
	inputs: []Bottom_Level_Input,
	flags: vk.BuildAccelerationStructureFlagsKHR,
) {
	device := ctx.device
	build_infos := make([]Build_Acceleration_Structure, len(inputs), context.temp_allocator)

	n_blas := u32(len(inputs))
	total_size, max_scratch_size: vk.DeviceSize
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
		ctx,
		u64(max_scratch_size),
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		.Gpu_Only,
		alignment = 128,
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
	batch_limit := vk.DeviceSize(256_000_000)
	for i in 0 ..< n_blas {
		append(&indices, i)
		batch_size += build_infos[i].size_info.accelerationStructureSize

		if batch_size >= batch_limit || i == n_blas - 1 {
			cmd := device_begin_single_time_commands(device, device.command_pool)
			defer device_end_single_time_commands(device, device.command_pool, cmd)

			cmd_create_blas(
				cmd,
				indices[:],
				build_infos,
				buffer_get_device_address(scratch_buffer),
				query_pool,
				ctx,
			)

			if query_pool != 0 {
				// cmd := device_begin_single_time_commands(device, device.command_pool)
				// defer device_end_single_time_commands(device, device.command_pool, cmd)

				// compact
			}

			batch_size = 0
			clear(&indices)

		}
	}

	gpu_scene.acceleration_structures = make([dynamic]Acceleration_Structure, 0, len(build_infos))

	for b in build_infos {
		append(&gpu_scene.acceleration_structures, b.as)
	}
}

gpu_scene_compile_objects_data :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	objects_data := make([]Object_GPU_Data, len(scene.objects), context.temp_allocator)

	for object, i in scene.objects {
		mesh := gpu_scene.meshes_data[object.mesh_index]
		objects_data[i] = Object_GPU_Data {
			vertex_buffer_address = buffer_get_device_address(mesh.vertex_buffer),
			index_buffer_address  = buffer_get_device_address(mesh.index_buffer),
			material_index        = u32(object.material_index),
			mesh_index            = u32(object.mesh_index),
		}
	}

	gpu_scene.objects_buffer = make_storage_buffer_set(
		ctx,
		u64(size_of(Object_GPU_Data) * len(objects_data)),
		MAX_FRAMES_IN_FLIGHT,
	)
	for f in 0 ..< MAX_FRAMES_IN_FLIGHT {
		buffer := storage_buffer_set_get(&gpu_scene.objects_buffer, f)
		buffer_map(buffer)
		buffer_write_rawptr(
			buffer,
			raw_data(objects_data),
			0,
			vk.DeviceSize(size_of(Object_GPU_Data) * len(objects_data)),
		)
		buffer_flush(buffer, 0, buffer.size)
	}

	gpu_scene_compile_lights(gpu_scene, ctx, scene)
}

gpu_scene_compile_lights :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	lights_data := make([dynamic]Light_GPU_Data, context.temp_allocator)

	for object, i in scene.objects {
		if scene.materials[object.material_index].emission_power > 0 {
			mask := u32(1 << (u32(i) & 7))
			append(
				&lights_data,
				Light_GPU_Data {
					transform = intrinsics.matrix_flatten(object.transform.model_matrix),
					object_index = u32(i),
					num_triangles = u32(len(scene.meshes[object.mesh_index].indices) / 3),
					instance_mask = mask,
				},
			)
		}
	}

	gpu_scene.lights_buffer = make_storage_buffer_set(
		ctx,
		u64(size_of(Light_GPU_Data) * len(lights_data)),
		MAX_FRAMES_IN_FLIGHT,
	)
	for f in 0 ..< MAX_FRAMES_IN_FLIGHT {
		buffer := storage_buffer_set_get(&gpu_scene.lights_buffer, f)
		buffer_map(buffer)
		buffer_write_rawptr(
			buffer,
			raw_data(lights_data),
			0,
			vk.DeviceSize(size_of(Light_GPU_Data) * len(lights_data)),
		)
		buffer_flush(buffer, 0, buffer.size)
	}
}

gpu_scene_compile_materials :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	materials_data := make([]Material_Data, len(scene.materials), context.temp_allocator)
	for material, i in scene.materials {
		materials_data[i] = {
			albedo         = material.albedo,
			emission_color = material.emission_color,
			emission_power = material.emission_power,
			roughness      = material.roughness,
			metallic       = material.metallic,
			transmission   = material.transmission,
			ior            = material.ior,
		}
	}

	gpu_scene.materials_buffer = make_storage_buffer_set(
		ctx,
		u64(size_of(Material_Data) * len(materials_data)),
		MAX_FRAMES_IN_FLIGHT,
	)
	for f in 0 ..< MAX_FRAMES_IN_FLIGHT {
		buffer := storage_buffer_set_get(&gpu_scene.materials_buffer, f)
		buffer_map(buffer)
		buffer_write_rawptr(
			buffer,
			raw_data(materials_data),
			0,
			vk.DeviceSize(size_of(Material_Data) * len(materials_data)),
		)
	}
}

gpu_scene_add_material :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	gpu_scene_recompile_materials(gpu_scene, ctx, scene)
}

gpu_scene_remove_material :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	gpu_scene_recompile_materials(gpu_scene, ctx, scene)
}

gpu_scene_recompile_materials :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	storage_buffer_set_destroy(ctx, &gpu_scene.materials_buffer)
	gpu_scene_compile_materials(gpu_scene, ctx, scene)
}

gpu_scene_add_object :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	gpu_scene_recompile_objects(gpu_scene, ctx, scene)
}

gpu_scene_remove_object :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	gpu_scene_recompile_objects(gpu_scene, ctx, scene)
}

gpu_scene_recompile_objects :: proc(gpu_scene: ^GPU_Scene, ctx: ^Vulkan_Context, scene: Scene) {
	storage_buffer_set_destroy(ctx, &gpu_scene.objects_buffer)
	storage_buffer_set_destroy(ctx, &gpu_scene.lights_buffer)
	gpu_scene_compile_objects_data(gpu_scene, ctx, scene)
	gpu_scene_compile_lights(gpu_scene, ctx, scene)
}

gpu_scene_update_object_transform :: proc(
	gpu_scene: ^GPU_Scene,
	ctx: ^Vulkan_Context,
	scene: Scene,
	object_index: int,
) {
	object := scene.objects[object_index]

	gpu_scene.tlas_infos[object_index].transform = matrix_to_transform_matrix_khr(
		object.transform.model_matrix,
	)

	if scene.materials[object.material_index].emission_power > 0 {
		storage_buffer_set_destroy(ctx, &gpu_scene.lights_buffer)
		gpu_scene_compile_lights(gpu_scene, ctx, scene)
	}

	gpu_scene_build_tlas(
		gpu_scene,
		ctx,
		gpu_scene.tlas_infos[:],
		{.PREFER_FAST_TRACE, .ALLOW_UPDATE},
		update = true,
	)
}

gpu_scene_update_object :: proc(
	gpu_scene: ^GPU_Scene,
	ctx: ^Vulkan_Context,
	scene: ^Scene,
	object_index: int,
	changed_material := false,
) {
	object := &scene.objects[object_index]
	mesh := &gpu_scene.meshes_data[object.mesh_index]

	object_data := Object_GPU_Data {
		vertex_buffer_address = buffer_get_device_address(mesh.vertex_buffer),
		index_buffer_address  = buffer_get_device_address(mesh.index_buffer),
		material_index        = u32(object.material_index),
		mesh_index            = u32(object.mesh_index),
	}

	offset := vk.DeviceSize(object_index * size_of(Object_GPU_Data))
	storage_buffer_set_write(&gpu_scene.objects_buffer, &object_data, offset)

	// for now lets do it like this, lets recompile the whole lights because for now we dont have a way to know
	if changed_material {
		storage_buffer_set_destroy(ctx, &gpu_scene.lights_buffer)
		gpu_scene_compile_lights(gpu_scene, ctx, scene^)
		mask: u32 = 0xFF
		if material := scene.materials[object.material_index]; material.emission_power > 0 {
			mask = (1 << (u32(object_index) & 7))
		}
		gpu_scene.tlas_infos[object_index].mask = mask
		gpu_scene_build_tlas(
			gpu_scene,
			ctx,
			gpu_scene.tlas_infos[:],
			{.PREFER_FAST_TRACE, .ALLOW_UPDATE},
			update = true,
		)
	}
}

gpu_scene_update_material :: proc(gpu_scene: ^GPU_Scene, scene: ^Scene, material_index: int) {
	material := &scene.materials[material_index]

	material_data := Material_Data {
		albedo         = material.albedo,
		emission_color = material.emission_color,
		emission_power = material.emission_power,
		roughness      = material.roughness,
		metallic       = material.metallic,
		transmission   = material.transmission,
		ior            = material.ior,
	}

	offset := vk.DeviceSize(material_index * size_of(Material_Data))

	storage_buffer_set_write(&gpu_scene.materials_buffer, &material_data, offset = offset)
}
