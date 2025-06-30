package raytracer

import "core:log"
_ :: log

import vk "vendor:vulkan"

import vma "external:odin-vma"

Buffer_Pool :: struct {
	blocks:       [dynamic]^Buffer_Block,
	block_size:   int,
	usage:        vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
	alignment:    vk.DeviceSize,
}

Buffer_Block :: struct {
	buffer: Buffer,
	offset: vk.DeviceSize,
}

Buffer_Allocation :: struct {
	buffer: Buffer,
	offset: vk.DeviceSize,
	size:   vk.DeviceSize,
}

buffer_allocation_descriptor_info :: proc(
	allocation: Buffer_Allocation,
) -> vk.DescriptorBufferInfo {
	return {buffer = allocation.buffer.handle, offset = allocation.offset, range = allocation.size}
}

buffer_allocation_update :: proc(alloc: ^Buffer_Allocation, data: rawptr, size: vk.DeviceSize) {
	buffer_map(&alloc.buffer)
	defer buffer_unmap(&alloc.buffer)
	buffer_write(&alloc.buffer, data, alloc.offset, size)
	buffer_flush(&alloc.buffer, offset = alloc.offset, size = size)
}

buffer_pool_init :: proc(
	pool: ^Buffer_Pool,
	block_size: int,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage = .Cpu_To_Gpu,
	alignment: vk.DeviceSize = 0,
	allocator := context.allocator,
) {
	// TODO: make this computated based on the type of buffer
	pool.alignment = alignment
	pool.blocks = make([dynamic]^Buffer_Block, allocator)
	pool.block_size = block_size
	pool.usage = usage
	pool.memory_usage = memory_usage
}

buffer_pool_destroy :: proc(pool: ^Buffer_Pool) {
	for b in pool.blocks {
		buffer_destroy(&b.buffer)
	}
	delete(pool.blocks)
}

buffer_pool_reset :: proc(pool: ^Buffer_Pool) {
	for b in pool.blocks {
		buffer_block_reset(b)
	}
}

buffer_block_reset :: proc(block: ^Buffer_Block) {
	// For now this is the only implementation for reseting a block
	block.offset = 0
}

@(require_results)
buffer_pool_request_buffer_block :: proc(
	pool: ^Buffer_Pool,
	ctx: ^Vulkan_Context,
	size: vk.DeviceSize,
) -> (
	block: ^Buffer_Block,
) {
	for b in pool.blocks {
		if buffer_block_can_allocate(b^, pool.alignment, size) {
			block = b
			break
		}
	}

	if block == nil {
		// allocate new block and return it
		block = new(Buffer_Block)
		// TODO: handle alignment
		buffer_init(
			&block.buffer,
			ctx,
			vk.DeviceSize(max(int(size), pool.block_size)),
			pool.usage,
			pool.memory_usage,
			alignment = pool.alignment,
		)
		append(&pool.blocks, block)
	}

	return block
}

@(require_results)
buffer_block_allocate :: proc(
	block: ^Buffer_Block,
	alignment, size: vk.DeviceSize,
) -> Buffer_Allocation {
	assert(buffer_block_can_allocate(block^, alignment, size))

	aligned := vk.DeviceSize(block.offset)
	if alignment > 0 {
		aligned = vk.DeviceSize(align_up(u32(block.offset), u32(alignment)))
	}
	block.offset = vk.DeviceSize(aligned) + size

	return {buffer = block.buffer, offset = aligned, size = vk.DeviceSize(size)}
}

@(require_results)
buffer_block_can_allocate :: proc(block: Buffer_Block, alignment, size: vk.DeviceSize) -> bool {
	assert(size > 0, "Allocation size must be greater than 0")
	aligned := vk.DeviceSize(block.offset)
	if alignment > 0 {
		aligned = vk.DeviceSize(align_up(u32(block.offset), u32(alignment)))
	}
	return aligned + size <= block.buffer.size
}

@(require_results)
buffer_pool_descriptor_info :: proc(allocation: Buffer_Allocation) -> vk.DescriptorBufferInfo {
	return {buffer = allocation.buffer.handle, range = allocation.size, offset = allocation.offset}
}
