package raytracer

import "vendor:glfw"

Window :: struct {
	handle: glfw.WindowHandle,
}

window_init :: proc(window: ^Window, width, height: i32, title: cstring) {
	window.handle = glfw.CreateWindow(width, height, title, nil, nil)
}

window_destroy :: proc(window: Window) {
	glfw.DestroyWindow(window.handle)
}

@(require_results)
window_should_close :: proc(window: Window) -> bool {
	return bool(glfw.WindowShouldClose(window.handle))
}

window_poll_events :: proc() {
	glfw.PollEvents()
}
