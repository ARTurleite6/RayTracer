package raytracer

import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_vulkan "external:odin-imgui/imgui_impl_vulkan"
import vk "vendor:vulkan"

UI_Context :: struct {
	pool: vk.DescriptorPool,
}

ui_context_init :: proc(ctx: ^UI_Context, device: ^Device, window: Window, format: vk.Format) {
	builder := &Descriptor_Pool_Builder{}
	descriptor_pool_builder_init(builder, device)
	descriptor_pool_builder_set_max_sets(builder, 1000)
	descriptor_pool_builder_add_pool_size(builder, .SAMPLER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .COMBINED_IMAGE_SAMPLER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .SAMPLED_IMAGE, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_IMAGE, 1000)
	descriptor_pool_builder_add_pool_size(builder, .UNIFORM_TEXEL_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_TEXEL_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .UNIFORM_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .UNIFORM_BUFFER_DYNAMIC, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_BUFFER_DYNAMIC, 1000)
	descriptor_pool_builder_add_pool_size(builder, .INPUT_ATTACHMENT, 1000)
	descriptor_pool_builder_set_flags(builder, {.FREE_DESCRIPTOR_SET})
	ctx.pool, _ = descriptor_pool_build(builder)

	imgui.CreateContext()
	imgui_vulkan.LoadFunctions(
		proc "c" (name: cstring, vulkan_instance: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr(cast(vk.Instance)vulkan_instance, name)
		},
		device.instance.ptr,
	)

	imgui_glfw.InitForVulkan(window.handle, true)
	format := format
	init_info := imgui_vulkan.InitInfo {
		Instance = device.instance.ptr,
		PhysicalDevice = device.physical_device.ptr,
		Device = device.logical_device.ptr,
		Queue = device.graphics_queue,
		DescriptorPool = ctx.pool,
		MinImageCount = 3,
		ImageCount = 3,
		UseDynamicRendering = true,
		PipelineRenderingCreateInfo = {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &format,
		},
		MSAASamples = ._1,
	}
	imgui_vulkan.Init(&init_info)
	imgui_vulkan.CreateFontsTexture()
}

ui_context_destroy :: proc(ctx: ^UI_Context, device: ^Device) {
	imgui_vulkan.Shutdown()
	vk.DestroyDescriptorPool(device.logical_device.ptr, ctx.pool, nil)
}
