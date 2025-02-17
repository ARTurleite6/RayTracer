package raytracer

import "core:c"
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

Error :: union #shared_nil {
	Window_Error,
	Context_Error,
	vk.Result,
}

Application :: struct {
	window:   Window,
	ctx:      ^Context,
	renderer: Renderer,
}

make_application :: proc(
	window_width, window_height: c.int,
	window_title: cstring,
	allocator := context.allocator,
) -> (
	app: Application,
	err: Error,
) {
	app.window = make_window(window_width, window_height, window_title) or_return
	app.ctx = new_clone(make_context(app.window) or_return)
	app.renderer = make_renderer(app.ctx, allocator) or_return

	return
}

delete_application :: proc(app: Application) {
	delete_context(app.ctx^)
	free(app.ctx)
	delete_window(app.window)
}

application_run :: proc(app: ^Application) {
	for !window_should_close(app.window) {
		glfw.PollEvents()
		window_update(app.window)

		if result := renderer_begin_frame(&app.renderer); result != .SUCCESS {
			fmt.eprintfln("Error starting frame %v", result)
			return
		}

		renderer_draw(app.renderer)

		if result := renderer_end_frame(&app.renderer); result != .SUCCESS {
			fmt.eprintfln("Error ending frame %v", result)
			return
		}
	}
}
