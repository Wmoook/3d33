class_name InputSetup
## Registers the game's input actions at runtime (so project.godot stays minimal).
## Mirrors Everybody Edits (upstream src/Me.as getPlayerInput + src/KeyBinding.as):
##   left  = Left arrow / A        (physical key -> Q on AZERTY, like EE's azerty binding)
##   right = Right arrow / D
##   up    = Up arrow / W          (physical -> Z on AZERTY)
##   down  = Down arrow / S
##   jump  = Space ONLY            (Up/W is "up", not jump: the sim decides what up does)
##   G = toggle god mode, M = toggle minimap, Shift+R = retry run (EE retryRun binding)
## Extras: H best-run ghost, F3 collision overlay, Esc pause, +/- and mouse wheel zoom, F11 fullscreen, gamepad (stick/dpad, A jump, Y god, Start pause, Back map).

const DEADZONE := 0.45

static func ensure_actions() -> void:
	_action(&"ee_left", [_key(KEY_LEFT), _key(KEY_A), _joy_btn(JOY_BUTTON_DPAD_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_action(&"ee_right", [_key(KEY_RIGHT), _key(KEY_D), _joy_btn(JOY_BUTTON_DPAD_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_action(&"ee_up", [_key(KEY_UP), _key(KEY_W), _joy_btn(JOY_BUTTON_DPAD_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action(&"ee_down", [_key(KEY_DOWN), _key(KEY_S), _joy_btn(JOY_BUTTON_DPAD_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action(&"ee_jump", [_key(KEY_SPACE), _joy_btn(JOY_BUTTON_A)])
	_action(&"ee_god", [_key(KEY_G), _joy_btn(JOY_BUTTON_Y)])
	_action(&"ee_minimap", [_key(KEY_M), _joy_btn(JOY_BUTTON_BACK)])
	_action(&"ee_retry", [_key(KEY_R)])  # Shift is checked by the game, like EE's Key(82, true)
	_action(&"ee_pause", [_key(KEY_ESCAPE), _joy_btn(JOY_BUTTON_START)])
	_action(&"ee_zoom_in", [_key(KEY_EQUAL), _key(KEY_KP_ADD), _joy_btn(JOY_BUTTON_RIGHT_SHOULDER)])
	_action(&"ee_zoom_out", [_key(KEY_MINUS), _key(KEY_KP_SUBTRACT), _joy_btn(JOY_BUTTON_LEFT_SHOULDER)])
	_action(&"ee_fullscreen", [_key(KEY_F11)])
	_action(&"ee_collision", [_key(KEY_F3)])
	_action(&"ee_ghost", [_key(KEY_H), _joy_btn(JOY_BUTTON_X)])

static func _action(name: StringName, events: Array) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, DEADZONE)
	for e in events:
		InputMap.action_add_event(name, e)

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _joy_btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = -1
	return e

static func _joy_axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = -1
	return e
