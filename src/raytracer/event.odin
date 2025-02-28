package raytracer

Event :: union {
	Key_Event,
	Resize_Event,
	Mouse_Event,
	Mouse_Button_Event,
}

Key_Event :: struct {
	key:    Key_Code,
	action: Key_Action,
	mods:   Key_Mod_Flags,
}

Resize_Event :: struct {
	width, height: i32,
}

Mouse_Event :: struct {
	x, y: f32,
}

Mouse_Button_Event :: struct {
	key:    Mouse_Key_Code,
	action: Key_Action,
	mods:   Key_Mod_Flags,
}
