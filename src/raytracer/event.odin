package raytracer

Event :: union {
	Window_Close_Event,
	Resize_Event,
	Key_Event,
	Mouse_Event,
	Mouse_Button_Event,
	Scene_Object_Material_Change,
	Scene_Object_Update_Position,
}

Window_Close_Event :: struct {}

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

Scene_Object_Material_Change :: struct {
	object_index, new_material_index: int,
}

Scene_Object_Update_Position :: struct {
	object_index: int,
	new_position: Vec3, // TODO: this in the future can change a little
}
