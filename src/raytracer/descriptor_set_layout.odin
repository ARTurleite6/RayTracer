package raytracer

import vk "vendor:vulkan"

Descriptor_Set_Layout2 :: struct {
	handle:               vk.DescriptorSetLayout,
	bindings:             [dynamic]vk.DescriptorSetLayoutBinding,
	binding_flags:        [dynamic]vk.DescriptorBindingFlagsEXT,
	bindings_lookup:      map[u32]vk.DescriptorSetLayoutBinding,
	binding_flags_lookup: map[u32]vk.DescriptorBindingFlagsEXT,
	resources_lookup:     map[string]u32,
	shader_modules:       []^Shader_Module,
	set_index:            u32,
}

descriptor_set_layout2_init :: proc(
	layout: ^Descriptor_Set_Layout2,
	ctx: ^Vulkan_Context,
	set_index: u32,
	shader_modules: []^Shader_Module,
	resource_set: []Shader_Resource,
) -> (
	err: vk.Result,
) {
	for res in resource_set {
		if res.type == .Input ||
		   res.type == .Output ||
		   res.type == .Push_Constant ||
		   res.type == .Specialization_Constant {
			continue
		}

		descriptor_type := find_descriptor_type(res.type, res.mode == .Dynamic)

		if res.mode == .Update_After_Bind {
			append_elem(&layout.binding_flags, vk.DescriptorBindingFlagsEXT{.UPDATE_AFTER_BIND})
		} else {
			append_elem(&layout.binding_flags, vk.DescriptorBindingFlagsEXT{})
		}

		layout_binding := vk.DescriptorSetLayoutBinding {
			binding         = res.binding,
			descriptorCount = res.array_size,
			descriptorType  = descriptor_type,
			stageFlags      = res.stages,
		}

		append(&layout.bindings, layout_binding)
		layout.bindings_lookup[res.binding] = layout_binding
		layout.binding_flags_lookup[res.binding] =
			layout.binding_flags[len(layout.binding_flags) - 1]

		layout.resources_lookup[res.name] = res.binding
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		flags        = {},
		bindingCount = u32(len(layout.bindings)),
		pBindings    = raw_data(layout.bindings),
	}

	// TODO: for now I dont needs this, lets add it in the future
	// binding_flags_create_info := vk.DescriptorSetLayoutBindingFlagsCreateInfoEXT {
	// 	sType = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT,
	// }

	return vk_check(
		vk.CreateDescriptorSetLayout(
			vulkan_get_device_handle(ctx),
			&create_info,
			nil,
			&layout.handle,
		),
		"Failed to create descriptor set layout",
	)
}


@(private = "file")
@(require_results)
find_descriptor_type :: proc(resource_type: Shader_Resource_Type, dyn: bool) -> vk.DescriptorType {
	#partial switch resource_type {
	case .Input_Attachment:
		return .INPUT_ATTACHMENT
	case .Image:
		return .SAMPLED_IMAGE
	case .Image_Sampler:
		return .COMBINED_IMAGE_SAMPLER
	case .Image_Storage:
		return .STORAGE_IMAGE
	case .Sampler:
		return .SAMPLER
	case .Buffer_Uniform:
		if dyn {
			return .UNIFORM_BUFFER_DYNAMIC
		} else {
			return .UNIFORM_BUFFER
		}
	case .Buffer_Storage:
		if dyn {
			return .STORAGE_BUFFER_DYNAMIC
		} else {
			return .STORAGE_BUFFER
		}
	case:
		panic("No possible conversion for resource type")
	}
}
