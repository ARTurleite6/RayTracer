package raytracer

import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:mem"
import vk "vendor:vulkan"
_ :: fmt

Raytracing_Builder :: struct {
	tlas:       Acceleration_Structure,
	as:         [dynamic]Acceleration_Structure,
	tlas_infos: [dynamic]vk.AccelerationStructureInstanceKHR,
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

mesh_to_geometry :: proc(mesh: ^Mesh_GPU_Data, device: Device) -> Bottom_Level_Input {
	vertex_address := buffer_get_device_address(mesh.vertex_buffer)
	index_address := buffer_get_device_address(mesh.index_buffer)

	max_primitives := u32(mesh.num_indices) / 3

	triangles := vk.AccelerationStructureGeometryTrianglesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
		vertexFormat = .R32G32B32_SFLOAT,
		vertexData = {deviceAddress = vertex_address},
		vertexStride = size_of(Vertex),
		indexType = .UINT32,
		indexData = {deviceAddress = index_address},
		maxVertex = u32(mesh.num_vertices) - 1,
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
	tlas: ^Acceleration_Structure,
	cmd: vk.CommandBuffer,
	count_instance: u32,
	instance_buffer_address: vk.DeviceAddress,
	scratch_buffer: ^Buffer,
	flags: vk.BuildAccelerationStructureFlagsKHR,
	update, motion: bool,
	ctx: ^Vulkan_Context,
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
		sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		flags         = flags,
		geometryCount = 1,
		pGeometries   = &top_as_geometry,
		mode          = update ? .UPDATE : .BUILD,
		type          = .TOP_LEVEL,
	}

	size_info := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}

	count_instance := count_instance
	vk.GetAccelerationStructureBuildSizesKHR(
		vulkan_get_device_handle(ctx),
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


	_ = buffer_init(
		scratch_buffer,
		ctx,
		u64(size_info.buildScratchSize),
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
		alignment = 128, // TODO: THIS NEEDS TO BE CHANGED ALSO
	)
	defer buffer_destroy(scratch_buffer)

	if update {
		build_info.srcAccelerationStructure = tlas.handle
	} else {
		tlas^ = create_acceleration(&create_info, ctx)
	}

	build_info.dstAccelerationStructure = tlas.handle
	build_info.scratchData.deviceAddress = buffer_get_device_address(scratch_buffer^)

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
	ctx: ^Vulkan_Context,
) {
	if query_pool != 0 {
		vk.ResetQueryPool(vulkan_get_device_handle(ctx), query_pool, 0, u32(len(indices)))
	}
	query_count: u32

	for idx in indices {
		create_info := vk.AccelerationStructureCreateInfoKHR {
			sType = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
			type  = .BOTTOM_LEVEL,
			size  = infos[idx].size_info.accelerationStructureSize,
		}

		infos[idx].as = create_acceleration(&create_info, ctx)

		infos[idx].build_info.dstAccelerationStructure = infos[idx].as.handle
		infos[idx].build_info.scratchData.deviceAddress = scratch_address

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
	ctx: ^Vulkan_Context,
) -> (
	as: Acceleration_Structure,
) {
	_ = buffer_init(
		&as.buffer,
		ctx,
		u64(create_info.size),
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	)
	create_info.buffer = as.buffer.handle

	_ = vk_check(
		vk.CreateAccelerationStructureKHR(
			vulkan_get_device_handle(ctx),
			create_info,
			nil,
			&as.handle,
		),
		"Failed to create acceleration structure",
	)

	return as
}

matrix_to_transform_matrix_khr :: proc(m: Mat4) -> vk.TransformMatrixKHR {
	temp := glm.transpose(m)
	out_matrix := vk.TransformMatrixKHR{}

	mem.copy(&out_matrix, &temp, size_of(vk.TransformMatrixKHR))

	return out_matrix
}

get_blas_device_address :: proc(
	as: Acceleration_Structure,
	device: vk.Device,
) -> vk.DeviceAddress {
	info := vk.AccelerationStructureDeviceAddressInfoKHR {
		sType                 = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
		accelerationStructure = as.handle,
	}

	return vk.GetAccelerationStructureDeviceAddressKHR(device, &info)
}

