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

application_init :: proc(
	app: ^Application,
	window_width, window_height: c.int,
	window_title: cstring,
	allocator := context.allocator,
) -> (
	err: Error,
) {
	app.window = new(Window)
	window_init(app.window, window_width, window_height, window_title) or_return
	app.renderer = new(Renderer, allocator)

	renderer_init(app.renderer, app.window, allocator)

	return
}

application_destroy :: proc(app: ^Application) {
	renderer_destroy(app.renderer)
	free(app.renderer)
	free(app.window)
	app.renderer = nil
	app.window = nil
}

application_run :: proc(app: ^Application) {
	renderer_run(app.renderer)
}
