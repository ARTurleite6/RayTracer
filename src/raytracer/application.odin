package raytracer

import "core:c"
import "core:log"
import "vendor:glfw"
_ :: log

Error :: union #shared_nil {
	Window_Error,
}

Application :: struct {
	window:       ^Window,
	scene:        Scene,
	renderer:     Renderer,
	input_system: Input_System,

	// Vulkan stuff
	vk_ctx:       Vulkan_Context,
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
	window_set_window_user_pointer(app.window, app.window)
	window_set_event_handler(
		app.window,
		Event_Handler{data = app, on_event = application_on_event},
	)
	input_system_init(&app.input_system, allocator)


	{ 	// create rendering stuff
		renderer_init(&app.renderer, app.window, allocator)
		// TODO: change this
		app.scene = create_scene()

	}
	return
}

application_destroy :: proc(app: ^Application) {
	{ 	// destroy input systems
		input_system_destroy(&app.input_system)
	}

	{ 	// destroy scene
		renderer_destroy(&app.renderer)
		scene_destroy(&app.scene)
	}

	free(app.window)
	// app.renderer = nil
	// app.window = nil
}

application_update :: proc(app: ^Application) {
	glfw.PollEvents()

	renderer_update(&app.renderer)

	if input_system_is_key_pressed(app.input_system, .Q) {
		window_set_should_close(app.window)
	}
}

application_render :: proc(app: ^Application) {
	// renderer_begin_frame(&app.renderer)
	renderer_begin_frame(&app.renderer)

	renderer_render_ui(&app.renderer, &app.scene)
	renderer_render(&app.renderer, &app.scene)

	renderer_end_frame(&app.renderer)
}

application_run :: proc(app: ^Application) {
	for !window_should_close(app.window^) {
		application_update(app)
		application_render(app)
	}
}

application_on_event :: proc(handler: ^Event_Handler, event: Event) {
	app := (^Application)(handler.data)

	#partial switch v in event {
	case Mouse_Button_Event:
		input_system_register_mouse_button(&app.input_system, v.key, v.action)
	case Key_Event:
		input_system_register_key(&app.input_system, v.key, v.action)
	case Resize_Event:
		window_resize(app.window, v.width, v.height)
	case Mouse_Event:
		if input_system_is_mouse_key_pressed(app.input_system, .MOUSE_BUTTON_2) {
			window_set_input_mode(app.window, .Locked)
		} else {
			window_set_input_mode(app.window, .Normal)
		}
	}
}
