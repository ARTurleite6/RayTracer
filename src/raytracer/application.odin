package raytracer

import "core:c"
import "core:log"
import "vendor:glfw"
_ :: log

Error :: union #shared_nil {
	Window_Error,
}

@(private = "file")
g_application: Application

Application :: struct {
	window:                      ^Window,
	scene:                       Scene,
	camera:                      Camera,
	renderer:                    Renderer,
	delta_time, last_frame_time: f64,
	running:                     bool,

	// Vulkan stuff
	vk_ctx:                      Vulkan_Context,
}

application_init :: proc(
	window_width, window_height: c.int,
	window_title: cstring,
) -> (
	app: ^Application,
	err: Error,
) {
	app = &g_application
	app.running = true
	app.window = new(Window)
	window_init(app.window, window_width, window_height, window_title) or_return
	camera_init(&app.camera, {0, 0, -3}, window_aspect_ratio(app.window^))
	window_set_window_user_pointer(app.window, app.window)
	window_set_event_handler(app.window, application_event_handler(app))


	{ 	// create rendering stuff
		renderer_init(&app.renderer, app.window)
		// TODO: change this
		app.scene = create_scene()

		renderer_set_scene(&app.renderer, &app.scene)

	}
	return
}

application_destroy :: proc(app: ^Application) {
	{ 	// destroy scene
		renderer_destroy(&app.renderer)
		window_destroy(app.window)
		free(app.window)
		scene_destroy(&app.scene)
	}
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

	dt := f32(app.delta_time)
	is_key_pressed(.W)
	if is_key_pressed(.W) {
		camera_move(&app.camera, .Forward, dt)
	}
	if is_key_pressed(.S) {
		camera_move(&app.camera, .Backwards, dt)
	}
	if is_key_pressed(.A) {
		camera_move(&app.camera, .Left, dt)
	}
	if is_key_pressed(.D) {
		camera_move(&app.camera, .Right, dt)
	}
	if is_key_pressed(.Space) {
		camera_move(&app.camera, .Up, dt)
	}
	if is_key_pressed(.Left_Shift) {
		camera_move(&app.camera, .Down, dt)
	}

	if is_key_pressed(.Q) {
		app.running = false
	}

	{
		move_camera := is_mouse_key_pressed(.MOUSE_BUTTON_2)
		if move_camera {
			set_input_mode(.Locked)

		} else {
			set_input_mode(.Normal)
		}

		x, y := mouse_position()
		camera_process_mouse(&app.camera, f32(x), f32(y), move_camera)
	}

	renderer_update(&app.renderer)
}

application_render :: proc(app: ^Application) {
	// renderer_begin_frame(&app.renderer)
	renderer_begin_frame(&app.renderer)

	renderer_render(&app.renderer, &app.camera)
	renderer_render_ui(&app.renderer)

	renderer_end_frame(&app.renderer)
}

application_run :: proc(app: ^Application) {
	for app.running {
		application_update(app)
		application_render(app)
	}
}

application_on_event :: proc(handler: ^Event_Handler, event: Event) {
	app := (^Application)(handler.data)

	dispatch(event, Resize_Event, application_on_resize, app)
	dispatch(event, Window_Close_Event, application_on_window_close, app)
}

application_on_resize :: proc(user_data: rawptr, event: Resize_Event) -> bool {
	app := (^Application)(user_data)
	camera_on_resize(&app.camera, window_aspect_ratio(app.window^))
	renderer_on_resize(&app.renderer, u32(event.width), u32(event.height))
	return true
}

application_on_window_close :: proc(user_data: rawptr, event: Window_Close_Event) -> bool {
	app := (^Application)(user_data)
	app.running = false
	return true
}

application_event_handler :: proc(app: ^Application) -> Event_Handler {
	return {data = app, on_event = application_on_event}
}
