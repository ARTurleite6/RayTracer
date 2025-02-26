package raytracer

import "base:runtime"
import "core:c"
import "core:log"
import vkb "external:odin-vk-bootstrap"
import "vendor:glfw"
import vk "vendor:vulkan"

Window_Error :: enum {
	None = 0,
	Initializing,
	Creating_Window,
}

Window :: struct {
	handle:              glfw.WindowHandle,
	surface:             vk.SurfaceKHR,
	framebuffer_resized: bool,
	width, height:       c.int,
}

window_init :: proc(window: ^Window, width, height: c.int, title: cstring) -> (err: Window_Error) {
	if !glfw.Init() {
		log.error("GLFW: Error while initialization")
		return .Initializing
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if window.handle == nil {
		log.error("GLFW: Error creating window")
		return .Creating_Window
	}

	window.width, window.height = width, height

	glfw.SetFramebufferSizeCallback(window.handle, framebuffer_resize)

	return
}

window_destroy :: proc(window: Window, instance: vk.Instance) {
	if window.surface != 0 {
		vk.DestroySurfaceKHR(instance, window.surface, nil)
	}
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

window_set_window_user_pointer :: proc(window: Window, pointer: rawptr) {
	glfw.SetWindowUserPointer(window.handle, pointer)
}

window_should_close :: proc(window: Window) -> b32 {
	return glfw.WindowShouldClose(window.handle)
}

window_update :: proc(window: Window) {
	glfw.SwapBuffers(window.handle)
}

window_aspect_ratio :: proc(window: Window) -> f32 {
	extent := window_get_extent(window)
	return f32(extent.width) / f32(extent.height)
}

@(require_results)
window_get_surface :: proc(
	window: ^Window,
	instance: ^vkb.Instance,
) -> (
	surface: vk.SurfaceKHR,
	err: vk.Result,
) {
	if window.surface != 0 {
		return window.surface, .SUCCESS
	}
	glfw.CreateWindowSurface(instance.ptr, window.handle, nil, &window.surface) or_return

	return window.surface, .SUCCESS
}

@(require_results)
window_get_extent :: proc(window: Window) -> vk.Extent2D {
	return {width = u32(window.width), height = u32(window.height)}
}

window_wait_events :: proc(window: Window) {
	glfw.WaitEvents()
}

framebuffer_resize :: proc "c" (window_handle: glfw.WindowHandle, width, height: c.int) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)

	window.framebuffer_resized = true
	window.width = width
	window.height = height
}
