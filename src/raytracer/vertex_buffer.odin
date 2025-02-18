package raytracer

import vk "vendor:vulkan"

Position :: [3]f64
Color :: [3]f64

Vertex :: struct {
	position: [3]Position,
	color:    [3]Color,
}

Vertex_Buffer :: vk.Buffer

@(require_results)
make_vertex_buffer :: proc(ctx: Context) -> (buffer: Vertex_Buffer, result: vk.Result) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size_of(Vertex),
		usage       = {.VERTEX_BUFFER},
		sharingMode = .EXCLUSIVE,
	}

	vk.CreateBuffer(ctx.device.handle, &create_info, nil, &buffer) or_return

	return
}
