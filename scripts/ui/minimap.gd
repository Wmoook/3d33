class_name Minimap
extends Control
## The EE minimap IS the level's artwork (CONTRACTS: "THE CANONICAL ART"). Shows assets/ee_ref/minimap_ee.png
## (EE's exact World.getMinimapColor rule, 1 px per tile) beautifully presented:
## sharp-bilinear upscale (crisp painted pixels, anti-aliased edges) + a soft mip glow, vignette, rounded glass
## frame; live state from the sim: doors/gates shown open when passable, uncollected coins as glints
## (removed when collected), pulsing player marker, current-view rectangle.
## Modes (M cycles): OFF -> CORNER (whole map, bottom-right) -> FULL (paused map view: wheel/+- zoom toward the
## cursor, drag or arrows/WASD/stick to pan, M/Esc close) -> OFF.

signal full_opened
signal full_closed

enum Mode { OFF, CORNER, FULL }

const MAP_SHADER := """
shader_type canvas_item;
uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 tex_size = vec2(400.0, 200.0);
uniform vec2 center = vec2(0.5, 0.5);
uniform vec2 span = vec2(1.0, 1.0);
uniform vec2 rect_size = vec2(460.0, 230.0);
uniform float radius = 16.0;
uniform float glow = 0.55;
uniform float time = 0.0;
uniform float reveal = 1.0;
float rounded(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 px = UV * rect_size;
	float d = rounded(px - rect_size * 0.5, rect_size * 0.5, radius);
	vec2 uv = center + (UV - 0.5) * span;
	// sharp bilinear: crisp texels, 1-screen-pixel anti-aliased seams
	vec2 scale = rect_size / (span * tex_size);
	vec2 texel = uv * tex_size;
	vec2 rr = max(vec2(0.0), 0.5 - 0.5 / scale);
	vec2 cd = fract(texel) - 0.5;
	vec2 f = (cd - clamp(cd, -rr, rr)) * scale + 0.5;
	vec2 suv = (floor(texel) + f) / tex_size;
	vec3 c = textureLod(map_tex, suv, 0.0).rgb;
	// soft painterly bloom from the mip chain
	vec3 g = textureLod(map_tex, uv, 2.5).rgb * 0.6 + textureLod(map_tex, uv, 4.0).rgb * 0.4;
	c += g * g * glow * 1.6;
	c = pow(c, vec3(0.94)) * 1.05;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	c = mix(vec3(0.012, 0.014, 0.022), c, inside);
	vec2 v = UV - 0.5;
	c *= 1.0 - dot(v, v) * 0.85;
	c += (hash(px + time) - 0.5) * 0.012;
	// reveal (title/loading): painted in by a soft noisy wipe
	float n = hash(floor(uv * tex_size));
	float rv = smoothstep(reveal * 1.25 - 0.2, reveal * 1.25, uv.x * 0.8 + n * 0.2);
	c *= 1.0 - rv;
	float edge = smoothstep(0.0, -1.5, d);
	float rim = smoothstep(-6.0, 0.0, d) * edge;
	c = mix(c, vec3(1.0, 0.85, 0.55), rim * 0.3);
	COLOR = vec4(c, edge * 0.97);
}
"""

const DOOR_IDS := [23, 24, 25, 26, 27, 28, 43]
const ZOOM_MAX := 10.0

var level
var sim
var mode := Mode.OFF
var _img: Image
var _tex: ImageTexture
var _map: TextureRect
var _overlay: Control
var _mat: ShaderMaterial
var _a := 0.0
var _full_a := 0.0
var _t := 0.0
var _player_tile := Vector2.ZERO
var _view := Rect2()
var _base := {}            # tile -> painted color (for restoring doors)
var _bg_under := {}        # tile -> color shown when the door is open
var _doors: Array[Vector2i] = []
var _door_open := {}
var _coins: Array = []     # [Vector2i tile, bool blue]
var _dirty := false
var _center := Vector2(0.5, 0.5)
var _zoom := 1.0
var _drag := false
var zone_name := ""
var _warm := 0

## Draw once (nearly transparent, behind the loading screen) so shaders compile before first real use.
func warmup(frames: int = 3) -> void:
	_warm = frames

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS

## Loads the canonical minimap image (works before the level is parsed: used by the loading reveal too).
static func load_art() -> Image:
	var p := "res://assets/ee_ref/minimap_ee.png"
	var img: Image = null
	if ResourceLoader.exists(p):
		var t: Texture2D = load(p)
		if t:
			img = t.get_image()
	if img == null:
		img = Image.load_from_file(ProjectSettings.globalize_path(p))
	if img:
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	return img

func build(lvl, s) -> void:
	level = lvl
	sim = s
	_img = load_art()
	if _img == null:
		_img = Image.create(lvl.width, lvl.height, false, Image.FORMAT_RGBA8)
	var colors := _load_colors()
	var bg_default := Color(0, 0, 0)
	for y in lvl.height:
		for x in lvl.width:
			var id: int = lvl.get_fg(x, y)
			if id in DOOR_IDS:
				var t := Vector2i(x, y)
				_doors.append(t)
				_base[t] = _img.get_pixel(x, y)
				var b: int = lvl.get_bg(x, y)
				var bc: Color = colors.get(b, bg_default) if b > 0 else bg_default
				_bg_under[t] = bc
			elif id == 100 or id == 101:
				_coins.append([Vector2i(x, y), id == 101])
	_img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(_img)
	_map = TextureRect.new()
	_map.texture = _tex
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MAP_SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("map_tex", _tex)
	_mat.set_shader_parameter("tex_size", Vector2(_img.get_width(), _img.get_height()))
	_map.material = _mat
	add_child(_map)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	refresh_doors()
	modulate.a = 0.0

static func _load_colors() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://assets/ee_ref/minimap_colors.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				if d[k] is String:
					out[int(k)] = Color.html(d[k])
	return out

# ---------------------------------------------------------------- live state
## Doors/gates: painted color when solid, a faint ghost of it over the background when passable.
func refresh_doors() -> void:
	if sim == null or _img == null or not sim.has_method(&"is_tile_solid_now"):
		return
	var changed := false
	for t in _doors:
		var open: bool = not sim.is_tile_solid_now(t.x, t.y)
		if _door_open.get(t, false) == open:
			continue
		_door_open[t] = open
		var c: Color = _base[t]
		if open:
			c = (_bg_under[t] as Color).lerp(c, 0.22)
		_img.set_pixel(t.x, t.y, c)
		changed = true
	if changed:
		_dirty = true

func mark_dirty() -> void:
	refresh_doors()

## Kept for compatibility: coins are overlay glints (EE paints coins transparent), nothing to erase.
func erase_tile(_t: Vector2i) -> void:
	pass

func set_player(player_tile: Vector2, view: Rect2) -> void:
	_player_tile = player_tile
	_view = view

# ---------------------------------------------------------------- modes
func toggle() -> void:
	match mode:
		Mode.OFF:
			set_mode(Mode.CORNER)
		Mode.CORNER:
			set_mode(Mode.FULL)
		Mode.FULL:
			set_mode(Mode.OFF)

func set_shown(v: bool) -> void:
	set_mode(Mode.CORNER if v else Mode.OFF)

func is_shown() -> bool:
	return mode != Mode.OFF

func is_full() -> bool:
	return mode == Mode.FULL

func set_mode(m: Mode) -> void:
	var was_full := mode == Mode.FULL
	mode = m
	if m == Mode.FULL and not was_full:
		_zoom = 1.0
		_center = Vector2(0.5, 0.5)
		refresh_doors()
		full_opened.emit()
	elif was_full and m != Mode.FULL:
		full_closed.emit()

func _full_rect() -> Rect2:
	var avail := size - Vector2(220, 260)
	var w := minf(avail.x, avail.y * 2.0)
	var s := Vector2(w, w * 0.5)
	return Rect2((size - s) * 0.5 + Vector2(0, 20), s)

func _corner_rect() -> Rect2:
	var s := Vector2(460, 230)
	return Rect2(size - s - Vector2(40, 40), s)

func _current_rect() -> Rect2:
	var c := _corner_rect()
	var f := _full_rect()
	return Rect2(c.position.lerp(f.position, _full_a), c.size.lerp(f.size, _full_a))

func _span() -> Vector2:
	var z := lerpf(1.0, _zoom, _full_a)
	return Vector2(1.0, 1.0) / z

func _clamp_center() -> void:
	var sp := Vector2(1.0, 1.0) / _zoom
	_center.x = clampf(_center.x, sp.x * 0.5, 1.0 - sp.x * 0.5)
	_center.y = clampf(_center.y, sp.y * 0.5, 1.0 - sp.y * 0.5)

func _zoom_at(factor: float, screen_pt: Vector2) -> void:
	var r := _full_rect()
	var uv_before := _center + ((screen_pt - r.position) / r.size - Vector2(0.5, 0.5)) / _zoom
	_zoom = clampf(_zoom * factor, 1.0, ZOOM_MAX)
	_center = uv_before - ((screen_pt - r.position) / r.size - Vector2(0.5, 0.5)) / _zoom
	_clamp_center()

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.FULL:
		return
	var handled := true
	if event.is_action_pressed(&"ee_minimap") or event.is_action_pressed(&"ee_pause"):
		set_mode(Mode.OFF)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.18, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.18, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag:
		_center -= (event as InputEventMouseMotion).relative / _full_rect().size / _zoom
		_clamp_center()
	elif event.is_action_pressed(&"ee_zoom_in"):
		_zoom_at(1.3, _full_rect().get_center())
	elif event.is_action_pressed(&"ee_zoom_out"):
		_zoom_at(1.0 / 1.3, _full_rect().get_center())
	elif event.is_action_pressed(&"ee_jump"):
		# recenter on the player
		_center = _player_tile / Vector2(_img.get_width(), _img.get_height())
		_zoom = maxf(_zoom, 3.0)
		_clamp_center()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_t += delta
	_a = lerpf(_a, 0.0 if mode == Mode.OFF else 1.0, 1.0 - exp(-9.0 * delta))
	_full_a = lerpf(_full_a, 1.0 if mode == Mode.FULL else 0.0, 1.0 - exp(-9.0 * delta))
	modulate.a = _a
	visible = _a > 0.01
	if _warm > 0:
		_warm -= 1
		visible = true
		modulate.a = 0.02
	if _map == null or not visible:
		return
	if mode == Mode.FULL:
		var pan := Input.get_vector(&"ee_left", &"ee_right", &"ee_up", &"ee_down")
		if pan != Vector2.ZERO:
			_center += pan * delta * 0.6 / _zoom
			_clamp_center()
	if _dirty:
		_dirty = false
		_img.generate_mipmaps()
		_tex.update(_img)
	var r := _current_rect()
	_map.position = r.position + Vector2(0, (1.0 - _a) * 30.0)
	_map.size = r.size
	var cen := Vector2(0.5, 0.5).lerp(_center, _full_a)
	_mat.set_shader_parameter("center", cen)
	_mat.set_shader_parameter("span", _span())
	_mat.set_shader_parameter("rect_size", r.size)
	_mat.set_shader_parameter("radius", lerpf(16.0, 22.0, _full_a))
	_mat.set_shader_parameter("time", _t)
	queue_redraw()
	_overlay.queue_redraw()

## tile (fractional, y down) -> screen position inside the map rect.
func _tile_to_screen(tile: Vector2) -> Vector2:
	var r := Rect2(_map.position, _map.size)
	var uv := tile / Vector2(_img.get_width(), _img.get_height())
	var cen := Vector2(0.5, 0.5).lerp(_center, _full_a)
	return r.position + ((uv - cen) / _span() + Vector2(0.5, 0.5)) * r.size

func _draw() -> void:
	if _map == null or (_a < 0.01 and _warm <= 0):
		return
	if _full_a > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.01, 0.72 * _full_a))
	var o := _map.position
	var frame := Rect2(o - Vector2(12, 44), _map.size + Vector2(24, 56))
	draw_style_box(UITheme.glass_box(22, 0.62), frame)
	var fs := int(lerpf(17.0, 26.0, _full_a))
	var title := "MAP OF THE ODYSSEY" if _full_a > 0.5 else "EX CREW ODYSSEY"
	draw_string(UITheme.title(4, 700), o + Vector2(4, -14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.GOLD, 0.9))
	var right := zone_name if _full_a > 0.5 else "M  expand"
	draw_string(UITheme.hud_medium(2), o + Vector2(0, -14), right, HORIZONTAL_ALIGNMENT_RIGHT, _map.size.x - 4, fs - 1, UITheme.INK_DIM)
	if _full_a > 0.5:
		var hint := "WHEEL  zoom      DRAG / ARROWS  pan      SPACE  find me      M / ESC  close"
		draw_string(UITheme.hud_medium(3), Vector2(0, o.y + _map.size.y + 44), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, Color(1, 1, 1, 0.5 * _full_a))

func _draw_overlay() -> void:
	if _map == null or _a < 0.01:
		return
	var r := Rect2(_map.position, _map.size)
	var px_per_tile := r.size.x / (float(_img.get_width()) * _span().x)
	# coin glints (uncollected only)
	for c in _coins:
		var t: Vector2i = c[0]
		if sim and sim.has_method(&"is_coin_collected") and sim.is_coin_collected(t.x, t.y):
			continue
		var p := _tile_to_screen(Vector2(t) + Vector2(0.5, 0.5))
		if not r.grow(-2).has_point(p):
			continue
		var col: Color = UITheme.BLUE_COIN if c[1] else UITheme.GOLD
		var tw := 0.6 + 0.4 * sin(_t * 4.0 + t.x * 1.7 + t.y)
		var s := maxf(1.6, px_per_tile * 0.45) * tw
		_overlay.draw_circle(p, s * 2.6, Color(col, 0.12))
		_overlay.draw_line(p - Vector2(s * 1.8, 0), p + Vector2(s * 1.8, 0), Color(col, 0.7), 1.0, true)
		_overlay.draw_line(p - Vector2(0, s * 1.8), p + Vector2(0, s * 1.8), Color(col, 0.7), 1.0, true)
		_overlay.draw_circle(p, s * 0.6, col.lerp(Color.WHITE, 0.5))
	# current camera view
	var a := _tile_to_screen(_view.position)
	var b := _tile_to_screen(_view.end)
	var vr := Rect2(a, b - a).intersection(r)
	if vr.size.x > 0:
		_overlay.draw_rect(vr, Color(1, 1, 1, 0.06))
		_overlay.draw_rect(vr, Color(1, 1, 1, 0.4), false, 1.0)
	# player
	var p := _tile_to_screen(_player_tile)
	if r.has_point(p):
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		var k := lerpf(1.0, 1.5, _full_a)
		_overlay.draw_circle(p, (10.0 + pulse * 7.0) * k, Color(1, 0.9, 0.5, 0.16 * (1.0 - pulse * 0.5)))
		_overlay.draw_circle(p, 5.5 * k, Color(0.05, 0.05, 0.08, 0.9))
		_overlay.draw_circle(p, 3.8 * k, Color(1.0, 0.93, 0.62))
