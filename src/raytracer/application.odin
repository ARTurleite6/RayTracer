package raytracer

import "core:c"
import "core:fmt"
_ :: fmt

Error :: union #shared_nil {
	Window_Error,
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

	renderer_init(app.renderer, app.window, allocator)

	window_set_window_user_pointer(app.window^, app.window)

	return
}

delete_application :: proc(app: Application) {
	renderer_destroy(app.renderer)
}

application_run :: proc(app: ^Application) {
	renderer_run(app.renderer)
}
