class_name LoadingScreen
extends Control
## Boot/loading screen: slow smoky ember backdrop (shader), small title, glowing gold progress line
## with status text, and the level's own words as a quote.

signal faded_out

const BG_SHADER := """
shader_type canvas_item;
uniform float time = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV * vec2(1.78, 1.0);
	float n = fbm(uv * 2.2 + vec2(time * 0.02, -time * 0.035));
	float m = fbm(uv * 4.0 - vec2(time * 0.03, time * 0.05) + n);
	vec3 c = vec3(0.012, 0.012, 0.02);
	c += vec3(0.30, 0.06, 0.03) * pow(m, 3.0) * smoothstep(1.1, 0.0, UV.y) * 0.9;
	c += vec3(0.10, 0.04, 0.16) * pow(n, 4.0);
	vec2 d = UV - 0.5;
	c *= 1.0 - dot(d, d) * 1.6;
	COLOR = vec4(c, 1.0);
}
"""

var progress := 0.0
var status := "Awakening"
var _shown := 0.0
var _disp := 0.0
var _t := 0.0
var _fading := false
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _fg: Control
var _map: TextureRect
var _map_mat: ShaderMaterial
var _reveal := 0.0
var level_title := "EX ODYSSEY"
var map_caption := "the map of the odyssey"
var quote := "\"The Devil hath taken thy Soul...  Go, and Return!\""
var ref_dir := "res://assets/ee_ref"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BG_SHADER
	_bg_mat.shader = sh
	_bg.material = _bg_mat
	add_child(_bg)
	# "Map of the Odyssey": the level's canonical EE-minimap art paints itself in as the world builds.
	var art := Minimap.load_art(ref_dir)
	if art:
		art.generate_mipmaps()
		var tex := ImageTexture.create_from_image(art)
		_map = TextureRect.new()
		_map.texture = tex
		_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_mat = ShaderMaterial.new()
		var ms := Shader.new()
		ms.code = Minimap.MAP_SHADER
		_map_mat.shader = ms
		_map_mat.set_shader_parameter("map_tex", tex)
		_map_mat.set_shader_parameter("tex_size", Vector2(art.get_width(), art.get_height()))
		_map_mat.set_shader_parameter("radius", 20.0)
		_map.material = _map_mat
		add_child(_map)
	_fg = Control.new()
	_fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.draw.connect(_draw_fg)
	add_child(_fg)

func set_progress(p: float, text: String = "") -> void:
	progress = clampf(p, 0.0, 1.0)
	if text != "":
		status = text

func fade_out(time: float = 1.2) -> void:
	_fading = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, time).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		visible = false
		faded_out.emit())

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_shown = minf(1.0, _shown + delta * 1.5)
	_disp = lerpf(_disp, progress, 1.0 - exp(-6.0 * delta))
	_bg_mat.set_shader_parameter("time", _t)
	_reveal = lerpf(_reveal, _disp, 1.0 - exp(-3.0 * delta))
	if _map:
		var r := _map_rect()
		_map.position = r.position
		_map.size = r.size
		_map.modulate.a = _shown
		_map_mat.set_shader_parameter("rect_size", r.size)
		_map_mat.set_shader_parameter("reveal", _reveal)
		_map_mat.set_shader_parameter("time", _t)
	_fg.queue_redraw()

func reveal_progress() -> float:
	return _reveal if _map else 1.0

func _map_rect() -> Rect2:
	var w := minf(size.x - 240.0, (size.y - 440.0) * 2.0)
	return Rect2(Vector2((size.x - w) * 0.5, 196.0), Vector2(w, w * 0.5))

func _draw_fg() -> void:
	if _t < 1.0:
		UITheme.warm_glyphs(_fg)
	var W := size.x
	var H := size.y
	var a := _shown
	var f := UITheme.title(20, 700)
	_fg.draw_string_outline(f, Vector2(0, 118), level_title, HORIZONTAL_ALIGNMENT_CENTER, W, 58, 10, Color(1, 0.7, 0.3, 0.06 * a))
	_fg.draw_string(f, Vector2(0, 118), level_title, HORIZONTAL_ALIGNMENT_CENTER, W, 58, Color(UITheme.GOLD, 0.92 * a))
	_fg.draw_string(UITheme.serif_italic(500), Vector2(0, 162), map_caption, HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color(0.95, 0.9, 0.82, 0.6 * a))
	var mr := _map_rect() if _map else Rect2(0, H * 0.4, W, 0)
	if _map:
		var frame := mr.grow(10)
		var sb := UITheme.glass_box(26, 0.5)
		sb.border_color = Color(UITheme.GOLD, 0.18 * a)
		_fg.draw_style_box(sb, frame)
	# progress line
	var lw := 560.0
	var x0 := W * 0.5 - lw * 0.5
	var ly := mr.end.y + 60.0
	_fg.draw_line(Vector2(x0, ly), Vector2(x0 + lw, ly), Color(1, 1, 1, 0.1 * a), 2.0, true)
	var xe := x0 + lw * _disp
	_fg.draw_line(Vector2(x0, ly), Vector2(xe, ly), Color(UITheme.GOLD, a), 2.0, true)
	for i in 5:
		_fg.draw_circle(Vector2(xe, ly), 14.0 - i * 2.6, Color(1.0, 0.8, 0.45, (0.04 + i * 0.04) * a))
	_fg.draw_circle(Vector2(xe, ly), 2.6, Color(1, 0.97, 0.9, a))
	var dots := ".".repeat(int(_t * 2.5) % 4)
	_fg.draw_string(UITheme.hud_medium(6), Vector2(0, ly + 40), status.to_upper() + dots, HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(1, 1, 1, 0.55 * a))
	_fg.draw_string(UITheme.hud(2), Vector2(x0 + lw + 18, ly + 7), "%d%%" % int(round(_disp * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.4 * a))
	var q := quote
	_fg.draw_string(UITheme.serif_italic(500), Vector2(0, H - 36), q, HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(0.95, 0.88, 0.8, 0.4 * a))
