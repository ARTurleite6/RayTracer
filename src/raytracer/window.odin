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

Cursor_Mode :: enum {
	Normal = 0,
	Hidden,
	Locked,
}

Window :: struct {
	handle:              glfw.WindowHandle,
	surface:             vk.SurfaceKHR,
	framebuffer_resized: bool,
	width, height:       c.int,
	event_handler:       Event_Handler,
	// TODO: probably this does not make sense, and should go with a better approach
	logger:              log.Logger,
}

Event_Handler :: struct {
	data:     rawptr,
	on_event: #type proc(handler: ^Event_Handler, event: Event),
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

	window.logger = context.logger

	glfw.SetFramebufferSizeCallback(window.handle, framebuffer_resize)
	glfw.SetKeyCallback(window.handle, key_callback)
	glfw.SetCursorPosCallback(window.handle, cursor_position_callback)
	glfw.SetMouseButtonCallback(window.handle, mouse_button_callback)

	return
}

window_destroy :: proc(window: Window, instance: vk.Instance) {
	if window.surface != 0 {
		vk.DestroySurfaceKHR(instance, window.surface, nil)
	}
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

window_set_window_user_pointer :: proc(window: ^Window, pointer: rawptr) {
	glfw.SetWindowUserPointer(window.handle, pointer)
}

window_set_event_handler :: proc(window: ^Window, handler: Event_Handler) {
	window.event_handler = handler
}

window_should_close :: proc(window: Window) -> b32 {
	return glfw.WindowShouldClose(window.handle)
}

window_resize :: proc(window: ^Window, width, height: i32) {
	window.framebuffer_resized = true
	window.width = width
	window.height = height
}

window_update :: proc(window: Window) {
	glfw.SwapBuffers(window.handle)
}

window_set_should_close :: proc(window: Window) {
	glfw.SetWindowShouldClose(window.handle, true)
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

window_set_input_mode :: proc(window: Window, mode: Cursor_Mode) {
	glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL + cast(i32)mode)
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
	context.logger = window.logger

	window.event_handler->on_event(Resize_Event{width = width, height = height})
}

@(private = "file")
key_callback :: proc "c" (window_handle: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	context.logger = window.logger
	window.event_handler->on_event(
		Key_Event {
			key = Key_Code(key),
			action = Key_Action(action),
			mods = transmute(Key_Mod_Flags)mods,
		},
	)
}

@(private = "file")
cursor_position_callback :: proc "c" (window_handle: glfw.WindowHandle, x_pos: f64, y_pos: f64) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	context.logger = window.logger

	window.event_handler->on_event(Mouse_Event{x = f32(x_pos), y = f32(y_pos)})
}

@(private = "file")
mouse_button_callback :: proc "c" (window_handle: glfw.WindowHandle, button, action, mods: c.int) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	context.logger = window.logger

	window.event_handler.on_event(
		&window.event_handler,
		Mouse_Button_Event {
			key = cast(Mouse_Key_Code)button,
			action = cast(Key_Action)action,
			mods = transmute(Key_Mod_Flags)mods,
		},
	)
}
