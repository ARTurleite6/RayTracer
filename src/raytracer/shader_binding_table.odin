package raytracer

import "core:mem"
import "core:mem/tlsf"
import "core:slice"
import vk "vendor:vulkan"

align_up :: proc(x, align: u32) -> u32 {
	return u32(tlsf.align_up(uint(x), uint(align)))
}

Shader_Binding_Table :: struct {
	buffer:      Buffer,
	rt_pipeline: vk.Pipeline,
	rt_props:    vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	sections:    [SBT_Section_Type]SBT_Section,
	is_built:    bool,
	allocator:   mem.Allocator,
	device:      ^Device,
}

SBT_Section :: struct {
	records: [dynamic]Shader_Record,
	region:  vk.StridedDeviceAddressRegionKHR,
	offset:  u32,
}

SBT_Section_Type :: enum {
	Ray_Gen,
	Miss,
	Hit,
}

Shader_Record :: struct {
	group_index:  u32,
	inlined_data: []u8,
}

sbt_init :: proc(
	sbt: ^Shader_Binding_Table,
	device: ^Device,
	rt_pipeline: vk.Pipeline,
	rt_props: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	allocator := context.allocator,
) {
	sbt.rt_pipeline = rt_pipeline
	sbt.rt_props = rt_props
	sbt.allocator = allocator
	sbt.device = device

	for &section in sbt.sections {
		section.records = make([dynamic]Shader_Record, allocator)
	}
}

sbt_build :: proc(sbt: ^Shader_Binding_Table) -> (err: Buffer_Error) {
	// FIXME: for now lets go with this
	assert(!sbt.is_built, "Shader binding table already built")

	handle_size := sbt.rt_props.shaderGroupHandleSize
	handle_alignment := sbt.rt_props.shaderGroupHandleAlignment
	base_alignment := sbt.rt_props.shaderGroupBaseAlignment

	current_offset: u32 = 0

	for &section in sbt.sections {
		current_offset = align_up(current_offset, base_alignment)

		max_data_size: u32 = 0

		for record in section.records {
			max_data_size = max(max_data_size, u32(len(record.inlined_data)))
		}

		stride := align_up(handle_size + max_data_size, handle_alignment)

		section_size := u32(len(section.records)) * stride

		if section_size > 0 {
			section.region.stride = vk.DeviceSize(stride)
			section.region.size = vk.DeviceSize(section_size)

			current_offset += section_size
		}
	}

	buffer_size := align_up(current_offset, base_alignment)
	assert(buffer_size > 0)

	buffer_init(
		&sbt.buffer,
		sbt.device,
		vk.DeviceSize(buffer_size),
		1,
		{.SHADER_BINDING_TABLE_KHR, .SHADER_DEVICE_ADDRESS},
		.Cpu_To_Gpu,
	)

	groups_count := 0
	for section in sbt.sections {
		groups_count += len(section.records)
	}

	assert(groups_count > 0)

	handles_size := groups_count * int(handle_size)
	handles := make([]u8, handles_size, context.temp_allocator)

	vk.GetRayTracingShaderGroupHandlesKHR(
		sbt.device.logical_device.ptr,
		sbt.rt_pipeline,
		0,
		u32(groups_count),
		handles_size,
		raw_data(handles),
	)

	mapped_data := buffer_map(&sbt.buffer, sbt.device) or_return
	defer buffer_unmap(&sbt.buffer, sbt.device)

	handle_offset := 0
	for &section in sbt.sections {
		if len(section.records) == 0 do continue

		data := cast(^[]u8)mapped_data
		section_data := slice.ptr_add(data, int(section.offset))

		section.region.deviceAddress = buffer_get_device_address(sbt.device^, sbt.buffer)

		for record, i in section.records {
			record_offset := i * int(section.region.stride)
			record_data := slice.ptr_add(section_data, record_offset)

			handle_data := handles[handle_offset:][:int(handle_size)]
			handle_offset += int(handle_size)

			mem.copy(record_data, raw_data(handle_data), int(handle_size))

			if len(record.inlined_data) > 0 {
				inlined_data_ptr := slice.ptr_add(record_data, int(handle_size))
				mem.copy(inlined_data_ptr, raw_data(record.inlined_data), len(record.inlined_data))
			}
		}
	}

	sbt.is_built = true
	return nil
}

sbt_add_ray_gen_shader :: proc(sbt: ^Shader_Binding_Table, group_index: u32, data: []u8 = nil) {
	section := &sbt.sections[.Ray_Gen]
	sbt_add_shader_record(section, group_index, sbt.allocator, data)
}

sbt_add_miss_shader :: proc(sbt: ^Shader_Binding_Table, group_index: u32, data: []u8 = nil) {
	section := &sbt.sections[.Miss]
	sbt_add_shader_record(section, group_index, sbt.allocator, data)
}

sbt_add_hit_shader :: proc(sbt: ^Shader_Binding_Table, group_index: u32, data: []u8 = nil) {
	section := &sbt.sections[.Hit]
	sbt_add_shader_record(section, group_index, sbt.allocator, data)
}

sbt_add_shader_record :: proc(
	section: ^SBT_Section,
	group_index: u32,
	allocator: mem.Allocator,
	data: []u8 = nil,
) {
	record := Shader_Record {
		group_index = group_index,
	}
	if data != nil {
		record.inlined_data = make([]u8, len(data), allocator)
		copy(record.inlined_data, data)
	}

	append(&section.records, record)
}
