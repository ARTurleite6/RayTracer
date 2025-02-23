package raytracer

import "base:runtime"
import "core:fmt"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: runtime
_ :: fmt

// TODO: Implement a distinct type for each vertex type (Vertex, Index, Uniform)
Buffer :: struct {
	handle:         vk.Buffer,
	allocator:      vma.Allocator,
	allocation:     vma.Allocation,
	size:           vk.DeviceSize,
	instance_size:  vk.DeviceSize,
	instance_count: u32,
	alignment_size: vk.DeviceSize,
	mapped_memory:  rawptr,
	mapped:         bool,
}

create_index_buffer :: proc(
	ctx: ^Context,
	indices: []u16,
	allocator := context.allocator,
) -> (
	index_buffer: Buffer,
	err: Backend_Error,
) {
	index_count := u32(len(indices))
	assert(index_count >= 3, "Indices count must be at least 3")

	index_size := size_of(16)

	return _create_buffer_with_staging(
		ctx,
		vk.DeviceSize(index_size),
		index_count,
		{.INDEX_BUFFER},
		raw_data(indices),
	)
}

create_vertex_buffer :: proc(
	ctx: ^Context,
	vertices: []Vertex,
	allocator := context.allocator,
) -> (
	vertex_buffer: Buffer,
	err: Backend_Error,
) {
	vertex_count := u32(len(vertices))
	assert(vertex_count >= 3, "Vertex count must be at least 3")

	vertex_size := size_of(Vertex)

	return _create_buffer_with_staging(
		ctx,
		vk.DeviceSize(vertex_size),
		vertex_count,
		{.VERTEX_BUFFER},
		raw_data(vertices),
	)
}

index_buffer_bind :: proc(buffer: Buffer, cmd: Command_Buffer, offset: vk.DeviceSize = 0) {
	vk.CmdBindIndexBuffer(cmd.handle, buffer.handle, offset, .UINT16)
}

vertex_buffer_bind :: proc(buffer: Buffer, cmd: Command_Buffer, offset: vk.DeviceSize = 0) {
	offset := offset
	buffer_handle := buffer.handle
	vk.CmdBindVertexBuffers(
		cmd.handle,
		0,
		1,
		raw_data([]vk.Buffer{buffer_handle}),
		raw_data([]vk.DeviceSize{offset}),
	)
}

buffer_flush :: proc(
	buffer: Buffer,
	size: vk.DeviceSize,
	offset: vk.DeviceSize = 0,
) -> Backend_Error {
	return vma.flush_allocation(buffer.allocator, buffer.allocation, offset, size)
}

buffer_flush_index :: proc(buffer: Buffer, index: int) -> Backend_Error {
	return buffer_flush(
		buffer,
		buffer.alignment_size,
		vk.DeviceSize(index) * buffer.alignment_size,
	)
}

buffer_copy_from :: proc(
	ctx: ^Context,
	dst: Buffer,
	src: Buffer,
	size: vk.DeviceSize,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	cmd := command_pool_allocate_primary_buffer(
		&ctx.transfer_command_pool,
		"Transfer command buffer",
		allocator = allocator,
	) or_return

	command_buffer_begin(cmd, {.ONE_TIME_SUBMIT}) or_return

	copy_region := vk.BufferCopy {
		size = size,
	}

	vk.CmdCopyBuffer(cmd.handle, src.handle, dst.handle, 1, &copy_region)

	vk_check(vk.EndCommandBuffer(cmd.handle), "Error while ending command buffer") or_return

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd.handle,
	}

	vk_check(
		vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, 0),
		"Failed to submit transfer",
	) or_return
	vk_check(vk.QueueWaitIdle(ctx.graphics_queue), "Failed to wait for transfer") or_return

	vk.FreeCommandBuffers(
		ctx.transfer_command_pool.device.ptr,
		ctx.transfer_command_pool.handle,
		1,
		&cmd.handle,
	)

	return nil
}


create_buffer :: proc(
	ctx: Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
	min_offset_alignment: vk.DeviceSize = 1,
) -> (
	buffer: Buffer,
	err: vk.Result,
) {
	buffer.instance_count = instance_count
	buffer.instance_size = instance_size
	buffer.alignment_size = get_alignment(instance_size, min_offset_alignment)
	buffer.size = buffer.alignment_size * vk.DeviceSize(instance_count)
	buffer.allocator = ctx.allocator

	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = buffer.size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	alloc_info := vma.Allocation_Create_Info {
		usage = memory_usage,
	}

	vk_check(
		vma.create_buffer(
			ctx.allocator,
			create_info,
			alloc_info,
			&buffer.handle,
			&buffer.allocation,
			nil,
		),
		"Failed to create buffer",
	) or_return


	return buffer, .SUCCESS
}

buffer_map :: proc(buffer: ^Buffer) -> Backend_Error {
	assert(!buffer.mapped, "Buffer was already mapped")
	vk_check(
		vma.map_memory(buffer.allocator, buffer.allocation, &buffer.mapped_memory),
		"Failed to map buffer",
	) or_return
	buffer.mapped = true
	return nil
}

buffer_unmap :: proc(buffer: ^Buffer) {
	assert(buffer.mapped, "Buffer was not previously mapped")
	vma.unmap_memory(buffer.allocator, buffer.allocation)
	buffer.mapped = false
}

buffer_write :: proc(
	buffer: Buffer,
	data: rawptr,
	size: u64 = vk.WHOLE_SIZE,
	offset: vk.DeviceSize = 0,
) {
	if size == vk.WHOLE_SIZE {
		runtime.mem_copy(buffer.mapped_memory, data, int(buffer.size))
	} else {
		runtime.mem_copy(rawptr(uintptr(buffer.mapped_memory) + uintptr(offset)), data, int(size))
	}
}

buffer_write_to_index :: proc(buffer: Buffer, data: rawptr, index: int) {
	buffer_write(
		buffer,
		data,
		u64(buffer.instance_size),
		vk.DeviceSize(index) * buffer.alignment_size,
	)
}

buffer_destroy :: proc(buffer: ^Buffer) {
	if buffer.mapped {
		buffer_unmap(buffer)
	}
	vma.destroy_buffer(buffer.allocator, buffer.handle, buffer.allocation)
	buffer^ = {}
}

@(private = "file")
_create_buffer_with_staging :: proc(
	ctx: ^Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	buffer_usage: vk.BufferUsageFlags,
	data: rawptr,
	allocator := context.allocator,
) -> (
	buffer: Buffer,
	err: Backend_Error,
) {
	staging_buffer := create_buffer(
		ctx^,
		instance_size,
		instance_count,
		{.TRANSFER_SRC},
		.Cpu_To_Gpu,
	) or_return
	defer buffer_destroy(&staging_buffer)

	buffer_map(&staging_buffer) or_return
	buffer_write(staging_buffer, data)
	buffer_unmap(&staging_buffer)

	buffer = create_buffer(
		ctx^,
		vk.DeviceSize(instance_size),
		instance_count,
		buffer_usage | {.TRANSFER_DST},
		.Gpu_Only,
	) or_return

	buffer_size := u32(instance_size) * instance_count
	buffer_copy_from(ctx, buffer, staging_buffer, vk.DeviceSize(buffer_size), allocator) or_return
	return buffer, nil
}

@(private = "file")
get_alignment :: proc(
	instance_size: vk.DeviceSize,
	min_offset_alignment: vk.DeviceSize,
) -> vk.DeviceSize {
	if min_offset_alignment > 0 {
		return (instance_size + min_offset_alignment - 1) & ~(min_offset_alignment - 1)
	}

	return instance_size
}
