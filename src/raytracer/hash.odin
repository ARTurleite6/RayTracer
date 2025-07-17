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
	hash_param_pipeline_state,
	hash_param_pipeline_layout,
	hash_param_shader_modules_list,
	hash_param_vertex_input_attribute_description,
	hash_param_vertex_input_binding_description,
}

hash_param_shader_modules_list :: proc(
	state: ^xxhash.XXH32_state,
	shader_modules: []^Shader_Module,
) {
	for module in shader_modules {
		xxhash.XXH32_update(state, mem.any_to_bytes(module.id))
	}
}

hash_param_pipeline_state :: proc(state: ^xxhash.XXH32_state, pipeline_state: Pipeline_State) {
	pipeline_layout := pipeline_state.layout
	hash_param_pipeline_layout(state, pipeline_layout.handle)

	for shader_module in pipeline_layout.shader_modules {
		xxhash.XXH32_update(state, mem.any_to_bytes(shader_module.id))
	}

	for c in pipeline_state.color_attachment_formats {
		xxhash.XXH32_update(state, mem.any_to_bytes(c))
	}
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_attachment_format))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.stencil_attachment_format))

	// Vertex Input Attributes
	for attribute in pipeline_state.vertex_input.attributes {
		hash_param(state, attribute)
	}

	// Vertex Input Bindings
	for binding in pipeline_state.vertex_input.bindings {
		hash_param(state, binding)
	}

	// Input Assembly
	xxhash.XXH32_update(
		state,
		mem.any_to_bytes(pipeline_state.input_assembly.primitive_restart_enable),
	)
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.input_assembly.topology))

	// Viewport State
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.viewport.viewport_count))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.viewport.scissor_count))

	// VkPipelineRasterizationStateCreateInfo
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.rasterization.cull_mode))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.rasterization.depth_bias_enable))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.rasterization.depth_clamp_enable))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.rasterization.front_face))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.rasterization.polygon_mode))
	xxhash.XXH32_update(
		state,
		mem.any_to_bytes(pipeline_state.rasterization.rasterizer_discard_enable),
	)

	// VkPipelineMultisampleStateCreateInfo
	xxhash.XXH32_update(
		state,
		mem.any_to_bytes(pipeline_state.multisample.alpha_to_coverage_enable),
	)
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.multisample.alpha_to_one_enable))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.multisample.min_sample_shading))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.multisample.rasterization_samples))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.multisample.sample_shading_enable))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.multisample.sample_mask))

	// VkPipelineDepthStencilStateCreateInfo
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_stencil.back))
	xxhash.XXH32_update(
		state,
		mem.any_to_bytes(pipeline_state.depth_stencil.depth_bounds_test_enable),
	)
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_stencil.depth_compare_op))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_stencil.depth_test_enable))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_stencil.depth_write_enable))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_stencil.front))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.depth_stencil.stencil_test_enable))

	// VkPipelineColorBlendStateCreateInfo
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.color_blend.logic_op))
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.color_blend.logic_op_enable))
	for color_blend_attachment in pipeline_state.color_blend.attachments {
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.alpha_blend_op))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.blend_enable))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.color_blend_op))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.color_write_mask))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.dst_alpha_blend_factor))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.dst_color_blend_factor))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.src_alpha_blend_factor))
		xxhash.XXH32_update(state, mem.any_to_bytes(color_blend_attachment.src_color_blend_factor))
	}

	// Raytracing max recursion
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_state.max_ray_recursion))
}

hash_param_vertex_input_attribute_description :: proc(
	state: ^xxhash.XXH32_state,
	attribute: vk.VertexInputAttributeDescription,
) {
	xxhash.XXH32_update(state, mem.any_to_bytes(attribute.binding))
	xxhash.XXH32_update(state, mem.any_to_bytes(attribute.format))
	xxhash.XXH32_update(state, mem.any_to_bytes(attribute.location))
	xxhash.XXH32_update(state, mem.any_to_bytes(attribute.offset))
}

hash_param_vertex_input_binding_description :: proc(
	state: ^xxhash.XXH32_state,
	binding: vk.VertexInputBindingDescription,
) {
	xxhash.XXH32_update(state, mem.any_to_bytes(binding.binding))
	xxhash.XXH32_update(state, mem.any_to_bytes(binding.inputRate))
	xxhash.XXH32_update(state, mem.any_to_bytes(binding.stride))
}

hash_param_pipeline_layout :: proc(
	state: ^xxhash.XXH32_state,
	pipeline_layout: vk.PipelineLayout,
) {
	xxhash.XXH32_update(state, mem.any_to_bytes(pipeline_layout))
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
	case .ACCELERATION_STRUCTURE_KHR:
		write_info := cast(^vk.WriteDescriptorSetAccelerationStructureKHR)param.pNext
		assert(write_info != nil)
		as := write_info.pAccelerationStructures[:write_info.accelerationStructureCount]
		for a in as {
			xxhash.XXH32_update(state, mem.any_to_bytes(a))
		}
	case:
		unimplemented("needs to implement for this type")
	}
}
