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
## Level select: configs from LevelCatalog (id, title, eyebrow, subtitle, credit, ref_dir...).
var levels: Array = []
var current_index := 0          # the level that is loaded
var selected_index := 0         # the highlighted card
var _cards: Array[TextureRect] = []
var _card_mats: Array[ShaderMaterial] = []
var _sel_k: Array[float] = []
var _sel_flash := 0.0
const CARD := Vector2(300, 150)
const CARD_GAP := 48.0

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

## Builds one framed minimap card per level (each level's canonical minimap art from its ref_dir).
func set_levels(cfgs: Array, current_id: String) -> void:
	levels = cfgs
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_card_mats.clear()
	_sel_k.clear()
	current_index = 0
	for i in levels.size():
		if str(levels[i].get("id", "")) == current_id:
			current_index = i
		var art := Minimap.load_art(str(levels[i].get("ref_dir", "res://assets/ee_ref")))
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var mat := ShaderMaterial.new()
		mat.shader = _shader(Minimap.MAP_SHADER)
		if art:
			art.generate_mipmaps()
			var tex := ImageTexture.create_from_image(art)
			tr.texture = tex
			mat.set_shader_parameter("map_tex", tex)
			mat.set_shader_parameter("tex_size", Vector2(art.get_width(), art.get_height()))
		mat.set_shader_parameter("radius", 12.0)
		mat.set_shader_parameter("glow", 0.45)
		tr.material = mat
		tr.size = CARD
		add_child(tr)
		_cards.append(tr)
		_card_mats.append(mat)
		_sel_k.append(0.0)
	selected_index = current_index

func current_cfg() -> Dictionary:
	return levels[current_index] if current_index < levels.size() else {}

func selected_cfg() -> Dictionary:
	return levels[selected_index] if selected_index < levels.size() else {}

## Move the highlight; returns true if it moved.
func select_delta(d: int) -> bool:
	if levels.size() < 2:
		return false
	var n := clampi(selected_index + d, 0, levels.size() - 1)
	if n == selected_index:
		return false
	selected_index = n
	_sel_flash = 1.0
	return true

static func _spaced_caps(t: String) -> String:
	return t.to_upper().replace(" ", "  ")

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
	_sel_flash = maxf(0.0, _sel_flash - delta * 2.5)
	_layout_cards(delta)
	_title_mat.set_shader_parameter("sheen", fmod(_t * 0.16, 1.6) - 0.3)
	_vig_mat.set_shader_parameter("amount", _k(0.0, 1.5) * _outk())
	queue_redraw()
	_title_ctl.queue_redraw()

func _layout_cards(delta: float) -> void:
	var n := _cards.size()
	if n == 0:
		return
	var W := size.x
	var H := size.y
	var total := n * CARD.x + (n - 1) * CARD_GAP
	var ca := _k(4.0, 1.2) * _outk() * (1.0 - _attract_k) * (1.0 if n > 1 else 0.0)
	for i in n:
		_sel_k[i] = lerpf(_sel_k[i], 1.0 if i == selected_index else 0.0, 1.0 - exp(-10.0 * delta))
		var sc := 1.0 + 0.1 * _sel_k[i]
		var sz := CARD * sc
		var cxy := Vector2(W * 0.5 - total * 0.5 + i * (CARD.x + CARD_GAP) + CARD.x * 0.5, H - 96.0 - 34.0 - CARD.y * 0.5)
		_cards[i].size = sz
		_cards[i].position = cxy - sz * 0.5 + Vector2(0, (1.0 - ca) * 30.0)
		_cards[i].modulate = Color(1, 1, 1, ca * lerpf(0.55, 1.0, _sel_k[i]))
		_card_mats[i].set_shader_parameter("rect_size", sz)
		_card_mats[i].set_shader_parameter("time", _t)

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
	var cfg := current_cfg()
	var eb := _spaced_caps(str(cfg.get("eyebrow", "")))
	var ef := UITheme.hud_medium(9)
	var ek := _k(0.7, 1.6) * a
	UITheme.draw_scrim(self, Vector2(cx, cy - 157), Vector2(ef.get_string_size(eb, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 300.0, 70.0), 0.45 * ek)
	draw_string(ef, Vector2(0, cy - 148), eb, HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color(0, 0, 0, 0.5 * ek))
	draw_string(ef, Vector2(0, cy - 150), eb, HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color(1, 1, 1, 0.78 * ek))
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
	var sub := str(cfg.get("subtitle", ""))
	draw_string(UITheme.serif_italic(500), Vector2(0, cy + 96), sub, HORIZONTAL_ALIGNMENT_CENTER, W, 42, Color(0.96, 0.9, 0.82, 0.92 * _k(3.0, 1.6) * a))
	# attract-mode caption
	if _attract_k > 0.01:
		var ak := _attract_k * o
		UITheme.draw_spaced(self, UITheme.title(0, 800), Vector2(52, 176), str(cfg.get("title", "")), 44, 8.0, Color(UITheme.GOLD, 0.9 * ak))
		draw_string(UITheme.serif_italic(500), Vector2(54, 214), "a recorded run", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.93, 0.85, 0.7 * ak))
	# level select cards: frame + label for each (the map art itself is a child TextureRect)
	var multi := _cards.size() > 1
	if multi:
		var ca := _k(4.0, 1.2) * o * (1.0 - _attract_k)
		for i in _cards.size():
			var r := Rect2(_cards[i].position, _cards[i].size)
			var sk := _sel_k[i]
			var sb := UITheme.glass_box(16, 0.55 * ca)
			sb.border_color = Color(UITheme.GOLD, (0.15 + 0.7 * sk) * ca)
			sb.set_border_width_all(1 if sk < 0.5 else 2)
			draw_style_box(sb, r.grow(8))
			var nm := str(levels[i].get("title", ""))
			var lf := UITheme.hud(4)
			draw_string(lf, Vector2(r.position.x, r.end.y + 32), nm, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20,
				Color(1, 1, 1, lerpf(0.45, 1.0, sk) * ca))
			if i == current_index:
				draw_circle(Vector2(r.position.x + 16, r.position.y + 16), 4.0, Color(UITheme.GOLD, ca))
	# prompt
	if _t > 4.2:
		var pk := _k(4.2, 1.0) * (0.55 + 0.45 * sin((_t - 4.2) * 2.6)) * o
		var pf := UITheme.hud(10)
		var py := (H - 96.0 - 34.0 - CARD.y * 0.5 - CARD.y * 0.55 - 40.0) if multi else H * 0.8
		var prompt := "PRESS  ANY  KEY"
		if multi and selected_index != current_index:
			prompt = "ENTER   TRAVEL  TO  " + _spaced_caps(str(selected_cfg().get("title", "")))
		elif multi:
			prompt = "ENTER   PLAY          LEFT / RIGHT   CHOOSE  LEVEL"
		var pw := pf.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		UITheme.draw_scrim(self, Vector2(W * 0.5, py - 8), Vector2(pw + 360.0, 96.0), 0.65 * _k(4.2, 1.0) * o)
		var pv := (0.78 + 0.22 * sin((_t - 4.2) * 2.6)) * _k(4.2, 1.0) * o
		draw_string(pf, Vector2(0, py + 2), prompt, HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(0, 0, 0, 0.6 * pv))
		draw_string(pf, Vector2(0, py), prompt, HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(1, 0.97, 0.9, pv))
	# footer in letterbox
	var fa := _k(1.2, 1.5) * o * 0.45
	draw_string(UITheme.hud_medium(3), Vector2(48, H - 38), str(cfg.get("credit", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, fa))
	draw_string(UITheme.hud_medium(3), Vector2(W - 548, H - 38), "ARROWS / WASD   SPACE   G   M   ESC", HORIZONTAL_ALIGNMENT_RIGHT, 500, 17, Color(1, 1, 1, fa))

func _draw_title() -> void:
	var W := size.x
	var H := size.y
	var cy := H * 0.47
	var k := _k(1.1, 2.8)
	var o := _outk()
	var spacing := lerpf(70.0, 22.0, k) + (1.0 - o) * 30.0
	var f := UITheme.title(0, 800)
	var text := str(current_cfg().get("title", ""))
	var fs := 164
	var tw := UITheme.spaced_width(f, text, fs, spacing)
	var fit := W * 0.84
	if tw > fit and tw > 0.0:     # long titles (FORGOTTEN VEIL) scale down to fit
		fs = int(fs * fit / tw)
		spacing *= fit / tw
		tw = UITheme.spaced_width(f, text, fs, spacing)
	var p := Vector2(W * 0.5 - tw * 0.5, cy)
	var a := k * o * (1.0 - _attract_k)
	_title_mat.set_shader_parameter("y0", (cy - fs * 0.72) / H)
	_title_mat.set_shader_parameter("y1", (cy + 4.0) / H)
	# soft glow halo + drop shadow, then the gradient face
	UITheme.draw_spaced(_title_ctl, f, p, text, fs, spacing, Color(1.0, 0.65, 0.25, 0.05 * a), 26)
	UITheme.draw_spaced(_title_ctl, f, p, text, fs, spacing, Color(1.0, 0.7, 0.3, 0.1 * a), 12)
	UITheme.draw_spaced(_title_ctl, f, p + Vector2(0, 6), text, fs, spacing, Color(0.0, 0.0, 0.0, 0.5 * a))
	UITheme.draw_spaced(_title_ctl, f, p, text, fs, spacing, Color(1, 1, 1, a))
