package raytracer

import "core:hash/xxhash"
import "core:log"
import "core:mem"
import "core:slice"

import vk "vendor:vulkan"

Binding_Map :: struct($T: typeid) {
	inner:     map[u32]map[u32]T,
	// TODO: maybe in the future this could be an arena allocator
	allocator: mem.Allocator,
}

Descriptor_Set2 :: struct {
	handle:                       vk.DescriptorSet,
	descriptor_set_layout:        ^Descriptor_Set_Layout2,
	descriptor_pool:              ^Descriptor_Pool,
	buffer_infos:                 Binding_Map(vk.DescriptorBufferInfo),
	image_infos:                  Binding_Map(vk.DescriptorImageInfo),
	acceleration_structure_infos: Binding_Map(vk.WriteDescriptorSetAccelerationStructureKHR),
	write_descriptor_sets:        [dynamic]vk.WriteDescriptorSet,
	updated_bindings:             map[u32]u32,
}

make_binding_map :: proc($T: typeid, allocator := context.allocator) -> Binding_Map(T) {
	return {inner = make(map[u32]map[u32]T, allocator = allocator), allocator = allocator}
}

binding_map_clone :: proc(
	b: Binding_Map($T),
	allocator := context.allocator,
) -> (
	dst: Binding_Map(T),
) {
	context.allocator = allocator
	dst = make_binding_map(T)
	for ko, vo in b.inner {
		for ki, vi in vo {
			binding_map_set_binding(&dst, ko, vi, ki)
		}
	}
	return dst
}

binding_map_destroy :: proc(b: ^Binding_Map($T)) {
	context.allocator = b.allocator
	for _, v in b.inner {
		delete(v)
	}
	delete(b.inner)
}

binding_map_set_binding :: proc(
	b: ^Binding_Map($T),
	binding: u32,
	value: T,
	array_element := u32(0),
) {
	_, value_ptr, just_inserted, _ := map_entry(&b.inner, binding)
	if just_inserted {
		value_ptr^ = make(map[u32]T, b.allocator)
	}
	value_ptr[array_element] = value
}

descriptor_set_init :: proc(
	set: ^Descriptor_Set2,
	ctx: ^Vulkan_Context,
	layout: ^Descriptor_Set_Layout2,
	pool: ^Descriptor_Pool,
	buffer_infos: Binding_Map(vk.DescriptorBufferInfo),
	image_infos: Binding_Map(vk.DescriptorImageInfo),
	acceleration_structure_infos: Binding_Map(vk.WriteDescriptorSetAccelerationStructureKHR),
) -> (
	err: vk.Result,
) {
	set.descriptor_set_layout = layout
	set.descriptor_pool = pool
	set.buffer_infos = binding_map_clone(buffer_infos)
	set.image_infos = binding_map_clone(image_infos)
	set.acceleration_structure_infos = binding_map_clone(acceleration_structure_infos)
	set.handle = descriptor_pool_allocate(pool, ctx) or_return

	descriptor_set_prepare(set, ctx)
	return nil
}

descriptor_set_destroy :: proc(set: ^Descriptor_Set2) {
	binding_map_destroy(&set.buffer_infos)
	binding_map_destroy(&set.image_infos)
	binding_map_destroy(&set.acceleration_structure_infos)
	delete(set.write_descriptor_sets)
	delete(set.updated_bindings)
}

descriptor_set_prepare :: proc(set: ^Descriptor_Set2, ctx: ^Vulkan_Context) {
	assert(
		len(set.write_descriptor_sets) == 0,
		"We should not prepare the same descriptor set twice",
	)

	for binding_index, &buffer_bindings in set.buffer_infos.inner {
		if binding_info, ok := set.descriptor_set_layout.bindings_lookup[binding_index]; ok {
			for k, &buffer_info in buffer_bindings {

				uniform_buffer_range_limit :=
					ctx.device.physical_device.properties.limits.maxUniformBufferRange
				storage_buffer_range_limit :=
					ctx.device.physical_device.properties.limits.maxStorageBufferRange
				buffer_range_limit := u32(buffer_info.range)

				if (binding_info.descriptorType == .UNIFORM_BUFFER ||
					   binding_info.descriptorType == .UNIFORM_BUFFER_DYNAMIC) &&
				   buffer_range_limit > uniform_buffer_range_limit {
					log.errorf(
						"Set %d binding %d cannot be updated: buffer size %v exceeds the uniform buffer range limit %v",
						set.descriptor_set_layout.set_index,
						binding_index,
						buffer_info.range,
						uniform_buffer_range_limit,
					)
					buffer_range_limit = uniform_buffer_range_limit
				} else if (binding_info.descriptorType == .STORAGE_BUFFER ||
					   binding_info.descriptorType == .STORAGE_BUFFER_DYNAMIC) &&
				   buffer_range_limit > storage_buffer_range_limit {
					log.errorf(
						"Set %d binding %d cannot be updated: buffer size %v exceeds the storage buffer range limit %v",
						set.descriptor_set_layout.set_index,
						binding_index,
						buffer_info.range,
						storage_buffer_range_limit,
					)
					buffer_range_limit = storage_buffer_range_limit
				}

				buffer_info.range = vk.DeviceSize(buffer_range_limit)

				write_descriptor_set := vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					dstBinding      = binding_index,
					pBufferInfo     = &buffer_info,
					dstSet          = set.handle,
					dstArrayElement = k,
					descriptorCount = 1,
					descriptorType  = binding_info.descriptorType,
				}

				append(&set.write_descriptor_sets, write_descriptor_set)
			}
		} else {
			log.errorf("Shader layout set does not use buffer binding at %d", binding_index)
		}
	}

	for binding_index, &binding_resources in set.image_infos.inner {
		if binding_info, ok := set.descriptor_set_layout.bindings_lookup[binding_index]; ok {
			for f, &image_info in binding_resources {

				write_descriptor_set := vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					dstBinding      = binding_index,
					descriptorType  = binding_info.descriptorType,
					pImageInfo      = &image_info,
					dstSet          = set.handle,
					dstArrayElement = f,
					descriptorCount = 1,
				}
				append(&set.write_descriptor_sets, write_descriptor_set)
			}
		} else {
			log.errorf("Shader layout set does not use image binding at %d", binding_index)
		}
	}

	for binding_index, &as_bindings in set.acceleration_structure_infos.inner {
		if binding_info, ok := set.descriptor_set_layout.bindings_lookup[binding_index];
		   ok && binding_info.descriptorType == .ACCELERATION_STRUCTURE_KHR {
			// Ensure this is an acceleration structure binding
			for k, &as_info in as_bindings {
				write_descriptor_set := vk.WriteDescriptorSet {
					sType           = .WRITE_DESCRIPTOR_SET,
					dstBinding      = binding_index,
					descriptorType  = .ACCELERATION_STRUCTURE_KHR,
					dstSet          = set.handle,
					dstArrayElement = k,
					descriptorCount = 1,
					pNext           = &as_info,
				}
				append(&set.write_descriptor_sets, write_descriptor_set)
			}
		} else {
			log.errorf(
				"Binding %d is not an acceleration structure type, got %v",
				binding_index,
				binding_info.descriptorType,
			)
		}
	}

}

descriptor_set_update2 :: proc(
	set: ^Descriptor_Set2,
	ctx: ^Vulkan_Context,
	bindings_to_update: ..u32,
) {
	write_operations := make([dynamic]vk.WriteDescriptorSet, context.temp_allocator)
	write_operation_hashes := make([dynamic]u32, context.temp_allocator)

	if len(bindings_to_update) == 0 {
		// we want to update everything
		state, _ := xxhash.XXH32_create_state()
		defer xxhash.XXH32_destroy_state(state)

		for &write_operation in set.write_descriptor_sets {
			hash_param(state, write_operation)
			write_operation_hash := xxhash.XXH32_digest(state)

			if old_hash, ok := set.updated_bindings[write_operation.dstBinding];
			   !ok || old_hash != write_operation_hash {
				append(&write_operations, write_operation)
				append(&write_operation_hashes, write_operation_hash)
			}
		}
	} else {
		state, _ := xxhash.XXH32_create_state()
		defer xxhash.XXH32_destroy_state(state)

		for &write_operation in set.write_descriptor_sets {
			if slice.contains(bindings_to_update, write_operation.dstBinding) {
				hash_param(state, write_operation)
				write_operation_hash := xxhash.XXH32_digest(state)

				if old_hash, ok := set.updated_bindings[write_operation.dstBinding];
				   !ok || old_hash != write_operation_hash {
					append(&write_operations, write_operation)
					append(&write_operation_hashes, write_operation_hash)
				}
			}
		}
	}

	if len(write_operations) > 0 {
		vk.UpdateDescriptorSets(
			vulkan_get_device_handle(ctx),
			u32(len(write_operations)),
			raw_data(write_operations[:]),
			0,
			nil,
		)
	}

	for write_operation, i in write_operations {
		set.updated_bindings[write_operation.dstBinding] = write_operation_hashes[i]
	}
}
