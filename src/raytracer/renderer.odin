package raytracer

import "core:mem"
import vk "vendor:vulkan"

Renderer :: struct {
	ctx: Context,
}

@(require_results)
renderer_init :: proc(renderer: ^Renderer, temp_allocator: mem.Allocator) -> vk.Result {
	return context_init(&renderer.ctx, temp_allocator)
}

renderer_destroy :: proc(renderer: Renderer) {
	context_destroy(renderer.ctx)
}
