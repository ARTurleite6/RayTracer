package raytracer

import "base:runtime"
import "core:log"
import "core:mem"
import "vendor:glfw"
import vk "vendor:vulkan"

g_context: runtime.Context

Error :: union #shared_nil {
	General_Error,
	vk.Result,
}

General_Error :: enum u8 {
	None,
	Initialization,
	WindowCreation,
}

Application :: struct {
	window:         Window,
	renderer:       Renderer,
	allocator:      mem.Allocator,
	temp_allocator: mem.Allocator,
}

@(require_results)
application_init :: proc(
	app: ^Application,
	window_width, window_height: i32,
	application_name: cstring,
	allocator: mem.Allocator,
	temp_allocator: mem.Allocator,
) -> (
	err: Error,
) {
	context.logger = log.create_console_logger()
	g_context = context

	app.allocator = allocator
	app.temp_allocator = temp_allocator

	if !glfw.Init() {
		log.fatal("GLFW: error initializing")
		return .Initialization
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window_init(
		&app.window,
		window_width,
		window_height,
		application_name,
		app.allocator,
		app.temp_allocator,
	) or_return

	return renderer_init(&app.renderer)
}

application_destroy :: proc(app: Application) {
	renderer_destroy(app.renderer)
	window_destroy(app.window)
}

application_run :: proc(app: Application) {
	for !window_should_close(app.window) {
		free_all(context.temp_allocator)
		window_poll_events()
	}
}
