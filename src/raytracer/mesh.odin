package raytracer

import vma "external:odin-vma"
import vk "vendor:vulkan"

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
	vertices:      []Vertex,
	vertex_buffer: Buffer,
	index_buffer:  Buffer,
	allocator:     vma.Allocator,
}
