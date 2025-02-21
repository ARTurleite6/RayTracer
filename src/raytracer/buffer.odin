package raytracer

import "base:runtime"
import "core:fmt"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: fmt
_ :: runtime

Uniform_Buffer_Object :: struct {
	view_proj: Mat4,
}

Buffer :: struct {
	handle:     vk.Buffer,
	allocation: vma.Allocation,
	allocator:  vma.Allocator,
	size:       vk.DeviceSize,
}

Vertex_Buffer :: Buffer
Index_Buffer :: Buffer
Uniform_Buffer :: Buffer

make_uniform_buffer :: proc(
	type: $T,
	allocator: vma.Allocator,
) -> (
	buffer: Uniform_Buffer,
	ok: bool,
) {
	assert(len(vertices) >= 0, "You must create a vertex buffer with at least three vertices")

	return make_buffer(allocator, size_of(T), {.UNIFORM_BUFFER}, .Cpu_To_Gpu)
}

make_index_buffer :: proc(
	allocator: vma.Allocator,
	vertices: []$T,
) -> (
	buffer: Vertex_Buffer,
	ok: bool,
) {
	assert(len(vertices) >= 0, "You must create a vertex buffer with at least three vertices")

	return make_buffer_with_staging(allocator, vertices, {.INDEX_BUFFER})
}

make_vertex_buffer :: proc(
	allocator: vma.Allocator,
	vertices: []$T,
) -> (
	buffer: Vertex_Buffer,
	ok: bool,
) {
	assert(len(vertices) >= 0, "You must create a vertex buffer with at least three vertices")

	return make_buffer_with_staging(allocator, vertices, {.VERTEX_BUFFER})
}

vertex_buffer_bind :: proc(
	buffer: ^Vertex_Buffer,
	cmd: Command_Buffer,
	offset: vk.DeviceSize = 0,
) {
	vk.CmdBindVertexBuffers(
		cmd.handle,
		0,
		1,
		raw_data([]vk.Buffer{buffer.handle}),
		raw_data([]vk.DeviceSize{offset}),
	)
}

make_buffer_with_staging :: proc(
	allocator: vma.Allocator,
	data: []$T,
	usage: vk.BufferUsageFlags,
) -> (
	buffer: Buffer,
	ok: bool,
) {
	staging_buffer := make_buffer_with_data(
		allocator,
		data,
		{.TRANSFER_SRC},
		.Cpu_To_Gpu,
	) or_return
	defer delete_buffer(&staging_buffer)

	buffer = make_buffer(
		allocator,
		vk.DeviceSize(size_of(T) * len(data)),
		usage | {.TRANSFER_DST},
		.Gpu_Only,
	) or_return

	buffer_copy_from(buffer, staging_buffer)

	return buffer, true
}

buffer_copy_from :: proc(
	dst: Buffer,
	src: Buffer,
	cmd_pool: ^Command_Pool,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	cmd := command_pool_allocate_primary_buffer(
		cmd_pool,
		"Transfer command buffer",
		allocator = allocator,
	) or_return

	command_buffer_begin(cmd, {.ONE_TIME_SUBMIT}) or_return

	copy_region := vk.BufferCopy {
		size = src.size,
	}

	vk.CmdCopyBuffer(cmd.handle, src.handle, dst.handle, 1, &copy_region)


	vk_check(vk.EndCommandBuffer(cmd.handle), "Error while ending command buffer") or_return
	unimplemented()
}

make_buffer_with_data :: proc(
	allocator: vma.Allocator,
	data: []$T,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
) -> (
	buffer: Buffer,
	err: vk.Result,
) {
	buffer = make_buffer(
		allocator,
		vk.DeviceSize(size_of(T) * len(data)),
		usage,
		memory_usage,
	) or_return
	buffer_upload(&buffer, data)
	return buffer, .SUCCESS
}

make_buffer :: proc(
	allocator: vma.Allocator,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
) -> (
	buffer: Buffer,
	err: vk.Result,
) {
	buffer.allocator = allocator
	buffer.size = size
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	alloc_info := vma.Allocation_Create_Info {
		usage          = memory_usage,
		required_flags = {.HOST_COHERENT, .HOST_VISIBLE},
	}

	vk_must(
		vma.create_buffer(
			allocator,
			create_info,
			alloc_info,
			&buffer.handle,
			&buffer.allocation,
			nil,
		),
		"Failed to create buffer",
	)

	return buffer, .SUCCESS
}

buffer_upload :: proc(buffer: ^Buffer, data: []$T) -> Backend_Error {
	size := size_of(T) * len(data)
	assert(u64(size) <= u64(buffer.size), "Size exceeds allocated memory")
	mapped_data: rawptr
	vk_check(
		vma.map_memory(buffer.allocator, buffer.allocation, &mapped_data),
		"Failed to map buffer",
	) or_return
	runtime.mem_copy(mapped_data, raw_data(data), size)
	vma.unmap_memory(buffer.allocator, buffer.allocation)

	return nil
}

make_staging_buffer :: proc(ctx: Context, vertices: []$T) -> (buffer: Buffer, ok: bool) {
	buffer_size := len(vertices) * size_of(T)

	create_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = buffer_size,
		usage = {.TRANSFER_SRC},
	}

	alloc_info := vma.Allocation_Create_Info {
		usage = .Cpu_To_Gpu,
		flags = {.Mapped},
	}

	vk_must(
		vma.create_buffer(
			ctx.allocator,
			create_info,
			alloc_info,
			&buffer.handle,
			&buffer.allocation,
		),
		"Failed to allocate staging buffer",
	)

	vk_must(buffer_upload_data(ctx, &buffer, vertices), "Failed to copy data")
}

delete_buffer :: proc(buffer: ^Buffer) {
	vma.destroy_buffer(buffer.allocator, buffer.handle, buffer.allocation)

	buffer.size = 0
	buffer.handle = 0
}
