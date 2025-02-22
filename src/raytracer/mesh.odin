package raytracer

import "core:fmt"
import "core:strings"
// import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: fmt

Position :: Vec3
Color :: Vec3

Vertex :: struct {
	position: Position,
	color:    Color,
}

VERTEX_INPUT_BINDING_DESCRIPTION := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

VERTEX_INPUT_ATTRIBUTE_DESCRIPTION := [?]vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, position)),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, color)),
	},
}

Mesh :: struct {
	name:          string,
	transform:     Mat4,
	// vertices:      []Vertex,
	vertex_count:  int,
	indices_count: int,
	vertex_buffer: Buffer,
	index_buffer:  Buffer,
	has_indices:   bool,
}

create_mesh :: proc {
	create_mesh_without_indices,
	create_mesh_with_indices,
}

create_quad :: proc(
	ctx: ^Context,
	name: string,
	transform: Mat4 = {},
	allocator := context.allocator,
) -> (
	Mesh,
	Backend_Error,
) {
	vertices := []Vertex {
		{position = {-0.5, -0.5, 0}, color = {1.0, 0.0, 0.0}},
		{position = {0.5, -0.5, 0}, color = {0.0, 1.0, 0.0}},
		{position = {0.5, 0.5, 0}, color = {0.0, 0.0, 1.0}},
		{position = {-0.5, 0.5, 0}, color = {1.0, 1.0, 1.0}},
	}

	indices := []u16{0, 1, 2, 2, 3, 0}
	return create_mesh(ctx, name, vertices, indices, transform, allocator)
}

create_mesh_with_indices :: proc(
	ctx: ^Context,
	name: string,
	vertices: []Vertex,
	indices: []u16,
	transform: Mat4 = {},
	allocator := context.allocator,
) -> (
	mesh: Mesh,
	err: Backend_Error,
) {
	mesh.name = strings.clone(name, allocator)
	mesh.vertex_buffer = create_vertex_buffer(ctx, vertices) or_return
	mesh.vertex_count = mesh.vertex_count

	mesh.has_indices = true
	mesh.indices_count = len(indices)
	mesh.index_buffer = create_index_buffer(ctx, indices) or_return
	mesh.transform = transform

	return mesh, nil
}

create_mesh_without_indices :: proc(
	mesh: ^Mesh,
	ctx: ^Context,
	name: string,
	vertices: []Vertex,
	transform: Mat4 = {},
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	mesh.name = strings.clone(name, allocator)
	mesh.vertex_buffer = create_vertex_buffer(ctx, vertices) or_return
	mesh.vertex_count = len(vertices)
	mesh.transform = transform
	return nil
}

mesh_bind :: proc(mesh: Mesh, cmd: Command_Buffer) {
	vertex_buffer_bind(mesh.vertex_buffer, cmd)

	if mesh.has_indices {
		index_buffer_bind(mesh.index_buffer, cmd)
	}
}

mesh_draw :: proc(mesh: Mesh, cmd: Command_Buffer) {
	if mesh.has_indices {
		vk.CmdDrawIndexed(cmd.handle, u32(mesh.indices_count), 1, 0, 0, 0)
	} else {
		vk.CmdDraw(cmd.handle, u32(mesh.vertex_count), 1, 0, 0)
	}
}

mesh_destroy :: proc(mesh: ^Mesh) {
	delete(mesh.name)
	buffer_destroy(&mesh.vertex_buffer)

	if mesh.has_indices {
		buffer_destroy(&mesh.vertex_buffer)
	}
}
