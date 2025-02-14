package raytracer

import "core:c"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"

Window_Error :: enum {
	None = 0,
	Initializing,
	Creating_Window,
}

Window :: struct {
	handle: glfw.WindowHandle,
}

make_window :: proc(width, height: c.int, title: cstring) -> (window: Window, err: Window_Error) {
	if !glfw.Init() {
		log.error("GLFW: Error while initialization")
		return {}, .Initializing
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if window.handle == nil {
		log.error("GLFW: Error creating window")
		return {}, .Creating_Window
	}

	return
}

delete_window :: proc(window: Window) {
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

window_should_close :: proc(window: Window) -> b32 {
	return glfw.WindowShouldClose(window.handle)
}

window_update :: proc(window: Window) {
	glfw.SwapBuffers(window.handle)
}

@(require_results)
window_make_surface :: proc(window: Window, instance: Instance) -> (surface: vk.SurfaceKHR, result: vk.Result) {
	result = glfw.CreateWindowSurface(instance, window.handle, nil, &surface)

	return
}

@(require_results)
window_get_framebuffer_size :: proc(window: Window) -> (width, height: c.int) {
        return glfw.GetFramebufferSize(window.handle)
}
