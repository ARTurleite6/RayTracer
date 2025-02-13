package raytracer

import "core:c"
import "vendor:glfw"

Error :: union #shared_nil{
	Window_Error,
	Context_Error,
}

Application :: struct {
	window: Window,
	ctx: Context,
}

make_application :: proc(window_width, window_height: c.int, window_title: cstring) -> (app: Application, err: Error) {
    app.window = make_window(window_width, window_height, window_title) or_return
    app.ctx = make_context(app.window) or_return

    return
}

delete_application :: proc(app: Application) {
    delete_context(app.ctx)
    delete_window(app.window)
}

application_run :: proc(app: Application) {
    for !window_should_close(app.window) {
        glfw.PollEvents()
        window_update(app.window)
    }
}
