package raytracer

import vk "vendor:vulkan"

pipeline_layout_init :: proc(
	ctx: ^Vulkan_Context,
	descriptor_set_layouts: []vk.DescriptorSetLayout,
	push_constant_ranges: []vk.PushConstantRange,
) -> (
	layout: vk.PipelineLayout,
) {
	create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = u32(len(descriptor_set_layouts)),
		pSetLayouts            = raw_data(descriptor_set_layouts),
		pushConstantRangeCount = u32(len(push_constant_ranges)),
		pPushConstantRanges    = raw_data(push_constant_ranges),
	}

	_ = vk_check(
		vk.CreatePipelineLayout(vulkan_get_device_handle(ctx), &create_info, nil, &layout),
		"Failed to create pipeline layout",
	)

	return layout
}
