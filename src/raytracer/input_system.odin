package raytracer

Input_System :: struct {
	key_states:       map[Key_Code]Key_State,
	mouse_key_states: map[Mouse_Key_Code]Key_State,
}

Key_State :: struct {
	is_pressed: bool,
}

Key_Action :: enum {
	Release = 0,
	Pressed = 1,
	Repeat  = 2,
}

Mouse_Key_Code :: enum {
	MOUSE_BUTTON_1 = 0,
	MOUSE_BUTTON_2,
	MOUSE_BUTTON_3,
	MOUSE_BUTTON_4,
	MOUSE_BUTTON_5,
	MOUSE_BUTTON_6,
	MOUSE_BUTTON_7,
	MOUSE_BUTTON_8,
}

Key_Code :: enum {
	// From glfw3.h
	Space         = 32,
	Apostrophe    = 39, /* ' */
	Comma         = 44, /* , */
	Minus         = 45, /* - */
	Period        = 46, /* . */
	Slash         = 47, /* / */
	D0            = 48, /* 0 */
	D1            = 49, /* 1 */
	D2            = 50, /* 2 */
	D3            = 51, /* 3 */
	D4            = 52, /* 4 */
	D5            = 53, /* 5 */
	D6            = 54, /* 6 */
	D7            = 55, /* 7 */
	D8            = 56, /* 8 */
	D9            = 57, /* 9 */
	Semicolon     = 59, /* ; */
	Equal         = 61, /* = */
	A             = 65,
	B             = 66,
	C             = 67,
	D             = 68,
	E             = 69,
	F             = 70,
	G             = 71,
	H             = 72,
	I             = 73,
	J             = 74,
	K             = 75,
	L             = 76,
	M             = 77,
	N             = 78,
	O             = 79,
	P             = 80,
	Q             = 81,
	R             = 82,
	S             = 83,
	T             = 84,
	U             = 85,
	V             = 86,
	W             = 87,
	X             = 88,
	Y             = 89,
	Z             = 90,
	Left_Bracket  = 91, /* [ */
	Backslash     = 92, /* \ */
	Right_Bracket = 93, /* ] */
	Grave_Accent  = 96, /* ` */
	World1        = 161, /* non-US #1 */
	World2        = 162, /* non-US #2 */

	/* Function keys */
	Escape        = 256,
	Enter         = 257,
	Tab           = 258,
	Backspace     = 259,
	Insert        = 260,
	Delete        = 261,
	Right         = 262,
	Left          = 263,
	Down          = 264,
	Up            = 265,
	PageUp        = 266,
	PageDown      = 267,
	Home          = 268,
	End           = 269,
	CapsLock      = 280,
	ScrollLock    = 281,
	NumLock       = 282,
	PrintScreen   = 283,
	Pause         = 284,
	F1            = 290,
	F2            = 291,
	F3            = 292,
	F4            = 293,
	F5            = 294,
	F6            = 295,
	F7            = 296,
	F8            = 297,
	F9            = 298,
	F10           = 299,
	F11           = 300,
	F12           = 301,
	F13           = 302,
	F14           = 303,
	F15           = 304,
	F16           = 305,
	F17           = 306,
	F18           = 307,
	F19           = 308,
	F20           = 309,
	F21           = 310,
	F22           = 311,
	F23           = 312,
	F24           = 313,
	F25           = 314,

	/* Keypad */
	KP0           = 320,
	KP1           = 321,
	KP2           = 322,
	KP3           = 323,
	KP4           = 324,
	KP5           = 325,
	KP6           = 326,
	KP7           = 327,
	KP8           = 328,
	KP9           = 329,
	KP_Decimal    = 330,
	KP_Divide     = 331,
	KP_Multiply   = 332,
	KP_Subtract   = 333,
	KP_Add        = 334,
	KP_Enter      = 335,
	KP_Equal      = 336,
	Left_Shift    = 340,
	Left_Control  = 341,
	Left_Alt      = 342,
	Left_Super    = 343,
	Right_Shift   = 344,
	Right_Control = 345,
	Right_Alt     = 346,
	Right_Super   = 347,
	Menu          = 348,
}

Key_Mod :: enum u32 {
	MOD_SHIFT     = 0x0001,
	MOD_CONTROL   = 0x0002,
	MOD_ALT       = 0x0004,
	MOD_SUPER     = 0x0008,
	MOD_CAPS_LOCK = 0x0010,
	MOD_NUM_LOCK  = 0x0020,
}

Key_Mod_Flags :: bit_set[Key_Mod]

input_system_init :: proc(system: ^Input_System) {
}

input_system_destroy :: proc(system: ^Input_System) {
	delete(system.key_states)
	delete(system.mouse_key_states)
	system^ = {}
}

input_system_register_mouse_button :: proc(
	system: ^Input_System,
	key: Mouse_Key_Code,
	action: Key_Action,
) {
	if action == .Pressed {
		system.mouse_key_states[key] = {
			is_pressed = true,
		}
	} else if action == .Release {
		system.mouse_key_states[key] = {
			is_pressed = false,
		}
	}
}

input_system_register_key :: proc(system: ^Input_System, key: Key_Code, action: Key_Action) {
	if action == .Pressed {
		system.key_states[key] = {
			is_pressed = true,
		}
	} else if action == .Release {
		system.key_states[key] = {
			is_pressed = false,
		}
	}
}

input_system_is_key_pressed :: proc(system: Input_System, key: Key_Code) -> bool {
	state, exists := system.key_states[key]
	return exists && state.is_pressed
}

input_system_is_mouse_key_pressed :: proc(system: Input_System, key: Mouse_Key_Code) -> bool {
	state, exists := system.mouse_key_states[key]
	return exists && state.is_pressed
}
