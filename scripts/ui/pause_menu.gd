class_name PauseMenu
extends Control
## Esc menu over a frosted, darkened blur of the frozen frame. Keyboard/gamepad navigable.
## Left: title + run info + actions. Right: settings (volumes, zoom, quality preset, fullscreen, hints)
## and a controls card.

signal resume_requested
signal restart_requested
signal quit_title_requested
signal quit_requested
signal setting_changed(key: String, value: Variant)
signal ui_sound(name: String)

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 1.0;
void fragment() {
	vec3 c = vec3(0.0);
	float lod = 3.2 * amount;
	vec2 px = SCREEN_PIXEL_SIZE * 6.0 * amount;
	c += textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.4;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0, px.y), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0, px.y), lod).rgb * 0.15;
	vec2 d = UV - vec2(0.25, 0.5);
	float shade = mix(0.42, 0.75, smoothstep(0.0, 1.1, length(d)));
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), 0.35 * amount);
	COLOR = vec4(c * mix(1.0, 1.0 - shade, amount), 1.0);
}
"""

var settings: GameSettings
var info_zone := ""
var info_time := ""
var info_coins := ""
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _root: Control
var _left: VBoxContainer
var _settings_panel: PanelContainer
var _buttons: Array[Button] = []
var _quality_btns: Array[Button] = []
var _fs_btn: Button
var _hint_btn: Button
var _open := false
var _a := 0.0
var _info: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.menu_theme()
	visible = false
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	_bg_mat.shader = sh
	_bg.material = _bg_mat
	add_child(_bg)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_info = Control.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.draw.connect(_draw_info)
	_root.add_child(_info)
	_left = VBoxContainer.new()
	_left.position = Vector2(150, 430)
	_left.add_theme_constant_override(&"separation", 6)
	_root.add_child(_left)
	for pair in [["RESUME", _on_resume], ["RESTART", _on_restart], ["SETTINGS", _on_settings],
			["QUIT TO TITLE", _on_quit_title], ["QUIT GAME", _on_quit]]:
		var b := Button.new()
		b.text = pair[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(380, 54)
		b.pressed.connect(pair[1])
		b.focus_entered.connect(func(): ui_sound.emit("ui_move"))
		b.mouse_entered.connect(func(): b.grab_focus())
		_left.add_child(b)
		_buttons.append(b)
	_build_settings()

func _build_settings() -> void:
	_settings_panel = PanelContainer.new()
	var sb := UITheme.glass_box(22, 0.62)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 34
	sb.content_margin_bottom = 34
	_settings_panel.add_theme_stylebox_override(&"panel", sb)
	_settings_panel.position = Vector2(760, 250)
	_settings_panel.custom_minimum_size = Vector2(700, 0)
	_root.add_child(_settings_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	_settings_panel.add_child(v)
	var head := Label.new()
	head.text = "SETTINGS"
	head.add_theme_font_override(&"font", UITheme.title(8, 700))
	head.add_theme_font_size_override(&"font_size", 34)
	head.add_theme_color_override(&"font_color", UITheme.GOLD)
	v.add_child(head)
	v.add_child(_spacer(4))
	_slider_row(v, "MASTER VOLUME", "master", 0.0, 1.0, 0.01)
	_slider_row(v, "MUSIC & AMBIENCE", "music", 0.0, 1.0, 0.01)
	_slider_row(v, "EFFECTS", "sfx", 0.0, 1.0, 0.01)
	_slider_row(v, "CAMERA ZOOM", "zoom", 20.0, 60.0, 1.0)
	# quality
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override(&"separation", 8)
	var ql := Label.new()
	ql.text = "QUALITY"
	ql.custom_minimum_size = Vector2(250, 0)
	ql.add_theme_color_override(&"font_color", UITheme.INK_DIM)
	qrow.add_child(ql)
	for i in GameSettings.QUALITY_NAMES.size():
		var b := Button.new()
		b.text = GameSettings.QUALITY_NAMES[i]
		b.toggle_mode = true
		b.add_theme_font_size_override(&"font_size", 22)
		b.custom_minimum_size = Vector2(88, 42)
		b.pressed.connect(func(): _set_quality(i))
		b.focus_entered.connect(func(): ui_sound.emit("ui_move"))
		qrow.add_child(b)
		_quality_btns.append(b)
	v.add_child(qrow)
	_fs_btn = _toggle_row(v, "FULLSCREEN", func(on): setting_changed.emit("fullscreen", on))
	_hint_btn = _toggle_row(v, "CONTROL HINTS", func(on): setting_changed.emit("show_hints", on))
	v.add_child(_spacer(6))
	var ctl := Label.new()
	ctl.text = "ARROWS / WASD  move      SPACE  jump      G  god mode\nM  map      SHIFT+R  retry      WHEEL / + -  zoom      F11  fullscreen"
	ctl.add_theme_font_size_override(&"font_size", 19)
	ctl.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.45))
	v.add_child(ctl)
	_settings_panel.visible = false

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _slider_row(parent: Control, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(250, 0)
	l.add_theme_color_override(&"font_color", UITheme.INK_DIM)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(300, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.name = key
	var val := Label.new()
	val.custom_minimum_size = Vector2(60, 0)
	val.add_theme_font_override(&"font", UITheme.hud(1))
	s.value_changed.connect(func(x: float):
		val.text = _fmt(key, x)
		setting_changed.emit(key, x))
	row.add_child(s)
	row.add_child(val)
	parent.add_child(row)

func _fmt(key: String, x: float) -> String:
	return "%d" % int(x) if key == "zoom" else "%d%%" % int(round(x * 100.0))

func _toggle_row(parent: Control, text: String, cb: Callable) -> Button:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(250, 0)
	l.add_theme_color_override(&"font_color", UITheme.INK_DIM)
	row.add_child(l)
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(120, 42)
	b.add_theme_font_size_override(&"font_size", 22)
	b.toggled.connect(func(on: bool):
		b.text = "ON" if on else "OFF"
		cb.call(on))
	b.focus_entered.connect(func(): ui_sound.emit("ui_move"))
	row.add_child(b)
	parent.add_child(row)
	return b

func _set_quality(i: int) -> void:
	for j in _quality_btns.size():
		_quality_btns[j].set_pressed_no_signal(j == i)
	setting_changed.emit("quality", i)
	ui_sound.emit("ui_select")

func sync_from_settings() -> void:
	if settings == null:
		return
	for key in ["master", "music", "sfx", "zoom"]:
		var s := _settings_panel.find_child(key, true, false) as HSlider
		if s:
			s.set_value_no_signal(float(settings.get(key)))
			(s.get_parent().get_child(2) as Label).text = _fmt(key, s.value)
	for j in _quality_btns.size():
		_quality_btns[j].set_pressed_no_signal(j == settings.quality)
	_fs_btn.set_pressed_no_signal(settings.fullscreen)
	_fs_btn.text = "ON" if settings.fullscreen else "OFF"
	_hint_btn.set_pressed_no_signal(settings.show_hints)
	_hint_btn.text = "ON" if settings.show_hints else "OFF"

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_settings_panel.visible = false
	sync_from_settings()
	_buttons[0].grab_focus()

func close() -> void:
	_open = false
	get_viewport().gui_release_focus()

func is_open() -> bool:
	return _open

func _process(delta: float) -> void:
	_a = lerpf(_a, 1.0 if _open else 0.0, 1.0 - exp(-12.0 * delta))
	if not _open and _a < 0.01:
		visible = false
	_bg_mat.set_shader_parameter("amount", _a)
	_root.modulate.a = _a
	_root.position.x = (1.0 - _a) * -40.0
	_info.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ee_pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings_panel.visible:
			_settings_panel.visible = false
			_buttons[2].grab_focus()
		else:
			_on_resume()

func _draw_info() -> void:
	var f := UITheme.title(14, 700)
	_info.draw_string(f, Vector2(150, 330), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 84, Color(1, 0.96, 0.88))
	_info.draw_line(Vector2(154, 360), Vector2(154 + 300, 360), Color(UITheme.GOLD, 0.7), 1.5, true)
	var it := UITheme.serif_italic(500)
	_info.draw_string(it, Vector2(154, 400), _title_case(info_zone), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.92, 0.82, 0.8))
	var hud := UITheme.hud_medium(3)
	_info.draw_string(hud, Vector2(154, _left.position.y + 5 * 60 + 60), "%s     %s" % [info_time, info_coins], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.5))

func _on_resume() -> void:
	ui_sound.emit("ui_select")
	resume_requested.emit()

func _on_restart() -> void:
	ui_sound.emit("ui_select")
	restart_requested.emit()

func _on_settings() -> void:
	ui_sound.emit("ui_select")
	_settings_panel.visible = not _settings_panel.visible
	if _settings_panel.visible:
		(_settings_panel.find_child("master", true, false) as Control).grab_focus()

func _on_quit_title() -> void:
	ui_sound.emit("ui_select")
	quit_title_requested.emit()

func _on_quit() -> void:
	quit_requested.emit()

static func _title_case(s: String) -> String:
	var out: PackedStringArray = []
	for w in s.split(" ", false):
		out.append(w.substr(0, 1).to_upper() + w.substr(1).to_lower())
	return " ".join(out)