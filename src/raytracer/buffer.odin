package raytracer

import "base:runtime"
import "core:fmt"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: fmt

Buffer_Kind :: enum {
	Vertex,
	Uniform,
}

Uniform_Buffer_Object :: struct {
	view_proj: Mat4,
}

Buffer :: struct {
	handle:     vk.Buffer,
	allocation: vma.Allocation,
	size:       vk.DeviceSize,
	kind:       Buffer_Kind,
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
		sType = .BUFFER_CREATE_INFO,
		size  = vk.DeviceSize(size),
		usage = buffer_kind_to_usage_flags(kind),
	}

	alloc_info := vma.Allocation_Create_Info {
		usage = .Auto,
	}

	vma.create_buffer(
		ctx.allocator,
		create_info,
		alloc_info,
		&buffer.handle,
		&buffer.allocation,
		nil,
	)

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
	return vma.map_memory(ctx.allocator, buffer.allocation, mapped_data)
}

buffer_unmap :: proc(ctx: Context, buffer: ^Buffer, mapped_data: ^rawptr) {
	assert(mapped_data != nil)
	vma.unmap_memory(ctx.allocator, buffer.allocation)
}

delete_buffer :: proc(ctx: Context, buffer: Buffer) {
	vma.destroy_buffer(ctx.allocator, buffer.handle, buffer.allocation)
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
