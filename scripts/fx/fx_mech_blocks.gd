class_name FxMechBlocks
extends Node3D
## Visuals for the newer EE mechanics (Forgotten Veil and any later level): purple switches 113 (rune
## lever medallions that visibly toggle), speed boosts 114-117 (double chevrons + rushing speed lines),
## piano 77 (carved chime tablets that light up and ripple a note), invisible gravity 411-414 (only a very
## faint shimmer, EE hides them). Built only for ids present in the level, so Odyssey gets nothing here.

const GLYPH_SHADER := preload("res://shaders/fx/grav_glyph.gdshader")
const GLOW_SHADER := preload("res://shaders/fx/glow_sprite.gdshader")
const SWITCH_SHADER := preload("res://shaders/fx/rune_switch.gdshader")
const CHIME_SHADER := preload("res://shaders/fx/chime_stone.gdshader")
const RIPPLE_SHADER := preload("res://shaders/fx/ripple.gdshader")
const SHIMMER_SHADER := preload("res://shaders/fx/shimmer.gdshader")
const FLOW_SHADER := preload("res://shaders/fx/boost_flow.gdshader")

const SWITCH_ID := 113
const PIANO_ID := 77
## Speed boost id -> flow angle (world, y up).
const BOOSTS := {114: PI, 115: 0.0, 116: PI * 0.5, 117: -PI * 0.5}
## Invisible gravity id -> [angle, dot]
const INVISIBLE := {411: [PI, 0.0], 412: [PI * 0.5, 0.0], 413: [0.0, 0.0], 414: [0.0, 1.0]}
const SWITCH_COLOR := Color(0.78, 0.32, 1.0)
const BOOST_COLOR := Color(0.35, 0.95, 1.0)
const MAX_RIPPLES := 12

var lvl: EELevel
var sim
var bursts: FxBursts

var _switches: Array = []     # {tile, sid, mat, halo, light, on, flash}
var _boost_tiles := {}        # Vector2i -> angle
var _boost_mats: Array[ShaderMaterial] = []
var _flow_mats: Array[ShaderMaterial] = []
var _surge := 0.0
var _last_boost_tile := Vector2i(-1, -1)
var _last_boost_ms := 0
var _chime_mm: MultiMesh
var _chime_mat: ShaderMaterial
var _chime_index := {}        # Vector2i -> instance
var _chime_custom: Array[Color] = []
var _chime_flare := PackedFloat32Array()
var _ripple_mm: MultiMesh
var _ripples: Array = []      # {pos, age, speed, size, col, n}
var _shimmer_mat: ShaderMaterial
var _hc_mats: Array[ShaderMaterial] = []
var _last_note_flash := 0

func build(level: EELevel, s) -> void:
	lvl = level
	sim = s
	_build_switches()
	_build_boosts()
	_build_piano()
	_build_invisible()
	_build_ripples()

func _number(t: Vector2i) -> int:
	if sim != null and sim.has_method("get_tile_number"):
		return sim.get_tile_number(t.x, t.y)
	return int(lvl.get_extra(t.x, t.y).get("rotation", 0))

# ------------------------------------------------------------------------------------------ switches

func _build_switches() -> void:
	for t in lvl.find_all(SWITCH_ID):
		var root := Node3D.new()
		root.name = "Switch_%d_%d" % [t.x, t.y]
		root.position = EECoords.tile_center(t.x, t.y, -0.3)
		add_child(root)
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.84, 0.84)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = SWITCH_SHADER
		m.set_shader_parameter("on_color", SWITCH_COLOR)
		m.set_shader_parameter("phase", FxInteractiveBlocks._tile_hash(t).x * TAU)
		mi.material_override = m
		root.add_child(mi)
		var halo := MeshInstance3D.new()
		var hq := QuadMesh.new()
		hq.size = Vector2(2.2, 2.2)
		halo.mesh = hq
		var hm := ShaderMaterial.new()
		hm.shader = GLOW_SHADER
		hm.set_shader_parameter("color", SWITCH_COLOR)
		hm.set_shader_parameter("intensity", 0.0)
		halo.material_override = hm
		halo.position = Vector3(0, 0, -0.1)
		root.add_child(halo)
		var l := OmniLight3D.new()
		l.light_color = SWITCH_COLOR
		l.light_energy = 0.0
		l.omni_range = 3.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 36.0
		l.distance_fade_length = 8.0
		l.position = Vector3(0, 0, 0.6)
		l.visible = false
		root.add_child(l)
		_hc_mats.append(m)
		var on := _switch_state(_number(t))
		_switches.append({"tile": t, "sid": _number(t), "mat": m, "halo": hm, "light": l,
			"on": 1.0 if on else 0.0, "flash": 0.0})

func _switch_state(sid: int) -> bool:
	return sim != null and sim.has_method("is_switch_on") and sim.is_switch_on(sid)

## sim_event &"switch" {kind, id, on}: every medallion with that id flashes and plays a pulse ring.
func on_switch(data: Dictionary) -> void:
	if StringName(data.get("kind", &"purple")) != &"purple":
		return
	var sid := int(data.get("id", -1))
	for sw in _switches:
		if sw.sid == sid or sid == 1000:
			sw.flash = 1.0
			var p := EECoords.tile_center(sw.tile.x, sw.tile.y, -0.2)
			spawn_ripple(p, SWITCH_COLOR, 3.2, 1.3, 3)
			if bursts:
				bursts.play(&"key", p, Vector3.UP, SWITCH_COLOR, 0.5)
				bursts.flash(p, SWITCH_COLOR, 2.5, 0.45, 5.0)

# ------------------------------------------------------------------------------------------ speed boosts

func _build_boosts() -> void:
	for id in BOOSTS:
		var tiles := lvl.find_all(id)
		if tiles.is_empty():
			continue
		var ang: float = BOOSTS[id]
		for t in tiles:
			_boost_tiles[t] = ang
		var mesh := FxMeshes.chevron_glyph().duplicate() as Mesh
		var gm := ShaderMaterial.new()
		gm.shader = GLYPH_SHADER
		gm.set_shader_parameter("color", BOOST_COLOR)
		gm.set_shader_parameter("intensity", 1.6)
		var om := ShaderMaterial.new()
		om.shader = GLYPH_SHADER
		om.set_shader_parameter("outline", 1.0)
		mesh.surface_set_material(0, gm)
		mesh.surface_set_material(1, om)
		_boost_mats.append(gm)
		_boost_mats.append(om)
		_hc_mats.append(gm)
		_hc_mats.append(om)
		# a double chevron per tile ">>"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = tiles.size() * 2
		var d := Vector3(cos(ang), sin(ang), 0.0)
		for i in tiles.size():
			var t := tiles[i]
			for k in 2:
				var b := Basis(Vector3(0, 0, 1), ang).scaled(Vector3.ONE * 0.95)
				var o := EECoords.tile_center(t.x, t.y, 0.1) + d * (k - 0.5) * 0.3
				mm.set_instance_transform(i * 2 + k, Transform3D(b, o))
				mm.set_instance_custom_data(i * 2 + k, Color(FxInteractiveBlocks._tile_hash(t).x, ang, 0.0, 0.0))
		var gi := MultiMeshInstance3D.new()
		gi.name = "Boost_%d" % id
		gi.multimesh = mm
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gi)
		_build_flow_strips(tiles, ang)

## One speed-line strip per straight run of boost tiles, behind the chevrons.
func _build_flow_strips(tiles: Array[Vector2i], ang: float) -> void:
	var horiz := absf(cos(ang)) > 0.5
	var set_ := {}
	for t in tiles:
		set_[t] = true
	var step := Vector2i(1, 0) if horiz else Vector2i(0, 1)
	for t in tiles:
		if set_.has(t - step):
			continue
		var n := 1
		while set_.has(t + step * n):
			n += 1
		var mi := MeshInstance3D.new()
		mi.name = "BoostFlow"
		var q := QuadMesh.new()
		q.size = Vector2(n + 0.6, 0.9)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = FLOW_SHADER
		m.set_shader_parameter("color", BOOST_COLOR)
		m.set_shader_parameter("length_tiles", n + 0.6)
		mi.material_override = m
		var c := (EECoords.tile_center(t.x, t.y, -0.4) + EECoords.tile_center(t.x + step.x * (n - 1), t.y + step.y * (n - 1), -0.4)) * 0.5
		mi.position = c
		mi.rotation.z = ang   # quad +x (UV.x) points along the flow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_flow_mats.append(m)
		_hc_mats.append(m)

# ------------------------------------------------------------------------------------------ piano

func _build_piano() -> void:
	var tiles := lvl.find_all(PIANO_ID)
	if tiles.is_empty():
		return
	var q := QuadMesh.new()
	q.size = Vector2(0.56, 0.72)
	_chime_mat = ShaderMaterial.new()
	_chime_mat.shader = CHIME_SHADER
	q.material = _chime_mat
	_hc_mats.append(_chime_mat)
	_chime_mm = MultiMesh.new()
	_chime_mm.transform_format = MultiMesh.TRANSFORM_3D
	_chime_mm.use_custom_data = true
	_chime_mm.mesh = q
	_chime_mm.instance_count = tiles.size()
	_chime_flare.resize(tiles.size())
	for i in tiles.size():
		var t := tiles[i]
		_chime_index[t] = i
		var h := FxInteractiveBlocks._tile_hash(t)
		var tilt := (h.y - 0.5) * 0.16
		_chime_mm.set_instance_transform(i, Transform3D(Basis(Vector3(0, 0, 1), tilt), EECoords.tile_center(t.x, t.y, -0.25)))
		var c := Color(h.x, _note_hue(_number(t)), 0.0, 0.0)
		_chime_custom.append(c)
		_chime_mm.set_instance_custom_data(i, c)
	var mi := MultiMeshInstance3D.new()
	mi.name = "PianoChimes"
	mi.multimesh = _chime_mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

static func _note_hue(note: int) -> float:
	return fposmod(float(note) * 0.083 + 0.55, 1.0)

## sim_event &"piano" {tile, note}: the tablet lights in its note colour and a ripple rings out.
func on_piano(data: Dictionary) -> void:
	var t = data.get("tile")
	if not (t is Vector2i):
		return
	var hue := _note_hue(int(data.get("note", _number(t))))
	var col := Color.from_hsv(hue, 0.65, 1.0)
	if _chime_index.has(t):
		_chime_flare[_chime_index[t]] = 1.0
	var p := EECoords.tile_center(t.x, t.y, -0.15)
	spawn_ripple(p, col, 2.6, 0.9, 2)
	var now := Time.get_ticks_msec()
	if bursts and now - _last_note_flash > 120:
		_last_note_flash = now
		bursts.flash(p, col, 1.6, 0.35, 4.0)

# ------------------------------------------------------------------------------------------ invisible gravity

func _build_invisible() -> void:
	var tiles: Array[Vector2i] = []
	var custom: Array[Color] = []
	for id in INVISIBLE:
		for t in lvl.find_all(id):
			tiles.append(t)
			var spec: Array = INVISIBLE[id]
			custom.append(Color(FxInteractiveBlocks._tile_hash(t).x, spec[0], spec[1], 0))
	if tiles.is_empty():
		return
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_shimmer_mat = ShaderMaterial.new()
	_shimmer_mat.shader = SHIMMER_SHADER
	q.material = _shimmer_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = tiles.size()
	for i in tiles.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, EECoords.tile_center(tiles[i].x, tiles[i].y, -0.2)))
		mm.set_instance_custom_data(i, custom[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "InvisibleGravity"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ------------------------------------------------------------------------------------------ ripples

func _build_ripples() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := ShaderMaterial.new()
	m.shader = RIPPLE_SHADER
	q.material = m
	_ripple_mm = MultiMesh.new()
	_ripple_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ripple_mm.use_custom_data = true
	_ripple_mm.use_colors = true
	_ripple_mm.mesh = q
	_ripple_mm.instance_count = MAX_RIPPLES
	_ripple_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Ripples"
	mi.multimesh = _ripple_mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)

## An expanding ring (size = final diameter in tiles, life in seconds, n = 1..3 concentric rings).
func spawn_ripple(pos: Vector3, col: Color, size: float, life: float, n := 1) -> void:
	if _ripples.size() >= MAX_RIPPLES:
		_ripples.pop_front()
	_ripples.append({"pos": pos, "age": 0.0, "life": life, "size": size, "col": col, "n": n})

# ------------------------------------------------------------------------------------------ runtime

func set_ball_pos(p: Vector3) -> void:
	for m in _boost_mats:
		m.set_shader_parameter("ball_pos", p)
	if _chime_mat:
		_chime_mat.set_shader_parameter("ball_pos", p)
	if _shimmer_mat:
		_shimmer_mat.set_shader_parameter("ball_pos", p)
	if _boost_tiles.is_empty():
		return
	var t := EECoords.world_to_tile(p)
	if _boost_tiles.has(t) and t != _last_boost_tile:
		var now := Time.get_ticks_msec()
		if now - _last_boost_ms > 250:
			_last_boost_ms = now
			_surge = 1.0
			var ang: float = _boost_tiles[t]
			var d := Vector3(cos(ang), sin(ang), 0.0)
			if bursts:
				bursts.play(&"sparks", p, -d, BOOST_COLOR, 0.6)
			spawn_ripple(p, BOOST_COLOR, 2.0, 0.45, 1)
	_last_boost_tile = t

func set_glyph_boost(k: float) -> void:
	for m in _hc_mats:
		m.set_shader_parameter("hc", k)

func _process(delta: float) -> void:
	for sw in _switches:
		var on := 1.0 if _switch_state(sw.sid) else 0.0
		sw.on = move_toward(sw.on, on, delta / 0.3)
		sw.flash = maxf(sw.flash - delta * 2.5, 0.0)
		var m: ShaderMaterial = sw.mat
		m.set_shader_parameter("on_amount", smoothstep(0.0, 1.0, sw.on))
		m.set_shader_parameter("flash", sw.flash)
		sw.halo.set_shader_parameter("intensity", 0.55 * sw.on + sw.flash * 0.6)
		var l: OmniLight3D = sw.light
		l.light_energy = 1.1 * sw.on + sw.flash * 1.5
		l.visible = l.light_energy > 0.01
	_surge = maxf(_surge - delta * 2.5, 0.0)
	for m in _flow_mats:
		m.set_shader_parameter("surge", _surge)
	if _chime_mm:
		for i in _chime_flare.size():
			if _chime_flare[i] > 0.0:
				_chime_flare[i] = maxf(_chime_flare[i] - delta * 1.4, 0.0)
				var c := _chime_custom[i]
				c.b = _chime_flare[i]
				_chime_mm.set_instance_custom_data(i, c)
	if _ripple_mm:
		var n := 0
		for i in range(_ripples.size() - 1, -1, -1):
			var r: Dictionary = _ripples[i]
			r.age += delta / r.life
			if r.age >= 1.0:
				_ripples.remove_at(i)
		for r in _ripples:
			_ripple_mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r.size), r.pos))
			_ripple_mm.set_instance_custom_data(n, Color(r.age, r.n, 0, 0))
			_ripple_mm.set_instance_color(n, r.col)
			n += 1
		_ripple_mm.visible_instance_count = n
