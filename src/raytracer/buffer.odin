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
	ctx:            ^Vulkan_Context,
}

Buffer_Error :: enum {
	None = 0,
	Creation_Failed,
	Mapping_Failed,
	Invalid_Size,
}

buffer_init :: proc(
	buffer: ^Buffer,
	ctx: ^Vulkan_Context,
	instance_size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
	instance_count := 1,
	alignment: vk.DeviceSize = 0,
) -> Buffer_Error {
	size := instance_size * vk.DeviceSize(instance_count)
	if size <= 0 {
		return .Invalid_Size
	}
	buffer.ctx = ctx
	buffer.size = size // TODO: this should be handled better in the future
	buffer.instance_size = instance_size
	buffer.instance_count = instance_count
	buffer.usage = usage

	device := buffer.ctx.device

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
	ctx: ^Vulkan_Context,
	data: rawptr,
	instance_size: vk.DeviceSize,
	instance_count: int,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage = .Gpu_Only,
) -> (
	err: Buffer_Error,
) {
	buffer.ctx = ctx
	device := buffer.ctx.device
	buffer_init(
		buffer,
		buffer.ctx,
		instance_size,
		{.TRANSFER_DST} | usage,
		memory_usage,
		instance_count = instance_count,
	) or_return

	staging_buffer: Buffer
	buffer_init(
		&staging_buffer,
		buffer.ctx,
		instance_size,
		{.TRANSFER_SRC} | usage,
		.Cpu_To_Gpu,
		instance_count = instance_count,
	) or_return
	defer buffer_destroy(&staging_buffer)

	buffer_map(&staging_buffer) or_return
	buffer_write(&staging_buffer, data)

	device_copy_buffer(device, staging_buffer.handle, buffer.handle, staging_buffer.size)
	return nil
}

buffer_destroy :: proc(buffer: ^Buffer) {
	if buffer.mapped_data != nil {
		vma.unmap_memory(buffer.ctx.device.allocator, buffer.allocation)
	}

	if buffer.handle != 0 {
		vma.destroy_buffer(buffer.ctx.device.allocator, buffer.handle, buffer.allocation)
	}
	buffer^ = {}
}

buffer_descriptor_info :: proc(buffer: Buffer) -> vk.DescriptorBufferInfo {
	return {buffer = buffer.handle, offset = 0, range = buffer.size}
}

buffer_map :: proc(buffer: ^Buffer) -> (rawptr, Buffer_Error) {
	if result := vk_check(
		vma.map_memory(buffer.ctx.device.allocator, buffer.allocation, &buffer.mapped_data),
		"Failed to map buffer",
	); result != .SUCCESS {
		return nil, .Mapping_Failed
	}

	return buffer.mapped_data, .None
}

buffer_unmap :: proc(buffer: ^Buffer) {
	vma.unmap_memory(buffer.ctx.device.allocator, buffer.allocation)
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

buffer_update_region :: proc(
	buffer: ^Buffer,
	data: rawptr,
	size: vk.DeviceSize,
	offset: vk.DeviceSize = 0,
) {

	staging_buffer: Buffer
	buffer_init(&staging_buffer, buffer.ctx, size, {.TRANSFER_SRC}, .Cpu_To_Gpu)
	defer buffer_destroy(&staging_buffer)

	// Map, copy data, and unmap
	buffer_map(&staging_buffer)
	buffer_write(&staging_buffer, data)

	// Copy from staging buffer to destination buffer
	device := buffer.ctx.device
	cmd := device_begin_single_time_commands(device, device.command_pool)
	defer device_end_single_time_commands(device, device.command_pool, cmd)

	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = offset,
		size      = size,
	}

	vk.CmdCopyBuffer(cmd, staging_buffer.handle, buffer.handle, 1, &copy_region)
}

buffer_flush :: proc(buffer: ^Buffer, size := vk.WHOLE_SIZE) {
	_ = vk_check(
		vma.flush_allocation(buffer.ctx.device.allocator, buffer.allocation, 0, buffer.size),
		"Failed to upload data to uniform buffer",
	)
}

buffer_get_device_address :: proc(buffer: Buffer) -> vk.DeviceAddress {
	address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.handle,
	}

	return vk.GetBufferDeviceAddress(vulkan_get_device_handle(buffer.ctx), &address_info)
}
