package raytracer

import imgui "external:odin-imgui"

Camera_Controller :: struct {
	camera: Camera,
}

camera_controller_init :: proc(self: ^Camera_Controller, position: Vec3, aspect_ratio: f32) {
	camera_init(&self.camera, position, aspect_ratio)
}

camera_controller_on_event :: proc(self: ^Camera_Controller, event: Event) {
	if event, ok := event.(Resize_Event); ok {
		camera_on_resize(&self.camera, f32(event.width) / f32(event.height))
	}
}

camera_controller_on_update :: proc(self: ^Camera_Controller, ts: f32) {
	io := imgui.GetIO()

	if !io.WantCaptureKeyboard {
		if is_key_pressed(.W) {
			camera_move(&self.camera, .Forward, ts)
		}
		if is_key_pressed(.S) {
			camera_move(&self.camera, .Backwards, ts)
		}
		if is_key_pressed(.A) {
			camera_move(&self.camera, .Left, ts)
		}
		if is_key_pressed(.D) {
			camera_move(&self.camera, .Right, ts)
		}
		if is_key_pressed(.Space) {
			camera_move(&self.camera, .Up, ts)
		}
		if is_key_pressed(.Left_Shift) {
			camera_move(&self.camera, .Down, ts)
		}
	}

	if !io.WantCaptureMouse {
		move_camera := is_mouse_key_pressed(.MOUSE_BUTTON_2)
		if move_camera {
			set_input_mode(.Locked)

		} else {
			set_input_mode(.Normal)
		}

		x, y := mouse_position()
		camera_process_mouse(&self.camera, f32(x), f32(y), move_camera)
	}
}
