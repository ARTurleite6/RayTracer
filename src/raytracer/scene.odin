package raytracer

import "base:runtime"
import glm "core:math/linalg"
// import vma "external:odin-vma"
import vk "vendor:vulkan"

Vertex :: struct {
	pos:   Vec3,
	color: Vec3,
}

VERTEX_INPUT_BINDING_DESCRIPTION := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

VERTEX_INPUT_ATTRIBUTE_DESCRIPTION := [?]vk.VertexInputAttributeDescription {
	{binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, color)),
	},
}

Acceleration_Structure :: struct {
	handler: vk.AccelerationStructureKHR,
	buffer:  Buffer,
}

Scene :: struct {
	// TODO
	meshes:          [dynamic]Mesh,
	objects:         [dynamic]Object,
	bottom_level_as: [dynamic]Acceleration_Structure,
	top_level_as:    Acceleration_Structure,
	instance_buffer: Buffer,
}

Object :: struct {
	name:       string,
	transform:  Transform,
	mesh_index: int,
}

Transform :: struct {
	position:     Vec3,
	rotation:     Vec3,
	scale:        Vec3,
	model_matrix: Mat4,
}

Mesh :: struct {
	name:          string,
	vertex_count:  u32,
	index_count:   u32,
	vertex_buffer: Buffer,
	index_buffer:  Buffer,
}

Mesh_Error :: union {
	Buffer_Error,
}

Scene_UBO :: struct {
	view:       Mat4,
	projection: Mat4,
}

Push_Constants :: struct {
	model_matrix: Mat4,
}

scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	scene.meshes = make([dynamic]Mesh, allocator)
	scene.objects = make([dynamic]Object, allocator)
	scene.bottom_level_as = make([dynamic]Acceleration_Structure, allocator)
}

scene_destroy :: proc(scene: ^Scene, device: ^Device) {
	for &mesh in scene.meshes {
		mesh_destroy(&mesh, device)
	}
	delete(scene.meshes)
	delete(scene.objects)
	delete(scene.bottom_level_as)
	scene^ = {}
}

scene_add_mesh :: proc(scene: ^Scene, mesh: Mesh) -> int {
	append(&scene.meshes, mesh)
	return len(scene.meshes) - 1
}

scene_add_object :: proc(
	scene: ^Scene,
	name: string,
	mesh_index: int,
	transform: Transform,
) -> (
	idx: int,
) {
	assert(mesh_index >= 0 && mesh_index < len(scene.meshes), "Invalid mesh index") // TODO: Move this to a error handling

	object := Object {
		name       = name,
		transform  = transform,
		mesh_index = mesh_index,
	}
	object_update_model_matrix(&object)

	append(&scene.objects, object)
	return len(scene.objects) - 1
}

// TODO: probably in the future would it be nice to change this, to not pass the pipeline_layout
scene_draw :: proc(scene: ^Scene, cmd: vk.CommandBuffer, pipeline_layout: vk.PipelineLayout) {
	for &object in scene.objects {

		transform := object.transform.model_matrix // glm.MATRIX4F32_IDENTITY
		// glm.matrix4_rotate_f32(90 * glm.DEG_PER_RAD, {0, 1, 0}) *
		// glm.matrix4_rotate_f32(90 * glm.DEG_PER_RAD, {0, 0, 1})

		push_constant := Push_Constants {
			// model_matrix = glm.identity_matrix(Mat4),
			model_matrix = transform,
		}

		vk.CmdPushConstants(
			cmd,
			pipeline_layout,
			{.VERTEX},
			0,
			size_of(Push_Constants),
			&push_constant,
		)

		mesh := &scene.meshes[object.mesh_index]

		mesh_draw(mesh, cmd)
	}
}

scene_create_acceleration_structures :: proc(scene: ^Scene, device: ^Device) {
	cmd := device_begin_single_time_commands(device, device.command_pool)

	for mesh in scene.meshes {
		as, _ := create_bottom_level_as(device, mesh, cmd)
		append(&scene.bottom_level_as, as)
	}

	create_top_level_as(device, scene, cmd)

	defer device_end_single_time_commands(device, device.command_pool, cmd)
}

object_update_position :: proc(object: ^Object, new_pos: Vec3) {
	object.transform.position = new_pos
	object_update_model_matrix(object)
}

object_update_model_matrix :: proc(object: ^Object) {
	transform := &object.transform
	transform.model_matrix = glm.matrix4_translate(transform.position)
}

@(private)
create_scene :: proc(device: ^Device) -> (scene: Scene) {
	scene_init(&scene)

	quad_mesh := create_cube(device)
	mesh_index := scene_add_mesh(&scene, quad_mesh)

	scene_add_object(&scene, "quad", mesh_index, {})

	return scene
}

mesh_init :: proc(
	mesh: ^Mesh,
	device: ^Device,
	vertices: []Vertex,
	indices: []u32,
	name: string,
) -> Mesh_Error {
	mesh.name = name
	mesh.vertex_count = u32(len(vertices))

	vertex_buffer_init(&mesh.vertex_buffer, device, vertices) or_return
	if len(indices) > 0 {
		buffer_init_with_staging_buffer(
			&mesh.index_buffer,
			device,
			raw_data(indices),
			size_of(u32),
			len(indices),
			{
				.INDEX_BUFFER,
				.SHADER_DEVICE_ADDRESS,
				.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
			},
		) or_return
		mesh.index_count = u32(len(indices))
	}

	return nil
}

mesh_destroy :: proc(mesh: ^Mesh, device: ^Device) {
	buffer_destroy(&mesh.vertex_buffer, device)
}

mesh_draw :: proc(mesh: ^Mesh, cmd: vk.CommandBuffer) {
	offsets := vk.DeviceSize(0)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &mesh.vertex_buffer.handle, &offsets)

	if mesh.index_count > 0 {
		vk.CmdBindIndexBuffer(cmd, mesh.index_buffer.handle, 0, .UINT32)
		vk.CmdDrawIndexed(cmd, mesh.index_count, 1, 0, 0, 0)
	} else {
		vk.CmdDraw(cmd, mesh.vertex_count, 1, 0, 0)
	}
}

create_quad :: proc(device: ^Device) -> (mesh: Mesh) {

	vertices := []Vertex {
		{{-0.5, -0.5, 0}, {1, 0, 0}}, // Bottom-left
		{{-0.5, 0.5, 0}, {1, 1, 1}}, // Top-left
		{{0.5, 0.5, 0}, {0, 0, 1}}, // Top-right
		{{0.5, -0.5, 0}, {0, 1, 0}}, // Bottom-right
	}

	// Counter-clockwise indices
	indices := []u32 {
		0,
		1,
		2, // First triangle (left side)
		0,
		2,
		3, // Second triangle (right side)
	}
	mesh_init(&mesh, device, vertices, indices, "Quad")

	return mesh
}

create_cube :: proc(device: ^Device) -> (mesh: Mesh) {
	vertices := []Vertex {
		// Front face
		{{-0.5, -0.5, 0.5}, {1, 0, 0}}, // 0
		{{-0.5, 0.5, 0.5}, {1, 1, 0}}, // 1
		{{0.5, 0.5, 0.5}, {0, 0, 1}}, // 2
		{{0.5, -0.5, 0.5}, {0, 1, 0}}, // 3

		// Back face
		{{-0.5, -0.5, -0.5}, {1, 0, 1}}, // 4
		{{-0.5, 0.5, -0.5}, {0, 0, 0}}, // 5
		{{0.5, 0.5, -0.5}, {1, 1, 1}}, // 6
		{{0.5, -0.5, -0.5}, {0, 1, 1}}, // 7
	}

	// Counter-clockwise indices for each face
	indices := []u32 {
		// Front face
		0,
		1,
		2,
		0,
		2,
		3,

		// Back face
		7,
		6,
		5,
		7,
		5,
		4,

		// Right face
		3,
		2,
		6,
		3,
		6,
		7,

		// Left face
		4,
		5,
		1,
		4,
		1,
		0,

		// Top face
		1,
		5,
		6,
		1,
		6,
		2,

		// Bottom face
		4,
		0,
		3,
		4,
		3,
		7,
	}

	mesh_init(&mesh, device, vertices, indices, "Cube")
	return mesh
}

@(require_results)
create_bottom_level_as :: proc(
	device: ^Device,
	mesh: Mesh,
	cmd: vk.CommandBuffer,
) -> (
	as: Acceleration_Structure,
	err: Buffer_Error,
) {
	vertex_address := buffer_get_device_address(device^, mesh.vertex_buffer)
	index_address := buffer_get_device_address(device^, mesh.index_buffer)

	geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .TRIANGLES,
		geometry = {
			triangles = {
				sType = .ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
				vertexFormat = .R32G32B32_SFLOAT,
				vertexData = {deviceAddress = vertex_address},
				vertexStride = size_of(Vertex),
				maxVertex = mesh.vertex_count - 1,
				indexType = .UINT32,
				indexData = {deviceAddress = index_address},
			},
		},
		flags = {.OPAQUE},
	}

	primitive_count := u32(mesh.index_count / 3)
	build_range_info := vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount  = primitive_count,
		primitiveOffset = 0,
		firstVertex     = 0,
	}

	build_geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type          = .BOTTOM_LEVEL,
		flags         = {.PREFER_FAST_TRACE},
		geometryCount = 1,
		pGeometries   = &geometry,
	}

	size_info := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}

	vk.GetAccelerationStructureBuildSizesKHR(
		device.logical_device.ptr,
		.DEVICE,
		&build_geometry_info,
		&primitive_count,
		&size_info,
	)

	buffer_init(
		&as.buffer,
		device,
		size_info.accelerationStructureSize,
		1,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	) or_return

	create_info := vk.AccelerationStructureCreateInfoKHR {
		sType  = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer = as.buffer.handle,
		size   = size_info.accelerationStructureSize,
		type   = .BOTTOM_LEVEL,
	}

	_ = vk_check(
		vk.CreateAccelerationStructureKHR(
			device.logical_device.ptr,
			&create_info,
			nil,
			&as.handler,
		),
		"Error creating bottom level acceleration structure",
	)

	scratch_buffer: Buffer
	buffer_init(
		&scratch_buffer,
		device,
		size_info.buildScratchSize,
		1,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	) or_return
	defer buffer_destroy(&scratch_buffer, device)

	scratch_address := buffer_get_device_address(device^, scratch_buffer)

	build_geometry_info.mode = .BUILD
	build_geometry_info.dstAccelerationStructure = as.handler
	build_geometry_info.scratchData.deviceAddress = scratch_address

	p_build_range_info: [^]vk.AccelerationStructureBuildRangeInfoKHR = &build_range_info
	vk.CmdBuildAccelerationStructuresKHR(cmd, 1, &build_geometry_info, &p_build_range_info)

	memory_barrier := vk.MemoryBarrier {
		sType         = .MEMORY_BARRIER,
		srcAccessMask = {.ACCELERATION_STRUCTURE_WRITE_KHR},
		dstAccessMask = {.ACCELERATION_STRUCTURE_READ_KHR},
	}

	vk.CmdPipelineBarrier(
		cmd,
		{.ACCELERATION_STRUCTURE_BUILD_KHR}, // srcStageMask
		{.ACCELERATION_STRUCTURE_BUILD_KHR}, // dstStageMask
		{}, // dependencyFlags
		1, // memoryBarrierCount
		&memory_barrier, // pMemoryBarriers
		0, // bufferMemoryBarrierCount
		nil, // pBufferMemoryBarriers
		0, // imageMemoryBarrierCount
		nil, // pImageMemoryBarriers
	)

	return as, nil
}

create_top_level_as :: proc(
	device: ^Device,
	scene: ^Scene,
	cmd: vk.CommandBuffer,
) -> (
	err: Buffer_Error,
) {
	instances := make(
		[dynamic]vk.AccelerationStructureInstanceKHR,
		0,
		len(scene.objects),
		context.temp_allocator,
	)

	for &object, i in scene.objects {
		mesh_idx := object.mesh_index
		blas := scene.bottom_level_as[mesh_idx]

		blas_address_info := vk.AccelerationStructureDeviceAddressInfoKHR {
			sType                 = .ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
			accelerationStructure = blas.handler,
		}

		blas_address := vk.GetAccelerationStructureDeviceAddressKHR(
			device.logical_device.ptr,
			&blas_address_info,
		)

		transform := glm.transpose(object.transform.model_matrix)
		transform_matrix: vk.TransformMatrixKHR
		runtime.mem_copy(&transform_matrix, &transform, size_of(vk.TransformMatrixKHR))

		append_elem(
			&instances,
			vk.AccelerationStructureInstanceKHR {
				transform = vk.TransformMatrixKHR{mat = transmute([3][4]f32)transform_matrix},
				instanceCustomIndexAndMask = u32(i),
				instanceShaderBindingTableRecordOffsetAndFlags = 0,
				accelerationStructureReference = u64(blas_address),
			},
		)
	}

	buffer_init_with_staging_buffer(
		&scene.instance_buffer,
		device,
		raw_data(instances),
		size_of(vk.AccelerationStructureInstanceKHR),
		len(instances),
		{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
	) or_return

	instance_address := buffer_get_device_address(device^, scene.instance_buffer)

	geometry := vk.AccelerationStructureGeometryKHR {
		sType = .ACCELERATION_STRUCTURE_GEOMETRY_KHR,
		geometryType = .INSTANCES,
		geometry = {
			instances = {
				sType = .ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
				data = {deviceAddress = instance_address},
			},
		},
	}

	build_geometry_info := vk.AccelerationStructureBuildGeometryInfoKHR {
		sType         = .ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
		type          = .TOP_LEVEL,
		flags         = {.PREFER_FAST_TRACE},
		geometryCount = 1,
		pGeometries   = &geometry,
	}

	instance_count := u32(len(scene.objects))

	size_info := vk.AccelerationStructureBuildSizesInfoKHR {
		sType = .ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR,
	}
	vk.GetAccelerationStructureBuildSizesKHR(
		device.logical_device.ptr,
		.DEVICE,
		&build_geometry_info,
		&instance_count,
		&size_info,
	)

	buffer_init(
		&scene.top_level_as.buffer,
		device,
		size_info.accelerationStructureSize,
		1,
		{.ACCELERATION_STRUCTURE_STORAGE_KHR, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	) or_return

	create_info := vk.AccelerationStructureCreateInfoKHR {
		sType  = .ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
		buffer = scene.top_level_as.buffer.handle,
		size   = size_info.accelerationStructureSize,
		type   = .TOP_LEVEL,
	}

	_ = vk_check(
		vk.CreateAccelerationStructureKHR(
			device.logical_device.ptr,
			&create_info,
			nil,
			&scene.top_level_as.handler,
		),
		"Failed to create top level acceleration structure",
	)

	scratch_buffer: Buffer
	buffer_init(
		&scratch_buffer,
		device,
		size_info.buildScratchSize,
		1,
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	) or_return
	defer buffer_destroy(&scratch_buffer, device)

	scratch_address := buffer_get_device_address(device^, scratch_buffer)

	build_range_info := vk.AccelerationStructureBuildRangeInfoKHR {
		primitiveCount  = instance_count,
		primitiveOffset = 0,
		firstVertex     = 0,
		transformOffset = 0,
	}

	// Update build info and build TLAS
	build_geometry_info.mode = .BUILD
	build_geometry_info.dstAccelerationStructure = scene.top_level_as.handler
	build_geometry_info.scratchData.deviceAddress = scratch_address

	p_build_range_info: [^]vk.AccelerationStructureBuildRangeInfoKHR = &build_range_info
	vk.CmdBuildAccelerationStructuresKHR(cmd, 1, &build_geometry_info, &p_build_range_info)


	return nil
}
