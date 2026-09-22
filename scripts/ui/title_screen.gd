class_name TitleScreen
extends Control
## Cinematic title overlay on top of the live world flyover: letterbox bars, gold-gradient "EX ODYSSEY"
## that resolves from wide tracking, the level's own line as subtitle, pulsing "PRESS ANY KEY".

signal dismissed

const TITLE_SHADER := """
shader_type canvas_item;
uniform float y0 = 0.4;
uniform float y1 = 0.52;
uniform float sheen = 0.0;
void fragment() {
	float g = clamp((SCREEN_UV.y - y0) / (y1 - y0), 0.0, 1.0);
	vec3 top = vec3(1.0, 0.97, 0.86);
	vec3 mid = vec3(1.0, 0.8, 0.42);
	vec3 bot = vec3(0.62, 0.36, 0.12);
	vec3 col = g < 0.55 ? mix(top, mid, g / 0.55) : mix(mid, bot, (g - 0.55) / 0.45);
	float s = exp(-pow((SCREEN_UV.x - sheen) * 9.0 - (SCREEN_UV.y - y0) * 3.0, 2.0));
	col += vec3(1.0, 0.95, 0.8) * s * 0.55;
	COLOR = vec4(col * COLOR.rgb, COLOR.a);
}
"""

const VIG_SHADER := """
shader_type canvas_item;
uniform float amount = 1.0;
void fragment() {
	vec2 d = (UV - vec2(0.5, 0.46)) * vec2(1.0, 1.5);
	float v = smoothstep(0.05, 0.75, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, amount * (0.18 + 0.5 * v));
}
"""

var _t := 0.0
var _out := -1.0
var _title_ctl: Control
var _title_mat: ShaderMaterial
var _vig: ColorRect
var _vig_mat: ShaderMaterial
var accept_input := false
var attract := false          # attract-mode demo: big title recedes, a small caption shows
var _attract_k := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig = ColorRect.new()
	_vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = _shader(VIG_SHADER)
	_vig.material = _vig_mat
	_vig.show_behind_parent = true
	add_child(_vig)
	_title_ctl = Control.new()
	_title_ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_mat = ShaderMaterial.new()
	_title_mat.shader = _shader(TITLE_SHADER)
	_title_ctl.material = _title_mat
	_title_ctl.draw.connect(_draw_title)
	add_child(_title_ctl)

static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func restart_intro() -> void:
	_t = 0.0
	_out = -1.0
	accept_input = false
	visible = true

func dismiss() -> void:
	if _out < 0.0:
		_out = 0.0
		accept_input = false

func is_dismissing() -> bool:
	return _out >= 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t > 2.2:
		accept_input = _out < 0.0
	if _out >= 0.0:
		_out += delta
		if _out > 0.9:
			visible = false
			dismissed.emit()
	_attract_k = move_toward(_attract_k, 1.0 if attract else 0.0, delta * 1.2)
	_title_mat.set_shader_parameter("sheen", fmod(_t * 0.16, 1.6) - 0.3)
	_vig_mat.set_shader_parameter("amount", _k(0.0, 1.5) * _outk())
	queue_redraw()
	_title_ctl.queue_redraw()

func _k(start: float, dur: float) -> float:
	var x := clampf((_t - start) / dur, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _outk() -> float:
	return 1.0 if _out < 0.0 else 1.0 - clampf(_out / 0.7, 0.0, 1.0)

func _draw() -> void:
	var W := size.x
	var H := size.y
	var o := _outk()
	# letterbox bars
	var bar := 96.0 * _k(0.0, 1.4) * (o * o)
	draw_rect(Rect2(0, 0, W, bar), Color.BLACK)
	draw_rect(Rect2(0, H - bar, W, bar), Color.BLACK)
	var cx := W * 0.5
	var cy := H * 0.47
	var a := o * (1.0 - _attract_k)
	# eyebrow
	var eb := "A  REIMAGINING  OF  EX  CREW  ODYSSEY"
	var ef := UITheme.hud_medium(9)
	draw_string(ef, Vector2(0, cy - 150), eb, HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color(1, 1, 1, 0.55 * _k(0.7, 1.6) * a))
	# rule + diamond
	var rk := _k(2.3, 1.4)
	var rl := 330.0 * rk
	var ry := cy + 34.0
	var gold := UITheme.GOLD
	draw_line(Vector2(cx - 18 - rl, ry), Vector2(cx - 18, ry), Color(gold, 0.75 * rk * a), 1.5, true)
	draw_line(Vector2(cx + 18, ry), Vector2(cx + 18 + rl, ry), Color(gold, 0.75 * rk * a), 1.5, true)
	var ds := 6.0 * rk
	if ds > 0.5:
		draw_colored_polygon(PackedVector2Array([Vector2(cx, ry - ds), Vector2(cx + ds, ry), Vector2(cx, ry + ds), Vector2(cx - ds, ry)]), Color(gold, rk * a))
	# subtitle (the level's own text)
	var sub := "The Devil hath taken thy Soul...  Go, and Return!"
	draw_string(UITheme.serif_italic(500), Vector2(0, cy + 96), sub, HORIZONTAL_ALIGNMENT_CENTER, W, 42, Color(0.96, 0.9, 0.82, 0.92 * _k(3.0, 1.6) * a))
	# attract-mode caption
	if _attract_k > 0.01:
		var ak := _attract_k * o
		UITheme.draw_spaced(self, UITheme.title(0, 800), Vector2(52, 176), "EX ODYSSEY", 44, 8.0, Color(UITheme.GOLD, 0.9 * ak))
		draw_string(UITheme.serif_italic(500), Vector2(54, 214), "the descent  -  a recorded run", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.93, 0.85, 0.7 * ak))
	# press any key
	if _t > 4.2:
		var pk := _k(4.2, 1.0) * (0.55 + 0.45 * sin((_t - 4.2) * 2.6)) * o
		var pf := UITheme.hud(10)
		draw_string(pf, Vector2(0, H * 0.8), "PRESS  ANY  KEY", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(1, 1, 1, pk))
	# footer in letterbox
	var fa := _k(1.2, 1.5) * o * 0.45
	draw_string(UITheme.hud_medium(3), Vector2(48, H - 38), "Based on  \"EX Crew Odyssey\"  -  Everybody Edits", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, fa))
	draw_string(UITheme.hud_medium(3), Vector2(W - 548, H - 38), "ARROWS / WASD   SPACE   G   M   ESC", HORIZONTAL_ALIGNMENT_RIGHT, 500, 17, Color(1, 1, 1, fa))

func _draw_title() -> void:
	var W := size.x
	var H := size.y
	var cy := H * 0.47
	var k := _k(1.1, 2.8)
	var o := _outk()
	var spacing := lerpf(70.0, 22.0, k) + (1.0 - o) * 30.0
	var f := UITheme.title(0, 800)
	var fs := 164
	var text := "EX ODYSSEY"
	var tw := UITheme.spaced_width(f, text, fs, spacing)
	var p := Vector2(W * 0.5 - tw * 0.5, cy)
	var a := k * o * (1.0 - _attract_k)
	_title_mat.set_shader_parameter("y0", (cy - fs * 0.72) / H)
	_title_mat.set_shader_parameter("y1", (cy + 4.0) / H)
	# soft glow halo + drop shadow, then the gradient face
	UITheme.draw_spaced(_title_ctl, f, p, text, fs, spacing, Color(1.0, 0.65, 0.25, 0.05 * a), 26)
	UITheme.draw_spaced(_title_ctl, f, p, text, fs, spacing, Color(1.0, 0.7, 0.3, 0.1 * a), 12)
	UITheme.draw_spaced(_title_ctl, f, p + Vector2(0, 6), text, fs, spacing, Color(0.0, 0.0, 0.0, 0.5 * a))
	UITheme.draw_spaced(_title_ctl, f, p, text, fs, spacing, Color(1, 1, 1, a))
