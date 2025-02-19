package raytracer

import "base:runtime"
import vk "vendor:vulkan"

Buffer_Kind :: enum {
	Vertex,
	Uniform,
}

Uniform_Buffer_Object :: struct {
	view_proj: Mat4,
}

Buffer :: struct {
	handle:        vk.Buffer,
	memory:        vk.DeviceMemory,
	size:          vk.DeviceSize,
	kind:          Buffer_Kind,
	mapped_memory: rawptr,
}

make_buffer_with_data :: proc(
	ctx: Context,
	data: []$T,
	kind: Buffer_Kind,
) -> (
	buffer: Buffer,
	result: vk.Result,
) {
	buffer = make_buffer(ctx, size_of(T) * len(data), kind) or_return
	buffer_upload_data(ctx, &buffer, data) or_return

	return
}

@(require_results)
make_buffer :: proc(
	ctx: Context,
	size: int,
	kind: Buffer_Kind,
) -> (
	buffer: Buffer,
	result: vk.Result,
) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = vk.DeviceSize(size),
		usage       = buffer_kind_to_usage_flags(kind),
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

buffer_upload_data :: proc(ctx: Context, buffer: ^Buffer, data: []$T) -> (result: vk.Result) {
	data_size := vk.DeviceSize(size_of(T) * len(data))
	assert(data_size <= buffer.size, "Trying to upload more data than buffer size")

	mapped_data: rawptr
	buffer_map(ctx, buffer, &mapped_data) or_return
	defer buffer_unmap(ctx, buffer, &mapped_data)

	runtime.mem_copy(mapped_data, raw_data(data), int(data_size))
	return
}

@(require_results)
buffer_map :: proc(ctx: Context, buffer: ^Buffer, mapped_data: ^rawptr) -> (result: vk.Result) {
	assert(mapped_data != nil)
	return vk.MapMemory(ctx.device.handle, buffer.memory, 0, buffer.size, {}, mapped_data)
}

buffer_unmap :: proc(ctx: Context, buffer: ^Buffer, mapped_data: ^rawptr) {
	assert(mapped_data != nil)
	vk.UnmapMemory(ctx.device.handle, buffer.memory)
}

delete_buffer :: proc(ctx: Context, buffer: Buffer) {
	vk.DestroyBuffer(ctx.device.handle, buffer.handle, nil)
	vk.FreeMemory(ctx.device.handle, buffer.memory, nil)
}

@(private = "file")
buffer_kind_to_usage_flags :: proc(kind: Buffer_Kind) -> vk.BufferUsageFlags {
	switch kind {
	case .Vertex:
		return {.VERTEX_BUFFER}
	case .Uniform:
		return {.UNIFORM_BUFFER}
	}

	return {}
}
