package raytracer

import "core:c"
import "vendor:glfw"

Cursor_Mode :: enum {
	Normal = 0,
	Hidden = 1,
	Locked = 2,
}

is_key_down :: proc(window: glfw.WindowHandle, button: c.int) -> bool {
	state := glfw.GetKey(window, button)
	return state == glfw.PRESS || state == glfw.REPEAT
}

is_mouse_button_down :: proc(window: glfw.WindowHandle, button: c.int) -> bool {
	state := glfw.GetMouseButton(window, button)
	return state == glfw.PRESS || state == glfw.REPEAT
}

get_mouse_position :: proc(window: glfw.WindowHandle) -> Vec2 {
	x, y := glfw.GetCursorPos(window)
	return {f32(x), f32(y)}
}

set_cursor_mode :: proc(window: glfw.WindowHandle, mode: Cursor_Mode) {
	glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL + c.int(mode))
}
