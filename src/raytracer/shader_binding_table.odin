package raytracer

import "base:runtime"
import "core:mem"

import vma "external:odin-vma"
import vk "vendor:vulkan"

Shader_Region :: enum {
	Ray_Gen,
	Miss,
	Hit,
	Callable,
}


Shader_Binding_Table :: struct {
	buffer:       Buffer,
	regions:      [Shader_Region]vk.StridedDeviceAddressRegionKHR,
	groups:       [dynamic]vk.RayTracingShaderGroupCreateInfoKHR,
	group_counts: [Shader_Region]u64,
}

shader_binding_table_destroy :: proc(self: ^Shader_Binding_Table) {
	buffer_destroy(&self.buffer)
	delete(self.groups)
}

shader_binding_table_build :: proc(
	self: ^Shader_Binding_Table,
	ctx: ^Vulkan_Context,
	pipeline: Pipeline,
	props: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	device := vulkan_get_device_handle(ctx)
	handle_size := props.shaderGroupHandleSize
	handle_alignment := props.shaderGroupHandleAlignment
	base_alignment := props.shaderGroupBaseAlignment
	aligned_handle_size := align_up(handle_size, handle_alignment)

	aligned_group_size := align_up(aligned_handle_size, base_alignment)

	group_count: u64
	for group in self.group_counts {
		group_count += group
	}

	sbt_size := group_count * u64(aligned_group_size)
	buffer := &self.buffer

	sbt_buffer_usage_flags: vk.BufferUsageFlags = {
		.SHADER_BINDING_TABLE_KHR,
		.TRANSFER_SRC,
		.SHADER_DEVICE_ADDRESS,
	}
	sbt_memory_usage: vma.Memory_Usage = .Cpu_To_Gpu

	buffer_init(
		buffer,
		ctx,
		vk.DeviceSize(sbt_size),
		sbt_buffer_usage_flags,
		sbt_memory_usage,
		alignment = vk.DeviceSize(base_alignment),
	)

	shader_handle_storage := make([]u8, sbt_size, context.temp_allocator)
	_ = vk_check(
		vk.GetRayTracingShaderGroupHandlesKHR(
			device,
			pipeline.handle,
			0,
			u32(group_count),
			int(sbt_size),
			raw_data(shader_handle_storage),
		),
		"Failed to get shader handles",
	)

	data: rawptr
	data, _ = buffer_map(buffer)
	defer buffer_unmap(buffer)

	for i in 0 ..< group_count {
		dst_offset := uintptr(u64(aligned_group_size) * i)
		src_offset := uintptr(u64(aligned_handle_size) * i)
		src := rawptr(uintptr(raw_data(shader_handle_storage)) + src_offset)
		dest := rawptr(uintptr(data) + dst_offset)
		mem.copy(dest, src, int(handle_size))
	}

	base_address := buffer_get_device_address(buffer^)
	stride := u64(aligned_group_size)

	raygen_offset := u64(base_address)
	miss_offset := vk.DeviceAddress(raygen_offset + self.group_counts[.Ray_Gen] * stride)
	hit_offset := vk.DeviceAddress(u64(miss_offset) + self.group_counts[.Miss] * stride)
	call_offset := vk.DeviceAddress(u64(hit_offset) + self.group_counts[.Hit] * stride)

	self.regions[.Ray_Gen] = {
		deviceAddress = vk.DeviceAddress(raygen_offset),
		stride        = vk.DeviceSize(stride),
		size          = vk.DeviceSize(stride * self.group_counts[.Ray_Gen]),
	}

	self.regions[.Miss] = {
		deviceAddress = miss_offset,
		stride        = vk.DeviceSize(stride),
		size          = vk.DeviceSize(stride * self.group_counts[.Miss]),
	}

	self.regions[.Hit] = {
		deviceAddress = hit_offset,
		stride        = vk.DeviceSize(stride),
		size          = vk.DeviceSize(stride * self.group_counts[.Hit]),
	}

	self.regions[.Callable] = {
		deviceAddress = call_offset,
		stride        = vk.DeviceSize(stride),
		size          = vk.DeviceSize(stride * self.group_counts[.Callable]),
	}
}

shader_binding_table_add_group :: proc(
	self: ^Shader_Binding_Table,
	group: vk.RayTracingShaderGroupCreateInfoKHR,
	type: Shader_Region,
) {
	append(&self.groups, group)
	self.group_counts[type] += 1
}
