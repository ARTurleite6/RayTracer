package raytracer

Restir_Renderer :: struct {
	ctx:            ^Vulkan_Context,
	output_image:   Image_Set,
	shader_modules: [1]Shader_Module,
}

restir_renderer_init :: proc(renderer: ^Restir_Renderer, ctx: ^Vulkan_Context) {
	make_image_set(
		ctx,
		.R32G32B32A32_SFLOAT,
		renderer.ctx.swapchain_manager.extent,
		MAX_FRAMES_IN_FLIGHT,
	)

	shader_module_init(&renderer.shader_modules[0], {.RAYGEN_KHR}, "shaders/restir.rgen", "main")
}

restir_renderer_destroy :: proc(renderer: ^Restir_Renderer) {
	image_set_destroy(renderer.ctx, &renderer.output_image)

	for &shader in renderer.shader_modules {
		shader_module_destroy(&shader)
	}
}

// TODO: see if this should take the command buffer in
restir_renderer_render :: proc(
	renderer: ^Restir_Renderer,
	cmd: ^Command_Buffer,
	gpu_scene: GPU_Scene,
) {
}
