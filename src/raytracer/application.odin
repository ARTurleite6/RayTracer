package raytracer

import "base:runtime"
import "core:c"
import "core:log"
import imgui "external:odin-imgui"
import "vendor:glfw"
_ :: log

Error :: union #shared_nil {
	Window_Error,
	Scene_Load_Error,
}

@(private = "file")
g_application: Application

Application :: struct {
	window:                      ^Window,
	scene:                       Scene,
	camera_controller:           Camera_Controller,
	renderer:                    Raytracing_Renderer,
	delta_time, last_frame_time: f64,
	running:                     bool,
	minimized:                   bool,
	ctx:                         runtime.Context,
}

application_init :: proc(
	window_width, window_height: c.int,
	window_title: cstring,
	scene_path: Maybe(string) = nil,
) -> (
	app: ^Application,
	err: Error,
) {
	app = &g_application
	app.running = true
	// TODO: change this
	// if scene_path, ok := scene_path.?; ok {
	// 	app.scene = load_scene_from_file(scene_path) or_return
	// } else {
	// 	app.scene = create_scene()
	// }

	app.scene, _ = load_scene_from_gltf("models/cornell_box/scene_with_light.glb")
	app.ctx = context
	app.window = new(Window)
	app.minimized = false
	window_init(app.window, window_width, window_height, window_title) or_return
	camera_controller_init(&app.camera_controller, {0, 0, -3}, window_aspect_ratio(app.window^))
	window_set_window_user_pointer(app.window, app.window)
	window_set_event_handler(app.window, application_event_handler(app))

	raytracing_renderer_init(&app.renderer, app.window)
	raytracing_renderer_set_scene(&app.renderer, &app.scene)

	return
}

application_destroy :: proc(app: ^Application) {
	raytracing_renderer_destroy(&app.renderer)
	window_destroy(app.window)
	free(app.window)
	scene_destroy(&app.scene)
}

application_get :: proc() -> ^Application {
	return &g_application
}

application_get_window :: proc(app: Application) -> ^Window {
	return app.window
}

application_update :: proc(app: ^Application) {
	glfw.PollEvents()

	current_time := glfw.GetTime()
	app.delta_time = current_time - app.last_frame_time
	app.last_frame_time = current_time

	if io := imgui.GetIO(); !io.WantCaptureKeyboard && is_key_pressed(.Q) {
		app.running = false
	}

	if is_key_pressed(.F11) {
		window_set_fullscreen(app.window)
	}

	dt := f32(app.delta_time)

	camera_controller_on_update(&app.camera_controller, dt)
}

application_render :: proc(app: ^Application) {
	if app.minimized {
		return
	}

	raytracing_renderer_begin_frame(&app.renderer)
	defer raytracing_renderer_end_frame(&app.renderer)
	raytracing_renderer_render_scene(&app.renderer, &app.camera_controller.camera)
	ui_render(&app.renderer)
}

application_run :: proc(app: ^Application) {
	for app.running {
		application_update(app)
		application_render(app)
		free_all(context.temp_allocator)
	}
}

application_on_event :: proc "contextless" (handler: ^Event_Handler, event: Event) {
	app := (^Application)(handler.data)
	context = app.ctx

	#partial switch v in event {
	case Resize_Event:
		application_on_resize(app, v.width, v.height)
	case Window_Close_Event:
		application_on_window_close(app)
	}

	camera_controller_on_event(&app.camera_controller, event)
}

application_on_resize :: proc(app: ^Application, width, height: int) -> bool {
	if width == 0 || height == 0 {
		app.minimized = true
	} else {
		app.minimized = false
	}
	return true
}

application_on_window_close :: proc(app: ^Application) -> bool {
	app.running = false
	return true
}

application_event_handler :: proc(app: ^Application) -> Event_Handler {
	return {data = app, on_event = application_on_event}
}
