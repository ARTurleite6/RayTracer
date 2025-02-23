package raytracer

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

Scene :: struct {
	// TODO
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

mesh_init :: proc(
	mesh: ^Mesh,
	device: ^Device,
	vertices: []Vertex,
	indices: []u32,
	name: string,
) -> Mesh_Error {
	mesh.name = name
	mesh.vertex_count = u32(len(vertices))

	buffer_init_with_staging_buffer(
		&mesh.vertex_buffer,
		device,
		raw_data(vertices),
		size_of(Vertex),
		len(vertices),
		{.VERTEX_BUFFER},
	) or_return

	if len(indices) > 0 {
		buffer_init_with_staging_buffer(
			&mesh.index_buffer,
			device,
			raw_data(indices),
			size_of(u32),
			len(indices),
			{.INDEX_BUFFER},
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
