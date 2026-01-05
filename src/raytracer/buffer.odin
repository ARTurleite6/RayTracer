package raytracer

import "base:runtime"
import "core:fmt"
import "core:log"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: runtime
_ :: log
_ :: fmt

Buffer :: struct {
	handle:      vk.Buffer,
	allocation:  vma.Allocation,
	size:        vk.DeviceSize,
	mapped_data: rawptr,
	usage:       vk.BufferUsageFlags,
	ctx:         ^Vulkan_Context,
}

Buffer_Error :: enum {
	None = 0,
	Creation_Failed,
	Mapping_Failed,
	Invalid_Size,
}

@(require_results)
buffer_init :: proc(
	buffer: ^Buffer,
	ctx: ^Vulkan_Context,
	size: u64,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
	alignment: vk.DeviceSize = 0,
) -> Buffer_Error {
	buffer^ = {}
	if size == 0 {
		return .Invalid_Size
	}
	buffer.ctx = ctx
	buffer.size = vk.DeviceSize(size)
	buffer.usage = usage | {.TRANSFER_SRC, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS}

	device := buffer.ctx.device

	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = vk.DeviceSize(size),
		usage       = buffer.usage,
		sharingMode = .EXCLUSIVE,
	}

	alloc_create_info := vma.Allocation_Create_Info {
		usage = memory_usage,
	}

	if alignment > 0 {
		if vk_check(
			   vma.create_buffer_with_alignment(
				   device.allocator,
				   buffer_info,
				   alloc_create_info,
				   alignment,
				   &buffer.handle,
				   &buffer.allocation,
				   nil,
			   ),
			   "Failed to create aligned buffer",
		   ) !=
		   .SUCCESS {
			return .Creation_Failed
		}
	} else {
		if vk_check(
			   vma.create_buffer(
				   device.allocator,
				   buffer_info,
				   alloc_create_info,
				   &buffer.handle,
				   &buffer.allocation,
				   nil,
			   ),
			   "Failed to create buffer",
		   ) !=
		   .SUCCESS {
			return .Creation_Failed
		}
	}

	return .None
}

buffer_init_with_staging_buffer :: proc(
	buffer: ^Buffer,
	ctx: ^Vulkan_Context,
	data: rawptr,
	size: u64,
	usage: vk.BufferUsageFlags,
	alignment := vk.DeviceSize(0),
	memory_usage: vma.Memory_Usage = .Gpu_Only,
) -> (
	err: Buffer_Error,
) {
	buffer.ctx = ctx
	device := buffer.ctx.device
	buffer_init(
		buffer,
		buffer.ctx,
		size,
		{.TRANSFER_DST} | usage,
		memory_usage,
		alignment = alignment,
	) or_return

	staging_buffer := vulkan_context_request_staging_buffer(ctx, vk.DeviceSize(size))

	buffer_allocation_update(&staging_buffer, data, vk.DeviceSize(size))

	device_copy_buffer(
		device,
		staging_buffer.buffer.handle,
		buffer.handle,
		staging_buffer.size,
		src_offset = staging_buffer.offset,
		dst_offset = 0,
	)
	return nil
}

buffer_destroy :: proc(buffer: ^Buffer) {
	if buffer.mapped_data != nil {
		vma.unmap_memory(buffer.ctx.device.allocator, buffer.allocation)
	}

	if buffer.handle != 0 {
		vma.destroy_buffer(buffer.ctx.device.allocator, buffer.handle, buffer.allocation)
	}
}

buffer_descriptor_info :: proc(buffer: Buffer) -> vk.DescriptorBufferInfo {
	return {buffer = buffer.handle, offset = 0, range = buffer.size}
}

buffer_map :: proc(buffer: ^Buffer) -> (rawptr, Buffer_Error) {
	if buffer.handle == 0 {
		return {}, .Mapping_Failed
	}
	if result := vk_check(
		vma.map_memory(buffer.ctx.device.allocator, buffer.allocation, &buffer.mapped_data),
		"Failed to map buffer",
	); result != .SUCCESS {
		return nil, .Mapping_Failed
	}

	return buffer.mapped_data, .None
}

buffer_unmap :: proc(buffer: ^Buffer) {
	if buffer.handle == 0 {
		return
	}
	vma.unmap_memory(buffer.ctx.device.allocator, buffer.allocation)
}

buffer_write :: proc {
	buffer_write_poly,
	buffer_write_rawptr,
}

buffer_write_poly :: proc(buffer: ^Buffer, data: ^$T, offset: vk.DeviceSize = 0) {
	buffer_write_rawptr(buffer, data, offset, size_of(T))
}

buffer_write_rawptr :: proc(buffer: ^Buffer, data: rawptr, offset, size: vk.DeviceSize) {
	if buffer.handle == 0 || buffer.allocation == nil {
		return
	}
	assert(buffer.mapped_data != nil)
	dst_ptr := rawptr(uintptr(buffer.mapped_data) + uintptr(offset))

	if size == vk.DeviceSize(vk.WHOLE_SIZE) {
		runtime.mem_copy(dst_ptr, data, int(buffer.size - offset))
	} else {
		runtime.mem_copy(dst_ptr, data, int(size))
	}
}

buffer_flush :: proc(buffer: ^Buffer, offset, size: vk.DeviceSize) {
	if buffer.handle == 0 {
		return
	}
	if size == vk.DeviceSize(vk.WHOLE_SIZE) {
		_ = vk_check(
			vma.flush_allocation(
				buffer.ctx.device.allocator,
				buffer.allocation,
				offset,
				buffer.size - offset,
			),
			"Failed to upload data to uniform buffer",
		)
	} else {
		_ = vk_check(
			vma.flush_allocation(buffer.ctx.device.allocator, buffer.allocation, offset, size),
			"Failed to upload data to uniform buffer",
		)
	}
}

buffer_get_device_address :: proc(buffer: Buffer) -> vk.DeviceAddress {
	address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.handle,
	}

	return vk.GetBufferDeviceAddress(vulkan_get_device_handle(buffer.ctx), &address_info)
}

