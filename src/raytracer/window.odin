package raytracer

import "vendor:glfw"
import vk "vendor:vulkan"

Window :: struct {
	handle: glfw.WindowHandle,
	ctx:    Context,
}

window_init :: proc(
	window: ^Window,
	width, height: i32,
	title: cstring,
	allocator := context.allocator,
) -> (
	err: Error,
) {
	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if window.handle == nil do return .WindowCreation
	context_init(&window.ctx, window^, allocator) or_return

	return
}

window_get_framebuffer_size :: proc(window: Window) -> (width: i32, height: i32) {
	return glfw.GetFramebufferSize(window.handle)
}

window_destroy :: proc(window: ^Window) {
	context_destroy(&window.ctx)
	glfw.DestroyWindow(window.handle)
}

@(require_results)
window_create_surface :: proc(
	window: Window,
	instance: Instance,
) -> (
	surface: vk.SurfaceKHR,
	result: vk.Result,
) {
	result = glfw.CreateWindowSurface(instance, window.handle, nil, &surface)
	return
}

@(require_results)
window_should_close :: proc(window: Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

window_poll_events :: proc() {
	glfw.PollEvents()
}
