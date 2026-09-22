class_name FxInteractiveBlocks
extends Node3D
## Visuals for every interactive block id owned by actors: gravity field (1-4), crowns (5), keys (6-8),
## doors/gates/coin doors (23-26, 28, 43), coins (100/101), trophy (121), portals (242/381), spawn (255).
## Big same-id populations are merged: one field quad for arrows, MultiMesh for keys/crowns/portals,
## one merged slab mesh per door kind.

const FIELD_SHADER := preload("res://shaders/fx/gravity_field.gdshader")
const GEM_SHADER := preload("res://shaders/fx/key_gem.gdshader")
const GLYPH_SHADER := preload("res://shaders/fx/grav_glyph.gdshader")
const GLOW_SHADER := preload("res://shaders/fx/glow_sprite.gdshader")
const BARRIER_SHADER := preload("res://shaders/fx/barrier.gdshader")
const PORTAL_SHADER := preload("res://shaders/fx/portal.gdshader")
const COIN_SHADER := preload("res://shaders/fx/coin.gdshader")
const BEACON_SHADER := preload("res://shaders/fx/beacon.gdshader")

const Z_FIELD := -0.56
const Z_KEYS := -0.3
const Z_PORTAL := -0.46

const KEY_COLORS := {
	&"red": Color("#ff3b3b"),
	&"green": Color("#3bff5a"),
	&"blue": Color("#3b7bff"),
}
const KEY_IDS := {6: &"red", 7: &"green", 8: &"blue"}
## Exact EE minimap colours (assets/ee_ref/minimap_colors.json): these tiles ARE the painting's dither.
const ART_COLORS := {5: Color("#43391f"), 6: Color("#2c1a1a"), 7: Color("#1a2c1a"), 8: Color("#1a1a2c")}
const CROWN_GLOW := Color(1.0, 0.72, 0.25)
## Barrier kinds: id -> [style, color, trigger]. Key doors/gates (23-28) belong to WorldView (they are art).
const BARRIERS := {
	43: [2, Color(1.0, 0.7, 0.2), &"coin"],
}

var lvl: EELevel
var sim
var bursts: FxBursts

var _art_mats := {}       # id -> ShaderMaterial (art pebbles: keys + crowns)
var _flares := {}         # id -> Array of Vector4(x, y, age, strength) (ring buffer of 4)
var _key_active := {}     # color -> float (smoothed)
var _ball_pos := Vector3(-1000, 0, 0)
var _field_mat: ShaderMaterial
var _halo_mats := {}
var _hc_mats: Array[ShaderMaterial] = []
var _hc := false
var _glyph_mats: Array[ShaderMaterial] = []
var _barriers: Array = [] # [{mat, reps: Array[Vector2i], open: float, target: float, id}]
var _coins: Array = []    # [{node, tile, collected, t}]
var _portal_tiles := {}   # Vector2i -> true
var _portal_mat: ShaderMaterial
var _coin_fly: Array = [] # flying collected coins

func build(level: EELevel, s) -> void:
	lvl = level
	sim = s
	_build_field()
	_build_keys()
	_build_barriers()
	_build_coins()
	_build_portals()
	_build_spawn()
	_build_trophy()

# ============================================================================ gravity field

func _build_field() -> void:
	var img := Image.create(lvl.width, lvl.height, false, Image.FORMAT_RGBA8)
	var any := false
	for y in lvl.height:
		for x in lvl.width:
			var id := lvl.fg[y * lvl.width + x]
			if id >= 1 and id <= 4:
				var c := Color(0, 0, 0, 0)
				c[id - 1] = 1.0
				img.set_pixel(x, y, c)
				any = true
	if not any:
		return
	var tex := ImageTexture.create_from_image(img)
	var mi := MeshInstance3D.new()
	mi.name = "GravityField"
	var q := QuadMesh.new()
	q.size = Vector2(lvl.width, lvl.height)
	mi.mesh = q
	mi.position = Vector3(lvl.width * 0.5, -lvl.height * 0.5, Z_FIELD)
	var m := ShaderMaterial.new()
	m.shader = FIELD_SHADER
	m.set_shader_parameter("field_lin", tex)
	m.set_shader_parameter("field_near", tex)
	m.set_shader_parameter("level_size", Vector2(lvl.width, lvl.height))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_field_mat = m
	_build_glyphs()

## Crisp per-tile glyphs: chevrons for arrows 1/2/3 (pointing in the gravity direction), orbs for dots 4.
func _build_glyphs() -> void:
	var angles := {1: PI, 2: PI * 0.5, 3: 0.0}
	for id in [1, 2, 3, 4]:
		var tiles := lvl.find_all(id)
		if tiles.is_empty():
			continue
		var dot: bool = id == 4
		var mesh := (FxMeshes.dot_glyph() if dot else FxMeshes.chevron_glyph()).duplicate() as Mesh
		var gm := ShaderMaterial.new()
		gm.shader = GLYPH_SHADER
		if dot:
			gm.set_shader_parameter("color", Color(1.0, 0.88, 0.6))
			gm.set_shader_parameter("intensity", 0.6)
		var om := ShaderMaterial.new()
		om.shader = preload("res://shaders/fx/glyph_halo.gdshader") if dot else GLYPH_SHADER
		if not dot:
			om.set_shader_parameter("outline", 1.0)
		mesh.surface_set_material(0, gm)
		mesh.surface_set_material(1, om)
		_hc_mats.append(gm)
		_hc_mats.append(om)
		_glyph_mats.append(gm)
		if not dot:
			_glyph_mats.append(om)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = tiles.size()
		var ang: float = 0.0 if dot else angles[id]
		for i in tiles.size():
			var t := tiles[i]
			var b := Basis(Vector3(0, 0, 1), ang).scaled(Vector3.ONE * (1.0 if dot else 1.15))
			mm.set_instance_transform(i, Transform3D(b, EECoords.tile_center(t.x, t.y, 0.12)))
			mm.set_instance_custom_data(i, Color(_tile_hash(t).x, ang, 1.0 if dot else 0.0, 0))
		var gi := MultiMeshInstance3D.new()
		gi.name = "Glyphs_%d" % id
		gi.multimesh = mm
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gi)

# ============================================================================ keys

func _build_keys() -> void:
	for id in [6, 7, 8, 5]:
		var tiles := lvl.find_all(id)
		if tiles.is_empty():
			continue
		var crown: bool = id == 5
		var col: Color = CROWN_GLOW if crown else KEY_COLORS[KEY_IDS[id]]
		var m := ShaderMaterial.new()
		m.shader = GEM_SHADER
		m.set_shader_parameter("gem_color", col)
		m.set_shader_parameter("glow", 0.9 if crown else 1.15)
		m.set_shader_parameter("twinkle", 1.0 if crown else 0.0)
		var gem := FxMeshes.gem().duplicate() as Mesh
		gem.surface_set_material(0, m)
		var mi := _multimesh(gem, tiles, Vector3(0, 0, 0.1), 0.26 if crown else 0.4, true, [], 0.0)
		mi.name = "KeyGems_%d" % id
		# small soft halo (additive) so dense fields glitter
		var gm := ShaderMaterial.new()
		gm.shader = GLOW_SHADER
		gm.set_shader_parameter("color", col)
		gm.set_shader_parameter("intensity", 0.12 if crown else 0.22)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9, 0.9)
		quad.material = gm
		_multimesh(quad, tiles, Vector3(0, 0, -0.05), 1.0, false).name = "KeyHalo_%d" % id
		_art_mats[id] = m
		_flares[id] = []
		_halo_mats[id] = gm
		_hc_mats.append(m)
	for c in KEY_COLORS:
		_key_active[c] = 0.0

## Flare the art pebbles of `id` around a tile (key/crown touched).
func flare(id: int, tile: Vector2i, strength := 1.0) -> void:
	if not _flares.has(id):
		return
	var arr: Array = _flares[id]
	var c := EECoords.tile_center(tile.x, tile.y)
	arr.push_front(Vector4(c.x, c.y, 0.0, strength))
	if arr.size() > 4:
		arr.pop_back()

func set_ball_pos(p: Vector3) -> void:
	_ball_pos = p
	if _field_mat:
		_field_mat.set_shader_parameter("ball_pos", p)
	for m in _glyph_mats:
		m.set_shader_parameter("ball_pos", p)

func _multimesh(mesh: Mesh, tiles: Array[Vector2i], offset: Vector3, scale: float, tilt: bool, custom_y := [], jitter := 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = tiles.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + tiles.size()
	for i in tiles.size():
		var t := tiles[i]
		# per-tile deterministic jitter (identical across multimeshes sharing tiles, e.g. crystal + halo)
		var h := _tile_hash(t)
		var b := Basis.IDENTITY.scaled(Vector3.ONE * scale * (1.0 + (h.x * 2.0 - 1.0) * jitter))
		var jp := Vector3(h.y * 2.0 - 1.0, h.z * 2.0 - 1.0, 0) * jitter * 0.6
		if tilt:
			b = Basis(Vector3(0, 0, 1), rng.randf_range(-0.25, 0.25)) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.2, 0.2)) * b
		mm.set_instance_transform(i, Transform3D(b, EECoords.tile_center(t.x, t.y) + offset + jp))
		var cy: float = custom_y[i] if i < custom_y.size() else 0.0
		mm.set_instance_custom_data(i, Color(rng.randf(), cy, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

static func _tile_hash(t: Vector2i) -> Vector3:
	var n := (t.x * 73856093) ^ (t.y * 19349663)
	var a := float((n * 1103515245 + 12345) & 0xFFFF) / 65535.0
	var b := float(((n >> 7) * 22695477 + 1) & 0xFFFF) / 65535.0
	var c := float(((n >> 13) * 134775813 + 7) & 0xFFFF) / 65535.0
	return Vector3(a, b, c)

# ============================================================================ doors / gates / coin doors

func _build_barriers() -> void:
	for id in BARRIERS:
		var tiles := lvl.find_all(id)
		if tiles.is_empty():
			continue
		var spec: Array = BARRIERS[id]
		var style: int = spec[0]
		var front: float = [0.5, 0.42, -0.12][style]
		var back := -0.85
		var mask := {}
		for t in tiles:
			mask[t] = true
		var mesh := _slab_mesh(tiles, mask, front, back)
		var m := ShaderMaterial.new()
		m.shader = BARRIER_SHADER
		m.set_shader_parameter("sdf", _sdf_texture(tiles, mask))
		m.set_shader_parameter("level_size", Vector2(lvl.width, lvl.height))
		m.set_shader_parameter("color", spec[1])
		m.set_shader_parameter("style", style)
		m.set_shader_parameter("front_z", front)
		var mi := MeshInstance3D.new()
		mi.name = "Barrier_%d" % id
		mi.mesh = mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Representative tiles: coin doors can have different coin counts (stored in extra.rotation).
		var reps: Array[Vector2i] = []
		var seen := {}
		for t in tiles:
			var num := int(lvl.get_extra(t.x, t.y).get("rotation", 0))
			if not seen.has(num):
				seen[num] = true
				reps.append(t)
		var solid0 := _query_solid(reps[0], style)
		var o := 0.0 if solid0 else 1.0
		m.set_shader_parameter("openness", o)
		var mats: Array[ShaderMaterial] = [m]
		if style == 2:
			mats.append(_build_coin_bars(tiles, mask))
		for mm in mats:
			mm.set_shader_parameter("openness", o)
		_barriers.append({"id": id, "mats": mats, "reps": reps, "open": o, "target": o, "style": style,
			"center": _centroid(tiles), "color": spec[1], "flash": 0.0})

## Three round gold bars per coin-door tile + a rail capping each column's top and bottom.
func _build_coin_bars(tiles: Array[Vector2i], mask: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/coin_bars.gdshader")
	var bar := CylinderMesh.new()
	bar.top_radius = 0.065
	bar.bottom_radius = 0.065
	bar.height = 1.0
	bar.radial_segments = 16
	bar.rings = 1
	bar.material = m
	var xf: Array[Transform3D] = []
	for t in tiles:
		for k in 3:
			xf.append(Transform3D(Basis.IDENTITY, Vector3(t.x + (k + 0.5) / 3.0, -t.y - 0.5, 0.05)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bar
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "CoinGateBars"
	mi.multimesh = mm
	add_child(mi)
	# rails (static frame) where the region ends vertically
	var rail := BoxMesh.new()
	rail.size = Vector3(1.0, 0.12, 0.26)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.95, 0.68, 0.25)
	rm.metallic = 1.0
	rm.roughness = 0.25
	rm.emission_enabled = true
	rm.emission = Color(0.6, 0.35, 0.05)
	rm.emission_energy_multiplier = 0.3
	rail.material = rm
	var rx: Array[Transform3D] = []
	for t in tiles:
		if not mask.has(t + Vector2i(0, -1)):
			rx.append(Transform3D(Basis.IDENTITY, Vector3(t.x + 0.5, -t.y - 0.06, 0.05)))
		if not mask.has(t + Vector2i(0, 1)):
			rx.append(Transform3D(Basis.IDENTITY, Vector3(t.x + 0.5, -t.y - 0.94, 0.05)))
	if not rx.is_empty():
		var rmm := MultiMesh.new()
		rmm.transform_format = MultiMesh.TRANSFORM_3D
		rmm.mesh = rail
		rmm.instance_count = rx.size()
		for i in rx.size():
			rmm.set_instance_transform(i, rx[i])
		var rmi := MultiMeshInstance3D.new()
		rmi.name = "CoinGateRails"
		rmi.multimesh = rmm
		add_child(rmi)
	return m

func _query_solid(t: Vector2i, style: int) -> bool:
	if sim != null and sim.has_method("is_tile_solid_now"):
		return sim.is_tile_solid_now(t.x, t.y)
	return style != 1   # without a sim: doors closed, gates open

func _centroid(tiles: Array[Vector2i]) -> Vector3:
	var c := Vector2.ZERO
	for t in tiles:
		c += Vector2(t)
	c /= tiles.size()
	return EECoords.tile_center(int(c.x), int(c.y))

## One merged slab: a front quad per tile, plus side walls only on region boundaries.
func _slab_mesh(tiles: Array[Vector2i], mask: Dictionary, zf: float, zb: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tiles:
		var x0 := float(t.x)
		var x1 := x0 + 1.0
		var y1 := -float(t.y)
		var y0 := y1 - 1.0
		st.set_normal(Vector3(0, 0, 1))
		_q(st, Vector3(x0, y0, zf), Vector3(x0, y1, zf), Vector3(x1, y1, zf), Vector3(x1, y0, zf))
		if not mask.has(t + Vector2i(-1, 0)):
			st.set_normal(Vector3(-1, 0, 0))
			_q(st, Vector3(x0, y0, zb), Vector3(x0, y1, zb), Vector3(x0, y1, zf), Vector3(x0, y0, zf))
		if not mask.has(t + Vector2i(1, 0)):
			st.set_normal(Vector3(1, 0, 0))
			_q(st, Vector3(x1, y0, zf), Vector3(x1, y1, zf), Vector3(x1, y1, zb), Vector3(x1, y0, zb))
		if not mask.has(t + Vector2i(0, -1)):  # tile above (EE y-1) = world +y side
			st.set_normal(Vector3(0, 1, 0))
			_q(st, Vector3(x0, y1, zf), Vector3(x0, y1, zb), Vector3(x1, y1, zb), Vector3(x1, y1, zf))
		if not mask.has(t + Vector2i(0, 1)):
			st.set_normal(Vector3(0, -1, 0))
			_q(st, Vector3(x0, y0, zb), Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, y0, zb))
	return st.commit()

## Quad a,b,c,d given clockwise as seen from the outside (Godot's front-face winding).
func _q(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

## Signed distance (tiles) from each texel center to the region boundary; +inside, -outside.
func _sdf_texture(tiles: Array[Vector2i], mask: Dictionary) -> ImageTexture:
	var img := Image.create(lvl.width, lvl.height, false, Image.FORMAT_RF)
	img.fill(Color(-1.5, 0, 0))
	var R := 4
	var todo := {}
	for t in tiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				todo[t + Vector2i(dx, dy)] = true
	for p: Vector2i in todo:
		if p.x < 0 or p.y < 0 or p.x >= lvl.width or p.y >= lvl.height:
			continue
		var inside := mask.has(p)
		var best := float(R) + 0.5
		for dy in range(-R, R + 1):
			for dx in range(-R, R + 1):
				var q := p + Vector2i(dx, dy)
				if mask.has(q) != inside:
					# distance from p's center to the nearest point of tile q (box distance)
					var ex := maxf(absf(dx) - 0.5, 0.0)
					var ey := maxf(absf(dy) - 0.5, 0.0)
					best = minf(best, sqrt(ex * ex + ey * ey))
		# p's center to boundary: inside tiles adjacent to outside get 0.5 (edge half a tile away)
		var d := best if inside else -best
		img.set_pixel(p.x, p.y, Color(d, 0, 0))
	return ImageTexture.create_from_image(img)

# ============================================================================ coins

func _build_coins() -> void:
	for id in [100, 101]:
		for t in lvl.find_all(id):
			var root := Node3D.new()
			root.name = "Coin_%d_%d" % [t.x, t.y]
			root.position = EECoords.tile_center(t.x, t.y, -0.1)
			add_child(root)
			var mi := MeshInstance3D.new()
			mi.mesh = FxMeshes.coin()
			var m := ShaderMaterial.new()
			m.shader = COIN_SHADER
			if id == 101:
				m.set_shader_parameter("metal_color", Color(0.5, 0.75, 1.0))
				m.set_shader_parameter("glow_color", Color(0.2, 0.5, 1.0))
			mi.material_override = m
			mi.scale = Vector3.ONE * 0.62
			root.add_child(mi)
			var halo := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1.6, 1.6)
			halo.mesh = q
			var gm := ShaderMaterial.new()
			gm.shader = GLOW_SHADER
			gm.set_shader_parameter("color", Color(1.0, 0.65, 0.15) if id == 100 else Color(0.25, 0.5, 1.0))
			gm.set_shader_parameter("intensity", 0.45)
			halo.material_override = gm
			halo.position = Vector3(0, 0, -0.25)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(halo)
			var sp := _coin_sparkles(id == 101)
			root.add_child(sp)
			_coins.append({"root": root, "mesh": mi, "tile": t, "id": id, "collected": false, "ph": randf() * TAU})

func _coin_sparkles(blue: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 1.2
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.38
	pm.gravity = Vector3(0, 0.25, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.1
	var c := Curve.new()
	c.add_point(Vector2(0, 0)); c.add_point(Vector2(0.5, 1)); c.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.color = Color(0.6, 0.8, 1.0) if blue else Color(1.0, 0.9, 0.6)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/particle.gdshader")
	m.set_shader_parameter("intensity", 5.0)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func collect_coin_at(tile: Vector2i) -> void:
	for c in _coins:
		if c.tile == tile and not c.collected:
			_collect(c)

func _collect(c: Dictionary) -> void:
	c.collected = true
	var pos: Vector3 = c.root.global_position
	var col := Color(1.0, 0.78, 0.25) if c.id == 100 else Color(0.35, 0.6, 1.0)
	if bursts:
		bursts.play(&"coin", pos, Vector3.UP, col)
		bursts.play(&"coin_ring", pos + Vector3(0, 0, 0.1), Vector3.UP, col)
		bursts.flash(pos, col, 3.0, 0.4, 5.0)
	_coin_fly.append({"c": c, "t": 0.0, "from": pos})

func _restore_coin(c: Dictionary) -> void:
	c.collected = false
	c.root.visible = true
	c.root.scale = Vector3.ONE * (1.35 if _hc else 1.0)
	c.root.position = EECoords.tile_center(c.tile.x, c.tile.y, -0.1)

# ============================================================================ portals

func _build_portals() -> void:
	for id in [242, 381]:
		var tiles := lvl.find_all(id)
		if tiles.is_empty():
			continue
		var rots := []
		for t in tiles:
			_portal_tiles[t] = id
			rots.append(float(int(lvl.get_extra(t.x, t.y).get("rotation", 0))) / 4.0)
		var q := QuadMesh.new()
		q.size = Vector2(1.45, 1.45) if id == 242 else Vector2(1.2, 1.2)
		var m := ShaderMaterial.new()
		m.shader = PORTAL_SHADER
		if id == 381:
			m.set_shader_parameter("invisible", 1.0)
		else:
			_portal_mat = m
		q.material = m
		_multimesh(q, tiles, Vector3(0, 0, Z_PORTAL), 1.0, false, rots).name = "Portals_%d" % id
		if id == 242:
			var gm := ShaderMaterial.new()
			gm.shader = GLOW_SHADER
			gm.set_shader_parameter("color", Color(0.3, 0.7, 1.0))
			gm.set_shader_parameter("intensity", 0.35)
			var gq := QuadMesh.new()
			gq.size = Vector2(2.4, 2.4)
			gq.material = gm
			_multimesh(gq, tiles, Vector3(0, 0, Z_PORTAL - 0.1), 1.0, false).name = "PortalGlow"

func portal_fx(from_tile, to_tile) -> void:
	if bursts == null:
		return
	for t in [from_tile, to_tile]:
		if t is Vector2i:
			var p := EECoords.tile_center(t.x, t.y, 0.0)
			bursts.play(&"portal", p, Vector3.UP, Color(0.5, 0.85, 1.0))
			bursts.flash(p, Color(0.45, 0.8, 1.0), 4.0, 0.35, 5.0)
	_portal_pulse = 1.0

var _portal_pulse := 0.0

# ============================================================================ spawn beacon + trophy

func _build_spawn() -> void:
	for t in lvl.find_all(255):
		var root := Node3D.new()
		root.name = "SpawnBeacon"
		root.position = EECoords.tile_center(t.x, t.y)
		add_child(root)
		var floor_y := -0.5
		var ring := MeshInstance3D.new()
		ring.mesh = FxMeshes.ring(0.46, 0.035)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.75, 0.85, 0.95)
		rm.metallic = 1.0
		rm.roughness = 0.2
		rm.emission_enabled = true
		rm.emission = Color(0.55, 0.85, 1.0)
		rm.emission_energy_multiplier = 2.2
		ring.material_override = rm
		ring.position = Vector3(0, floor_y + 0.04, 0)
		root.add_child(ring)
		var ring2 := MeshInstance3D.new()
		ring2.mesh = FxMeshes.ring(0.3, 0.02)
		ring2.material_override = rm
		ring2.position = Vector3(0, floor_y + 0.04, 0)
		ring2.name = "Inner"
		root.add_child(ring2)
		var beam := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.1, 3.2)
		beam.mesh = q
		var bm := ShaderMaterial.new()
		bm.shader = BEACON_SHADER
		beam.material_override = bm
		beam.position = Vector3(0, floor_y + 1.6, -0.35)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
		var l := OmniLight3D.new()
		l.light_color = Color(0.6, 0.85, 1.0)
		l.light_energy = 1.2
		l.omni_range = 3.5
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 40.0
		l.distance_fade_length = 10.0
		l.position = Vector3(0, floor_y + 0.4, 0.3)
		root.add_child(l)
		var p := _coin_sparkles(true)
		p.amount = 10
		(p.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.9, 0)
		p.position = Vector3(0, floor_y + 0.3, 0)
		root.add_child(p)
		_spawn_nodes.append(root)

var _spawn_nodes: Array = []
var _trophies: Array = []

func _build_trophy() -> void:
	for t in lvl.find_all(121):
		var root := Node3D.new()
		root.name = "Trophy"
		root.position = EECoords.tile_center(t.x, t.y, -0.15)
		add_child(root)
		var c := MeshInstance3D.new()
		c.mesh = FxMeshes.crown()
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.88, 0.9, 0.96)
		metal.metallic = 1.0
		metal.roughness = 0.15
		metal.emission_enabled = true
		metal.emission = Color(0.5, 0.6, 0.8)
		metal.emission_energy_multiplier = 0.4
		var gem := StandardMaterial3D.new()
		gem.albedo_color = Color(0.3, 0.6, 1.0)
		gem.emission_enabled = true
		gem.emission = Color(0.3, 0.65, 1.0)
		gem.emission_energy_multiplier = 2.0
		c.set_surface_override_material(0, metal)
		c.set_surface_override_material(1, gem)
		c.scale = Vector3.ONE * 0.75
		c.position = Vector3(0, -0.3, 0)
		root.add_child(c)
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.0, 2.0)
		halo.mesh = q
		var gm := ShaderMaterial.new()
		gm.shader = GLOW_SHADER
		gm.set_shader_parameter("color", Color(0.7, 0.85, 1.0))
		gm.set_shader_parameter("intensity", 0.5)
		halo.material_override = gm
		halo.position = Vector3(0, 0, -0.3)
		root.add_child(halo)
		_trophies.append(c)

# ============================================================================ runtime

## Accessibility: gameplay glyphs (keys, arrows, dots, crown glints) +50% size and emission; coins/portals too.
func set_high_contrast(on: bool) -> void:
	_hc = on
	for m in _hc_mats:
		m.set_shader_parameter("hc", 1.0 if on else 0.0)
	for c in _coins:
		if not c.collected:
			c.root.scale = Vector3.ONE * (1.35 if on else 1.0)
	if _portal_mat:
		_portal_mat.set_shader_parameter("intensity", 1.5 if on else 1.0)

func key_triggered(color: StringName, tile = null) -> void:
	for id in KEY_IDS:
		if KEY_IDS[id] == color and tile is Vector2i:
			flare(id, tile)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	# art pebbles: flares age out, active colours breathe faster, proximity glow follows the ball
	for id in _art_mats:
		var m: ShaderMaterial = _art_mats[id]
		var arr: Array = _flares[id]
		var packed := PackedVector4Array()
		for i in range(arr.size() - 1, -1, -1):
			var f: Vector4 = arr[i]
			f.z += delta
			if f.z > 2.5:
				arr.remove_at(i)
			else:
				arr[i] = f
		for f in arr:
			packed.append(f)
		while packed.size() < 4:
			packed.append(Vector4.ZERO)
		m.set_shader_parameter("flares", packed)
		m.set_shader_parameter("ball_pos", _ball_pos)
		if KEY_IDS.has(id):
			var color: StringName = KEY_IDS[id]
			var active := 1.0 if sim != null and sim.has_method("is_key_active") and sim.is_key_active(color) else 0.0
			_key_active[color] = move_toward(_key_active[color], active, delta * 4.0)
			m.set_shader_parameter("active", _key_active[color])
			_halo_mats[id].set_shader_parameter("active", 0.0)
	# barriers
	for b in _barriers:
		var solid := _query_solid(b.reps[0], b.style)
		var tgt := 0.0 if solid else 1.0
		if tgt != b.target:
			b.target = tgt
			b.flash = 1.0
		b.open = move_toward(b.open, b.target, delta / 0.45)
		b.flash = maxf(b.flash - delta * 2.0, 0.0)
		for m: ShaderMaterial in b.mats:
			m.set_shader_parameter("openness", b.open)
			m.set_shader_parameter("flash", b.flash)
	# coins
	for c in _coins:
		if c.collected:
			continue
		if sim != null and sim.has_method("is_coin_collected") and sim.is_coin_collected(c.tile.x, c.tile.y):
			_collect(c)
			continue
		c.mesh.rotation.y = t * 2.2 + c.ph
		c.mesh.position.y = sin(t * 2.0 + c.ph) * 0.06
	for c in _coins:
		if c.collected and _coin_fly.filter(func(f): return f.c == c).is_empty():
			if sim != null and sim.has_method("is_coin_collected") and not sim.is_coin_collected(c.tile.x, c.tile.y):
				_restore_coin(c)
	_update_coin_fly(delta)
	# portals
	_portal_pulse = maxf(_portal_pulse - delta * 2.0, 0.0)
	if _portal_mat:
		_portal_mat.set_shader_parameter("pulse", _portal_pulse)
	for n in _spawn_nodes:
		n.get_node("Inner").rotation.y = t * 1.5
	for c in _trophies:
		c.rotation.y = t * 0.8

## Collected coins spin up, rise and zip toward the top-left of the screen (where the HUD counter lives).
func _update_coin_fly(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for i in range(_coin_fly.size() - 1, -1, -1):
		var f: Dictionary = _coin_fly[i]
		f.t += delta
		var c: Dictionary = f.c
		var k: float = f.t / 0.7
		if k >= 1.0:
			c.root.visible = false
			_coin_fly.remove_at(i)
			continue
		var target: Vector3 = f.from + Vector3(-6, 6, 4)
		if cam:
			var vp := get_viewport().get_visible_rect().size
			target = cam.project_position(Vector2(vp.x * 0.06, vp.y * 0.07), 6.0)
		var rise: Vector3 = f.from + Vector3(0, 0.9, 0.4)
		var e := k * k * (3.0 - 2.0 * k)
		var a: Vector3 = f.from.lerp(rise, clampf(k * 3.0, 0.0, 1.0))
		c.root.global_position = a.lerp(target, pow(maxf(k - 0.25, 0.0) / 0.75, 2.0))
		c.mesh.rotation.y += delta * (10.0 + 30.0 * e)
		c.root.scale = Vector3.ONE * (1.0 + 0.4 * sin(k * PI)) * (1.0 - pow(k, 4.0) * 0.8)
