package raytracer

import "base:runtime"
import "core:fmt"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: runtime
_ :: fmt

Buffer :: struct {
	handle:         vk.Buffer,
	allocation:     vma.Allocation,
	size:           vk.DeviceSize,
	instance_size:  vk.DeviceSize,
	instance_count: int,
	mapped_data:    rawptr,
	usage:          vk.BufferUsageFlags,
}

Buffer_Error :: enum {
	None = 0,
	Creation_Failed,
	Mapping_Failed,
	Invalid_Size,
}

buffer_init :: proc(
	buffer: ^Buffer,
	device: ^Device,
	instance_size: vk.DeviceSize,
	instance_count: int,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
	alignment: vk.DeviceSize = 0,
) -> Buffer_Error {
	size := instance_size * vk.DeviceSize(instance_count)
	if size <= 0 {
		return .Invalid_Size
	}
	buffer.size = size // TODO: this should be handled better in the future
	buffer.instance_size = instance_size
	buffer.instance_count = instance_count
	buffer.usage = usage

	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
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
	}

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

	return .None
}

buffer_init_with_staging_buffer :: proc(
	buffer: ^Buffer,
	device: ^Device,
	data: rawptr,
	instance_size: vk.DeviceSize,
	instance_count: int,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage = .Gpu_Only,
) -> (
	err: Buffer_Error,
) {
	buffer_init(
		buffer,
		device,
		instance_size,
		instance_count,
		{.TRANSFER_DST} | usage,
		memory_usage,
	) or_return

	staging_buffer: Buffer
	buffer_init(
		&staging_buffer,
		device,
		instance_size,
		instance_count,
		{.TRANSFER_SRC} | usage,
		.Cpu_To_Gpu,
	) or_return
	defer buffer_destroy(&staging_buffer, device)

	buffer_map(&staging_buffer, device) or_return
	buffer_write(&staging_buffer, data)

	device_copy_buffer(device, staging_buffer.handle, buffer.handle, staging_buffer.size)
	return nil
}

buffer_destroy :: proc(buffer: ^Buffer, device: ^Device) {
	if buffer.mapped_data != nil {
		vma.unmap_memory(device.allocator, buffer.allocation)
	}

	if buffer.handle != 0 {
		vma.destroy_buffer(device.allocator, buffer.handle, buffer.allocation)
	}
	buffer^ = {}
}

buffer_map :: proc(buffer: ^Buffer, device: ^Device) -> (rawptr, Buffer_Error) {
	if result := vk_check(
		vma.map_memory(device.allocator, buffer.allocation, &buffer.mapped_data),
		"Failed to map buffer",
	); result != .SUCCESS {
		return nil, .Mapping_Failed
	}

	return buffer.mapped_data, .None
}

buffer_unmap :: proc(buffer: ^Buffer, device: ^Device) {
	vma.unmap_memory(device.allocator, buffer.allocation)
}

buffer_write :: proc(
	buffer: ^Buffer,
	data: rawptr,
	size := vk.WHOLE_SIZE,
	offset: vk.DeviceSize = 0,
) {
	assert(buffer.mapped_data != nil, "Buffer must be mapped before writing to it")

	if size == vk.WHOLE_SIZE {
		runtime.mem_copy(buffer.mapped_data, data, int(buffer.size))
	} else {
		runtime.mem_copy(buffer.mapped_data, data, int(size))
	}
}

buffer_flush :: proc(buffer: ^Buffer, device: Device, size := vk.WHOLE_SIZE) {
	_ = vk_check(
		vma.flush_allocation(device.allocator, buffer.allocation, 0, buffer.size),
		"Failed to upload data to uniform buffer",
	)
}

buffer_get_device_address :: proc(buffer: Buffer, device: Device) -> vk.DeviceAddress {
	address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.handle,
	}

	return vk.GetBufferDeviceAddress(device.logical_device.ptr, &address_info)
}
