package raytracer

import "core:c"
import "core:fmt"
import "vendor:glfw"
_ :: fmt

Error :: union #shared_nil {
	Window_Error,
	Backend_Error,
}

Application :: struct {
	window:   ^Window,
	renderer: ^Renderer,
}

make_application :: proc(
	window_width, window_height: c.int,
	window_title: cstring,
	allocator := context.allocator,
) -> (
	app: Application,
	err: Error,
) {
	app.window = new_clone(make_window(window_width, window_height, window_title) or_return)
	app.renderer = new(Renderer, allocator)

	renderer_init(app.renderer, app.window, allocator) or_return

	window_set_window_user_pointer(app.window^, app.window)

	return
}

delete_application :: proc(app: Application) {
	renderer_destroy(app.renderer)
	// free(app.renderer)

	// delete_window(app.window^)
	// free(app.window)

}

application_run :: proc(app: ^Application, allocator := context.allocator) {
	for !window_should_close(app.window^) {
		application_update(app, allocator)
		application_render(app, allocator)
	}

}

application_update :: proc(app: ^Application, allocator := context.allocator) {
	glfw.PollEvents()
	window_update(app.window^)
}

application_render :: proc(app: ^Application, allocator := context.allocator) {
	renderer_render(app.renderer)
}

@(private)
application_handle_resize :: proc(
	app: ^Application,
	allocator := context.allocator,
) -> Backend_Error {
	app.window.framebuffer_resized = false
	unimplemented()
}
