class_name GameHUD
extends Control
## Minimal AAA-style HUD, all vector-drawn: coin counters (spinning coin icons with pickup pop), key ring
## timers, elapsed time, current zone, god-mode pill, crown, control hints, damage/death vignette.
## The game pushes a state Dictionary every frame via set_state().

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.0, 1.0);
uniform float amount = 0.0;
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.25, 0.85, length(d * vec2(1.25, 1.0)));
	COLOR = vec4(tint.rgb, v * amount);
}
"""

var _s := {"coins": 0, "coins_total": 0, "blue": 0, "blue_total": 0, "keys": {}, "time": 0.0, "god": false,
	"crown": false, "zone": "", "visible": true, "best": -1.0, "coin_label": ""}
var _t := 0.0
var _pop_gold := 0.0
var _pop_blue := 0.0
var _floaters: Array = []   # [{pos, text, t, color}]
var _alpha := 0.0
var _hint_t := 0.0
var show_hints := true
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _vig_amount := 0.0
var _caption := ""
var _caption_t := -1.0
var _toast_title := ""
var _toast_text := ""
var _toast_t := -1.0
var _toast_len := 4.0

## Small centred caption (e.g. "TRIAL VII" when entering a trial room); fades in, holds, fades out.
func caption(text: String) -> void:
	if text == _caption and _caption_t >= 0.0 and _caption_t < 2.5:
		return
	_caption = text
	_caption_t = 0.0

## Small one-off message pill (e.g. "COIN DOOR  needs 16 gold coins"), top-center under the god pill.
func toast(title_s: String, text: String, secs: float = 4.0) -> void:
	_toast_title = title_s
	_toast_text = text
	_toast_len = secs
	_toast_t = 0.0
	_pop_gold = 1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vignette.material = _vig_mat
	add_child(_vignette)
	_vignette.show_behind_parent = true

func set_state(s: Dictionary) -> void:
	for k in s:
		if k == "coins" and s[k] > _s.coins:
			_pop_gold = 1.0
			_floaters.append({"pos": Vector2(118, 58), "text": "+%d" % (s[k] - _s.coins), "t": 0.0, "color": UITheme.GOLD})
		elif k == "blue" and s[k] > _s.blue:
			_pop_blue = 1.0
			_floaters.append({"pos": Vector2(118, 122), "text": "+%d" % (s[k] - _s.blue), "t": 0.0, "color": UITheme.BLUE_COIN})
		_s[k] = s[k]

func flash(color: Color, amount: float) -> void:
	_vig_mat.set_shader_parameter("tint", color)
	_vig_amount = maxf(_vig_amount, amount)

func reset_hints() -> void:
	_hint_t = 0.0

func _process(delta: float) -> void:
	_t += delta
	_hint_t += delta
	_pop_gold = maxf(0.0, _pop_gold - delta * 2.8)
	_pop_blue = maxf(0.0, _pop_blue - delta * 2.8)
	_alpha = lerpf(_alpha, 1.0 if _s.visible else 0.0, 1.0 - exp(-5.0 * delta))
	_vig_amount = maxf(0.0, _vig_amount - delta * 1.2)
	_vig_mat.set_shader_parameter("amount", _vig_amount)
	if _caption_t >= 0.0:
		_caption_t += delta
		if _caption_t > 3.2:
			_caption_t = -1.0
	if _toast_t >= 0.0:
		_toast_t += delta
		if _toast_t > _toast_len:
			_toast_t = -1.0
	for f in _floaters:
		f.t += delta
	_floaters = _floaters.filter(func(f): return f.t < 1.1)
	modulate.a = _alpha
	queue_redraw()

func _draw() -> void:
	if _alpha < 0.01:
		return
	var W := size.x
	var num := UITheme.hud()
	var lab := UITheme.hud_medium(5)
	# ---- coins panel (top-left)
	var rows := 1 + (1 if int(_s.blue_total) > 0 else 0)
	var panel := Rect2(36, 30, 250, 24 + rows * 62)
	draw_style_box(UITheme.glass_box(16, 0.5), panel)
	var spin := cos(_t * 2.2)
	_coin_row(Vector2(78, 72), int(_s.coins), int(_s.coins_total), false, spin, _pop_gold)
	if str(_s.coin_label) != "":
		draw_string(UITheme.hud(5), Vector2(113, 50), str(_s.coin_label), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UITheme.GOLD, 0.95))
	if rows > 1:
		_coin_row(Vector2(78, 134), int(_s.blue), int(_s.blue_total), true, cos(_t * 2.2 + 1.3), _pop_blue)
	if _s.crown:
		_draw_crown(Vector2(panel.end.x - 36, 58), 16.0)
	for f in _floaters:
		var a: float = 1.0 - f.t / 1.1
		var p: Vector2 = f.pos + Vector2(150 + f.t * 30, -f.t * 26)
		draw_string(num, p, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(f.color.r, f.color.g, f.color.b, a))
	# ---- key ring timers (below coins)
	var kx := 64.0
	var ky := panel.end.y + 44
	for color in [&"red", &"green", &"blue"]:
		var k: Array = _s.keys.get(color, [])
		if k.is_empty() or float(k[0]) <= 0.0:
			continue
		_key_ring(Vector2(kx, ky), color, float(k[0]), maxf(float(k[1]), 0.001))
		kx += 78
	# ---- time + zone (top-right)
	var t: float = _s.time
	var mins := int(t / 60.0)
	var secs := fmod(t, 60.0)
	var ts := "%02d:%05.2f" % [mins, secs]
	var tr := Rect2(W - 300, 30, 264, 86)
	draw_style_box(UITheme.glass_box(16, 0.5), tr)
	draw_string(lab, Vector2(tr.position.x + 24, 60), "TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.INK_DIM)
	var best: float = _s.best
	if best >= 0.0:
		var bs := "BEST  %02d:%05.2f" % [int(best / 60.0), fmod(best, 60.0)]
		draw_string(lab, Vector2(tr.position.x, 60), bs, HORIZONTAL_ALIGNMENT_RIGHT, tr.size.x - 22, 16, Color(UITheme.GOLD, 0.8))
	_shadow_string(num, Vector2(tr.position.x + 22, 102), ts, 42, UITheme.INK, HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 40)
	if str(_s.zone) != "":
		draw_string(UITheme.title(3, 600), Vector2(W - 536, tr.end.y + 34), str(_s.zone), HORIZONTAL_ALIGNMENT_RIGHT, 500, 18, Color(1, 1, 1, 0.5))
	# ---- god mode pill (top-center)
	if _s.god:
		var pw := 210.0
		var pr := Rect2(W * 0.5 - pw * 0.5, 34, pw, 40)
		var sb := UITheme.glass_box(20, 0.55)
		sb.border_color = Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.45 + 0.25 * sin(_t * 4.0))
		sb.set_border_width_all(2)
		draw_style_box(sb, pr)
		draw_string(UITheme.hud(6), Vector2(pr.position.x, pr.position.y + 29), "GOD MODE", HORIZONTAL_ALIGNMENT_CENTER, pw, 22, UITheme.GOLD)
	# ---- trial caption (top-center, below the pills)
	if _caption_t >= 0.0 and _caption != "":
		var ca := clampf(_caption_t / 0.5, 0.0, 1.0) * clampf((3.2 - _caption_t) / 0.9, 0.0, 1.0)
		var cf := UITheme.title(0, 700)
		var cw := UITheme.spaced_width(cf, _caption, 26, 8.0)
		var cp := Vector2(W * 0.5 - cw * 0.5, 372)   # below the zone card, so both can coexist
		UITheme.draw_scrim(self, Vector2(W * 0.5, cp.y - 9), Vector2(cw + 320.0, 110.0), 0.45 * ca)
		UITheme.draw_spaced(self, cf, cp + Vector2(0, 2), _caption, 26, 8.0, Color(0, 0, 0, 0.5 * ca))
		UITheme.draw_spaced(self, cf, cp, _caption, 26, 8.0, Color(UITheme.GOLD, 0.95 * ca))
		draw_line(Vector2(cp.x - 70, cp.y - 9), Vector2(cp.x - 16, cp.y - 9), Color(UITheme.GOLD, 0.6 * ca), 1.2, true)
		draw_line(Vector2(cp.x + cw + 16, cp.y - 9), Vector2(cp.x + cw + 70, cp.y - 9), Color(UITheme.GOLD, 0.6 * ca), 1.2, true)
	# ---- toast (top-center)
	if _toast_t >= 0.0:
		var ta := clampf(_toast_t / 0.4, 0.0, 1.0) * clampf((_toast_len - _toast_t) / 0.8, 0.0, 1.0)
		var tf := UITheme.hud(6)
		var bf := UITheme.hud_medium(2)
		var tw := tf.get_string_size(_toast_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var bw := bf.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var w := tw + bw + 110.0
		var r := Rect2(W * 0.5 - w * 0.5, 96 + (1.0 - ta) * -10.0, w, 48)
		var sb := UITheme.glass_box(24, 0.62 * ta)
		sb.border_color = Color(UITheme.GOLD, 0.5 * ta)
		sb.set_border_width_all(1)
		draw_style_box(sb, r)
		UITheme.draw_coin(self, r.position + Vector2(30, 24), 12.0, cos(_t * 2.2), false, 0.0)
		draw_string(tf, r.position + Vector2(54, 32), _toast_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UITheme.GOLD, ta))
		draw_string(bf, r.position + Vector2(66 + tw, 32), _toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.96, 0.9, 0.9 * ta))
	# ---- hints (bottom-left), fade out after a while
	if show_hints:
		var ha := clampf(1.0 - (_hint_t - 14.0) / 2.0, 0.0, 1.0) * clampf(_hint_t / 1.5, 0.0, 1.0)
		if ha > 0.0:
			UITheme.draw_scrim(self, Vector2(520, size.y - 50), Vector2(1500, 170), 0.45 * ha)
			var hy := size.y - 44
			var x := 44.0
			for pair in [["ARROWS / WASD", "move"], ["SPACE", "jump"], ["G", "god mode"], ["M", "map"], ["SHIFT+R", "retry"], ["H", "ghost"], ["F3", "collision"], ["ESC", "menu"]]:
				x = _hint(Vector2(x, hy), pair[0], pair[1], ha) + 26

func _coin_row(c: Vector2, n: int, total: int, blue: bool, spin: float, pop: float) -> void:
	var r := 19.0 * (1.0 + pop * 0.35 * sin(pop * PI))
	UITheme.draw_coin(self, c, r, spin, blue, pop)
	var num := UITheme.hud()
	var col := (UITheme.BLUE_COIN if blue else UITheme.GOLD).lerp(Color.WHITE, 0.55 + pop * 0.45)
	var s := str(n)
	_shadow_string(num, Vector2(c.x + 36, c.y + 15), s, 44, col)
	var w := num.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	if total > 0:
		draw_string(num, Vector2(c.x + 42 + w, c.y + 13), "/ %d" % total, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UITheme.INK_DIM)

func _key_ring(c: Vector2, color: StringName, left: float, dur: float) -> void:
	var kc: Color = UITheme.KEY_COLORS.get(color, Color.WHITE)
	var frac := clampf(left / dur, 0.0, 1.0)
	var urgent := left < 1.5
	var pulse := 1.0 + (0.08 * sin(_t * 18.0) if urgent else 0.0)
	var r := 26.0 * pulse
	draw_circle(c, r + 8, Color(0.03, 0.035, 0.05, 0.6))
	for i in 3:
		draw_circle(c, r + 12 - i * 3, Color(kc.r, kc.g, kc.b, 0.05))
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.12), 4.0, true)
	draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, kc, 5.0, true)
	# key glyph
	draw_arc(c + Vector2(-5, 0), 6.0, 0, TAU, 20, kc.lerp(Color.WHITE, 0.3), 3.0, true)
	draw_line(c + Vector2(1, 0), c + Vector2(12, 0), kc.lerp(Color.WHITE, 0.3), 3.0, true)
	draw_line(c + Vector2(8, 0), c + Vector2(8, 5), kc.lerp(Color.WHITE, 0.3), 3.0, true)
	draw_line(c + Vector2(12, 0), c + Vector2(12, 5), kc.lerp(Color.WHITE, 0.3), 3.0, true)
	draw_string(UITheme.hud(), c + Vector2(-40, r + 30), "%.1f" % left, HORIZONTAL_ALIGNMENT_CENTER, 80, 20, kc.lerp(Color.WHITE, 0.4))

func _draw_crown(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.3), c + Vector2(-s * 0.5, s * 0.1),
		c + Vector2(0, -s * 0.7), c + Vector2(s * 0.5, s * 0.1), c + Vector2(s, -s * 0.3), c + Vector2(s, s * 0.6)])
	draw_circle(c, s * 1.6, Color(1, 0.8, 0.3, 0.08))
	draw_colored_polygon(pts, UITheme.GOLD)
	draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.GOLD_DEEP, 2.0, true)

func _hint(p: Vector2, key: String, what: String, a: float) -> float:
	var f := UITheme.hud(2)
	var kw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 18
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.1 * a)
	sb.border_color = Color(1, 1, 1, 0.25 * a)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	draw_style_box(sb, Rect2(p + Vector2(0, -21), Vector2(kw, 30)))
	draw_string(f, p + Vector2(9, 0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.9 * a))
	draw_string(UITheme.hud_medium(1), p + Vector2(kw + 9, 0), what, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1, 0.6 * a))
	return p.x + kw + 9 + UITheme.hud_medium(1).get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x

func _shadow_string(f: Font, p: Vector2, s: String, sz: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(f, p + Vector2(0, 2), s, align, w, sz, Color(0, 0, 0, 0.45 * c.a))
	draw_string(f, p, s, align, w, sz, c)
