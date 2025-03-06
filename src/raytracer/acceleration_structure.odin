package raytracer

import "base:runtime"
import "core:fmt"
import glm "core:math/linalg"
import vk "vendor:vulkan"
_ :: fmt

Raytracing_Builder :: struct {
	tlas: Acceleration_Structure,
	as:   [dynamic]Acceleration_Structure,
}

Acceleration_Structure :: struct {
	handle: vk.AccelerationStructureKHR,
	buffer: Buffer,
}

Bottom_Level_Input :: struct {
	geometry: vk.AccelerationStructureGeometryKHR,
	offset:   vk.AccelerationStructureBuildRangeInfoKHR,
}

Build_Acceleration_Structure :: struct {
	build_info: vk.AccelerationStructureBuildGeometryInfoKHR,
	range_info: vk.AccelerationStructureBuildRangeInfoKHR,
	size_info:  vk.AccelerationStructureBuildSizesInfoKHR,
	as:         Acceleration_Structure,
}

create_top_level_as :: proc(rt_builder: ^Raytracing_Builder, scene: Scene, device: ^Device) {
	tlas := make([dynamic]vk.AccelerationStructureInstanceKHR, 0, len(scene.objects))

	for obj in scene.objects {
		ray_inst := vk.AccelerationStructureInstanceKHR {
			transform                                      = matrix_to_transform_matrix_khr(
				obj.transform.model_matrix,
			),
			instanceCustomIndexAndMask                     = (0xFF << 24) | u32(obj.mesh_index),
			instanceShaderBindingTableRecordOffsetAndFlags = (u32(
					vk.GeometryInstanceFlagsKHR{.TRIANGLE_FACING_CULL_DISABLE},
				) <<
				24) | 0,
		}

		append(&tlas, ray_inst)
	}

	build_tlas(rt_builder, tlas[:], device)
}

build_tlas :: proc(
	rt_builder: ^Raytracing_Builder,
	instances: []vk.AccelerationStructureInstanceKHR,
	device: ^Device,
	flags: vk.BuildAccelerationStructureFlagsKHR = {.PREFER_FAST_TRACE},
	update := false,
) {
	assert(rt_builder.tlas.handle == 0, "Cannot build tlas twice, only update")

	count_instance := u32(len(instances))

	cmd := device_begin_single_time_commands(device, device.command_pool)
	defer device_end_single_time_commands(device, device.command_pool, cmd)

	instances_buffer: Buffer
	buffer_init_with_staging_buffer(
		&instances_buffer,
		device,
		raw_data(instances),
		size_of(vk.AccelerationStructureKHR),
		1,
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	)

	memory_barrier := vk.MemoryBarrier2 {
		sType         = .MEMORY_BARRIER_2,
		srcStageMask  = {.TRANSFER},
		dstStageMask  = {.ACCELERATION_STRUCTURE_BUILD_KHR},
		srcAccessMask = {.TRANSFER_WRITE},
		dstAccessMask = {.ACCELERATION_STRUCTURE_WRITE_KHR},
	}

	dependency_info := vk.DependencyInfo {
		sType              = .DEPENDENCY_INFO,
		memoryBarrierCount = 1,
		pMemoryBarriers    = &memory_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dependency_info)

	scratch_buffer: Buffer
	cmd_create_tlas(
		rt_builder,
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

create_bottom_level_as :: proc(rt_builder: ^Raytracing_Builder, scene: Scene, device: ^Device) {
	inputs := make([dynamic]Bottom_Level_Input, 0, len(scene.meshes))

	for &mesh in scene.meshes {
		append(&inputs, mesh_to_geometry(&mesh, device^))
	}
	fmt.println(inputs)

	build_blas(rt_builder, inputs[:], {.PREFER_FAST_TRACE}, device)
}

build_blas :: proc(
	rt_builder: ^Raytracing_Builder,
	inputs: []Bottom_Level_Input,
	flags: vk.BuildAccelerationStructureFlagsKHR,
	device: ^Device,
) {
	build_infos := make([]Build_Acceleration_Structure, len(inputs))

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
		max_scratch_size += max(info.size_info.buildScratchSize, max_scratch_size)
		number_compactions += .ALLOW_COMPACTION in info.build_info.flags
	}

	scratch_buffer: Buffer
	buffer_init(
		&scratch_buffer,
		device,
		max_scratch_size,
		1,
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
		.Gpu_Only,
	)


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

	indices := make([dynamic]u32)

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
				cmd := device_begin_single_time_commands(device, device.command_pool)
				defer device_end_single_time_commands(device, device.command_pool, cmd)

				// compact
			}

			batch_size = 0
			clear(&indices)
		}
	}

	rt_builder.as = make([dynamic]Acceleration_Structure, 0, len(build_infos))

	for b in build_infos {
		append(&rt_builder.as, b.as)
	}
}

mesh_to_geometry :: proc(mesh: ^Mesh, device: Device) -> Bottom_Level_Input {
	vertex_address := buffer_get_device_address(mesh.vertex_buffer, device)
	index_address := buffer_get_device_address(mesh.index_buffer, device)

	max_primitives := mesh.index_count / 3

	triangles := vk.AccelerationStructureGeometryTrianglesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
		vertexFormat = .R32G32B32_SFLOAT,
		vertexData = {deviceAddress = vertex_address},
		vertexStride = size_of(Vertex),
		indexType = .UINT32,
		indexData = {deviceAddress = index_address},
		maxVertex = mesh.vertex_count - 1,
	}

	geom := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		flags = {.OPAQUE},
		geometryType = .TRIANGLES,
		geometry = {triangles = triangles},
	}

	offset := vk.AccelerationStructureBuildRangeInfoKHR {
		firstVertex     = 0,
		primitiveCount  = max_primitives,
		primitiveOffset = 0,
		transformOffset = 0,
	}

	return {geometry = geom, offset = offset}
}

cmd_create_tlas :: proc(
	rt_builder: ^Raytracing_Builder,
	cmd: vk.CommandBuffer,
	count_instance: u32,
	instance_buffer_address: vk.DeviceAddress,
	scratch_buffer: ^Buffer,
	flags: vk.BuildAccelerationStructureFlagsKHR,
	update, motion: bool,
	device: ^Device,
) {
	instances_vk := vk.AccelerationStructureGeometryInstancesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
		data = {deviceAddress = instance_buffer_address},
	}

	top_as_geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .INSTANCES,
		geometry = {instances = instances_vk},
	}

	build_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType                    = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		flags                    = flags,
		geometryCount            = 1,
		pGeometries              = &top_as_geometry,
		mode                     = update ? .UPDATE : .BUILD,
		type                     = .TOP_LEVEL,
		srcAccelerationStructure = 0,
	}

	size_info := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}

	count_instance := count_instance
	vk.GetAccelerationStructureBuildSizesKHR(
		device.logical_device.ptr,
		.DEVICE,
		&build_info,
		&count_instance,
		&size_info,
	)

	create_info := vk.AccelerationStructureCreateInfoKHR {
		sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		type  = .TOP_LEVEL,
		size  = size_info.accelerationStructureSize,
	}

	rt_builder.tlas = create_acceleration(&create_info, device)

	buffer_init(
		scratch_buffer,
		device,
		size_info.buildScratchSize,
		1,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	)

	build_info.srcAccelerationStructure = 0
	build_info.dstAccelerationStructure = rt_builder.tlas.handle
	build_info.scratchData.deviceAddress = buffer_get_device_address(scratch_buffer^, device^)

	range_info := vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount  = count_instance,
		primitiveOffset = 0,
		firstVertex     = 0,
		transformOffset = 0,
	}
	p_range_info: [^]vk.AccelerationStructureBuildRangeInfoKHR = &range_info

	vk.CmdBuildAccelerationStructuresKHR(cmd, 1, &build_info, &p_range_info)
}

cmd_create_blas :: proc(
	cmd: vk.CommandBuffer,
	indices: []u32,
	infos: []Build_Acceleration_Structure,
	scratch_address: vk.DeviceAddress,
	query_pool: vk.QueryPool,
	device: ^Device,
) {
	if query_pool != 0 {
		vk.ResetQueryPool(device.logical_device.ptr, query_pool, 0, u32(len(indices)))
	}
	query_count: u32

	for idx in indices {
		create_info := vk.AccelerationStructureCreateInfoKHR {
			sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
			type  = .BOTTOM_LEVEL,
			size  = infos[idx].size_info.accelerationStructureSize,
		}

		infos[idx].as = create_acceleration(&create_info, device)

		infos[idx].build_info.dstAccelerationStructure = infos[idx].as.handle
		infos[idx].build_info.scratchData.deviceAddress = scratch_address

		fmt.println(infos[idx].range_info)
		range_infos: [^]vk.AccelerationStructureBuildRangeInfoKHR = &infos[idx].range_info
		vk.CmdBuildAccelerationStructuresKHR(cmd, 1, &infos[idx].build_info, &range_infos)

		barrier := vk.MemoryBarrier2 {
			sType         = .MEMORY_BARRIER_2,
			srcStageMask  = {.ACCELERATION_STRUCTURE_BUILD_KHR},
			dstStageMask  = {.ACCELERATION_STRUCTURE_BUILD_KHR},
			srcAccessMask = {.ACCELERATION_STRUCTURE_WRITE_KHR},
			dstAccessMask = {.ACCELERATION_STRUCTURE_READ_KHR},
		}
		dependency := vk.DependencyInfo {
			sType              = .DEPENDENCY_INFO,
			memoryBarrierCount = 1,
			pMemoryBarriers    = &barrier,
		}
		vk.CmdPipelineBarrier2(cmd, &dependency)

		if query_pool != 0 {
			vk.CmdWriteAccelerationStructuresPropertiesKHR(
				cmd,
				1,
				&infos[idx].build_info.dstAccelerationStructure,
				.ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR,
				query_pool,
				query_count,
			)
			query_count += 1
		}
	}
}

cmd_compact_blas :: proc(
	cmd: vk.CommandBuffer,
	indices: []u32,
	infos: []Build_Acceleration_Structure,
	query_pool: vk.QueryPool,
) {
	// TODO: implement this
}

create_acceleration :: proc(
	create_info: ^vk.AccelerationStructureCreateInfoKHR,
	device: ^Device,
) -> (
	as: Acceleration_Structure,
) {
	buffer_init(
		&as.buffer,
		device,
		create_info.size,
		1,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	)
	create_info.buffer = as.buffer.handle

	_ = vk_check(
		vk.CreateAccelerationStructureKHR(device.logical_device.ptr, create_info, nil, &as.handle),
		"Failed to create acceleration structure",
	)

	return as
}

matrix_to_transform_matrix_khr :: proc(m: Mat4) -> vk.TransformMatrixKHR {
	temp := glm.transpose(m)
	out_matrix := vk.TransformMatrixKHR{}

	runtime.mem_copy(&out_matrix, &temp, size_of(vk.TransformMatrixKHR))

	return out_matrix
}
