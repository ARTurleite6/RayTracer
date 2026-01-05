package raytracer

import vk "vendor:vulkan"

Storage_Buffer_Set :: struct {
	buffers: []Buffer,
}

make_storage_buffer_set :: proc(
	ctx: ^Vulkan_Context,
	size: u64,
	frames_in_flight: int,
	allocator := context.allocator,
) -> (
	bs: Storage_Buffer_Set,
) {
	bs.buffers = make([]Buffer, frames_in_flight, allocator)

	for &b in bs.buffers {
		buffer_init(
			&b,
			ctx,
			size,
			{.STORAGE_BUFFER},
			.Cpu_To_Gpu,
			ctx.device.physical_device.properties.limits.minStorageBufferOffsetAlignment,
		) or_break
	}

	return bs
}

storage_buffer_set_get :: proc(bs: ^Storage_Buffer_Set, current_frame: int) -> ^Buffer {
	return &bs.buffers[current_frame]
}

storage_buffer_set_destroy :: proc(
	ctx: ^Vulkan_Context,
	bs: ^Storage_Buffer_Set,
	allocator := context.allocator,
) {
	for &b in bs.buffers {
		buffer_destroy(&b)
	}
	delete(bs.buffers, allocator)
}

storage_buffer_set_write :: proc(bs: ^Storage_Buffer_Set, data: ^$T, offset: vk.DeviceSize = 0) {
	for &buffer in bs.buffers {
		buffer_write(&buffer, data, offset = offset)
	}
}

