package raytracer

import "core:c"
import "core:fmt"
import "core:log"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: fmt

Error :: union #shared_nil {
	Window_Error,
	vk.Result,
}

Application :: struct {
	window:        ^Window,
	renderer:      ^Renderer,
	should_resize: bool,
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
	if !renderer_init(app.renderer, app.window, allocator) {
		return
	}

	window_set_window_user_pointer(app.window^, app.window)

	return
}

delete_application :: proc(app: Application) {
	renderer_destroy(app.renderer)
	free(app.renderer)

	delete_window(app.window^)
	free(app.window)

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

	if app.should_resize {
		app.should_resize = false
		if !application_handle_resize(app, allocator) {
			log.errorf("Error while resizing window")
		}
	}
}

application_render :: proc(app: ^Application, allocator := context.allocator) {
	result: vk.Result

	if !renderer_begin_frame(app.renderer) do return

	renderer_draw(app.renderer)

	result = renderer_end_frame(app.renderer)

	if result == .ERROR_OUT_OF_DATE_KHR ||
	   result == .SUBOPTIMAL_KHR ||
	   app.window.framebuffer_resized {
		app.should_resize = true
	} else if result != .SUCCESS {
		return
	}
}

@(private)
application_handle_resize :: proc(app: ^Application, allocator := context.allocator) -> bool {
	app.window.framebuffer_resized = false
	return renderer_handle_resize(app.renderer, allocator)
}
