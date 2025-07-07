package raytracer

import "core:hash/xxhash"
import "core:mem"

import vk "vendor:vulkan"

hash_param :: proc {
	hash_param_write_descriptor_set,
	hash_param_descriptor_set_layout,
	hash_param_descriptor_buffer_info,
	hash_param_descriptor_image_info,
	hash_param_binding_map,
}

hash_param_binding_map :: proc(state: ^xxhash.XXH32_state, binding_map: Binding_Map($T)) {
	for key, binding_set in binding_map.inner {
		xxhash.XXH32_update(state, mem.any_to_bytes(key))

		for k, binding_elem in binding_set {
			xxhash.XXH32_update(state, mem.any_to_bytes(k))
			hash_param(state, binding_elem)
		}
	}

}

hash_param_descriptor_buffer_info :: proc(
	state: ^xxhash.XXH32_state,
	buffer_info: vk.DescriptorBufferInfo,
) {
	xxhash.XXH32_update(state, mem.any_to_bytes(buffer_info.buffer))
	xxhash.XXH32_update(state, mem.any_to_bytes(buffer_info.range))
	xxhash.XXH32_update(state, mem.any_to_bytes(buffer_info.offset))
}

hash_param_descriptor_image_info :: proc(
	state: ^xxhash.XXH32_state,
	image_info: vk.DescriptorImageInfo,
) {
	xxhash.XXH32_update(state, mem.any_to_bytes(image_info.sampler))
	xxhash.XXH32_update(state, mem.any_to_bytes(image_info.imageView))
	xxhash.XXH32_update(state, mem.any_to_bytes(image_info.imageLayout))
}

hash_param_descriptor_set_layout :: proc(
	state: ^xxhash.XXH32_state,
	layout: Descriptor_Set_Layout2,
) {
	xxhash.XXH32_update(state, mem.any_to_bytes(layout.handle))
}

hash_param_write_descriptor_set :: proc(state: ^xxhash.XXH32_state, param: vk.WriteDescriptorSet) {
	xxhash.XXH32_update(state, mem.any_to_bytes(param.dstSet))
	xxhash.XXH32_update(state, mem.any_to_bytes(param.dstBinding))
	xxhash.XXH32_update(state, mem.any_to_bytes(param.dstArrayElement))
	xxhash.XXH32_update(state, mem.any_to_bytes(param.descriptorCount))
	xxhash.XXH32_update(state, mem.any_to_bytes(param.descriptorType))

	#partial switch (param.descriptorType) {
	case .SAMPLER, .COMBINED_IMAGE_SAMPLER, .SAMPLED_IMAGE, .STORAGE_IMAGE, .INPUT_ATTACHMENT:
		xxhash.XXH32_update(state, mem.any_to_bytes(param.pImageInfo))
	case .UNIFORM_BUFFER, .STORAGE_BUFFER, .UNIFORM_BUFFER_DYNAMIC, .STORAGE_BUFFER_DYNAMIC:
		xxhash.XXH32_update(state, mem.any_to_bytes(param.pBufferInfo))
	case:
		unimplemented("needs to implement for this type")
	}
}
