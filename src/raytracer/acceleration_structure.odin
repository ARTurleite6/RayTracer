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

mesh_to_geometry :: proc(mesh: ^Mesh_GPU_Data, device: Device) -> Bottom_Level_Input {
	vertex_address := buffer_get_device_address(mesh.vertex_buffer, device)
	index_address := buffer_get_device_address(mesh.index_buffer, device)

	max_primitives := u32(mesh.index_buffer.instance_count) / 3

	triangles := vk.AccelerationStructureGeometryTrianglesDataKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
		vertexFormat = .R32G32B32_SFLOAT,
		vertexData = {deviceAddress = vertex_address},
		vertexStride = size_of(Vertex),
		indexType = .UINT32,
		indexData = {deviceAddress = index_address},
		maxVertex = u32(mesh.vertex_buffer.instance_count) - 1,
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

	if !update {
		rt_builder.tlas = create_acceleration(&create_info, device)
	}

	buffer_init(
		scratch_buffer,
		device,
		size_info.buildScratchSize,
		1,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
		alignment = 128, // TODO: THIS NEEDS TO BE CHANGED ALSO
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
