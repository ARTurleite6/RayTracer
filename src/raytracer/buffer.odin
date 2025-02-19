package raytracer

import "base:runtime"
import vk "vendor:vulkan"

Buffer_Kind :: enum {
	Vertex,
}

Buffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
	size:   vk.DeviceSize,
	kind:   Buffer_Kind,
}

make_vertex_buffer_with_data :: proc(
	ctx: Context,
	data: []$T,
) -> (
	buffer: Buffer,
	result: vk.Result,
) {
	buffer = make_vertex_buffer(ctx, size_of(T) * len(data)) or_return
	buffer_upload_data(ctx, buffer, data) or_return

	return
}

@(require_results)
make_vertex_buffer :: proc(ctx: Context, size: int) -> (buffer: Buffer, result: vk.Result) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = vk.DeviceSize(size),
		usage       = {.VERTEX_BUFFER},
		sharingMode = .EXCLUSIVE,
	}

	vk.CreateBuffer(ctx.device.handle, &create_info, nil, &buffer.handle) or_return

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device.handle, buffer.handle, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = find_memory_type(
			ctx,
			mem_requirements.memoryTypeBits,
			{.HOST_VISIBLE, .HOST_COHERENT},
		),
	}

	vk.AllocateMemory(ctx.device.handle, &alloc_info, nil, &buffer.memory) or_return

	vk.BindBufferMemory(ctx.device.handle, buffer.handle, buffer.memory, 0) or_return

	buffer.size = vk.DeviceSize(size)
	buffer.kind = .Vertex
	return
}

buffer_upload_data :: proc(ctx: Context, buffer: Buffer, data: []$T) -> (result: vk.Result) {
	data_size := vk.DeviceSize(size_of(Vertex) * len(data))
	assert(data_size <= buffer.size, "Trying to upload more data than buffer size")

	mapped_data: rawptr
	vk.MapMemory(ctx.device.handle, buffer.memory, 0, data_size, {}, &mapped_data) or_return
	defer vk.UnmapMemory(ctx.device.handle, buffer.memory)

	runtime.mem_copy(mapped_data, raw_data(data), int(data_size))
	return
}

delete_buffer :: proc(ctx: Context, buffer: Buffer) {
	vk.DestroyBuffer(ctx.device.handle, buffer.handle, nil)
	vk.FreeMemory(ctx.device.handle, buffer.memory, nil)
}
