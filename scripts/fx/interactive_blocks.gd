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
	&"magenta": Color("#ff3bf0"),
}
const KEY_IDS := {6: &"red", 7: &"green", 8: &"blue", 409: &"magenta"}
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
## false on levels other than Odyssey: coin doors also show their required coin count.
var odyssey := true

var _art_mats := {}       # id -> ShaderMaterial (art pebbles: keys + crowns)
var _flares := {}         # id -> Array of Vector4(x, y, age, strength) (ring buffer of 4)
var _key_active := {}     # color -> float (smoothed)
var _ball_pos := Vector3(-1000, 0, 0)
var _field_mat: ShaderMaterial
var _halo_mats := {}
var _hc_mats: Array[ShaderMaterial] = []
var _hc := false
var _coin_scale := 1.0
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
			if not odyssey:
				# daylight: a deeper gold orb on a firmer dark backing so it never washes out on the sky
				gm.set_shader_parameter("color", Color(1.0, 0.72, 0.22))
				gm.set_shader_parameter("intensity", 1.1)
		var om := ShaderMaterial.new()
		om.shader = preload("res://shaders/fx/glyph_halo.gdshader") if dot else GLYPH_SHADER
		if not dot:
			om.set_shader_parameter("outline", 1.0)
		elif not odyssey:
			om.set_shader_parameter("strength", 0.85)
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
	var ink := {}   # region index -> Array of [tile, id]
	for id in [6, 7, 8, 5, 409]:
		var tiles := lvl.find_all(id)
		if not odyssey:
			tiles = _split_ink(id, tiles, ink)
		if tiles.is_empty():
			if not odyssey and (id == 5 or id == 6):
				_flares[id] = []   # ink letters still flare on touch
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
	for ri in ink:
		if INK_REGIONS[ri][3] < 0.0:
			_build_trim(ink[ri])
		else:
			_build_ink(INK_REGIONS[ri][0], ink[ri])

## Non-Odyssey art regions where crowns (5) / red keys (6) are the INK of painted lettering
## (FV: the Winners' Scroll names and the ΣX logo's gold inlays). [rect (tiles, y down), ids, z, gain]
const INK_REGIONS := [
	[Rect2i(350, 0, 48, 72), [5, 6], -0.88, 1.0],   # just above world's flat -0.9 ink floor (confirmed)
	[Rect2i(300, 14, 46, 29), [5], -0.88, -1.0],   # logo: gain < 0 = gilded edge trim on the letters, not ink (_build_trim)
]
var _ink_mats: Array[ShaderMaterial] = []

const TRIM_Z := 0.82        # the stone letters' front face (terrain front ~0.8)
const TRIM_ON_STONE := 0.08 # band overlap onto the letter
const TRIM_IN_AIR := 0.12   # band reach into the (passable) crown tile: within the contract's 0.12 bevel

## ΣX logo: every crown tile edge that touches a solid letter tile gets a narrow bevelled gold band hugging
## that stone edge (the painting's gold outline), instead of a filled tile floating in the sky.
func _build_trim(cells: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for c in cells:
		var t: Vector2i = c[0]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = t + d
			if q.x < 0 or q.y < 0 or q.x >= lvl.width or q.y >= lvl.height:
				continue
			if not WorldPalette.is_world_solid(lvl.get_fg(q.x, q.y)):
				continue
			# edge between t and q in world space; "out" points from the stone into the crown tile
			var cx: float = t.x + 0.5 + d.x * 0.5
			var cy: float = -(t.y + 0.5) - d.y * 0.5
			var out := Vector2(-d.x, d.y) as Vector2   # world y is up
			var along := Vector2(out.y, -out.x)
			var e := Vector2(cx, cy)
			var a0 := e - along * 0.5 - out * TRIM_ON_STONE
			var a1 := e + along * 0.5 - out * TRIM_ON_STONE
			var b0 := e - along * 0.5 + out * TRIM_IN_AIR
			var b1 := e + along * 0.5 + out * TRIM_IN_AIR
			var m0 := e - along * 0.5 + out * 0.02
			var m1 := e + along * 0.5 + out * 0.02
			var z1 := TRIM_Z + 0.05
			var nrm_top := Vector3(0, 0, 1)
			var nrm_bev := Vector3(out.x, out.y, 1.0).normalized()
			# flat top (on the stone edge) + bevel sloping down into the crown tile
			_tq(st, Vector3(a0.x, a0.y, z1), Vector3(a1.x, a1.y, z1), Vector3(m1.x, m1.y, z1), Vector3(m0.x, m0.y, z1), nrm_top)
			_tq(st, Vector3(m0.x, m0.y, z1), Vector3(m1.x, m1.y, z1), Vector3(b1.x, b1.y, TRIM_Z - 0.06), Vector3(b0.x, b0.y, TRIM_Z - 0.06), nrm_bev)
			n += 1
	if n == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "GildedTrim"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/gold_trim.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_ink_mats.append(m)

func _tq(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(nrm)
		st.add_vertex(v)

func _split_ink(id: int, tiles: Array[Vector2i], ink: Dictionary) -> Array[Vector2i]:
	var keep: Array[Vector2i] = []
	for t in tiles:
		var hit := -1
		for ri in INK_REGIONS.size():
			var r: Array = INK_REGIONS[ri]
			if (r[0] as Rect2i).has_point(t) and (r[1] as Array).has(id):
				hit = ri
				break
		if hit < 0:
			keep.append(t)
		else:
			if not ink.has(hit):
				ink[hit] = []
			ink[hit].append([t, id])
	return keep

## One flat quad per ink region; the letters come from a 1-texel-per-tile mask (R gold, G vermilion).
func _build_ink(rect: Rect2i, cells: Array) -> void:
	var r := rect.grow(1)
	var img := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	for c in cells:
		var t: Vector2i = c[0]
		var col := img.get_pixel(t.x - r.position.x, t.y - r.position.y)
		if c[1] == 5:
			col.r = 1.0
		else:
			col.g = 1.0
		img.set_pixel(t.x - r.position.x, t.y - r.position.y, col)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/ink_letters.gdshader")
	m.set_shader_parameter("mask", ImageTexture.create_from_image(img))
	m.set_shader_parameter("rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var mi := MeshInstance3D.new()
	mi.name = "InkLetters"
	var q := QuadMesh.new()
	q.size = Vector2(r.size)
	mi.mesh = q
	mi.material_override = m
	var z: float = -1.2
	for reg in INK_REGIONS:
		if reg[0] == rect:
			z = reg[2]
			m.set_shader_parameter("gain", reg[3])
	mi.position = Vector3(r.position.x + r.size.x * 0.5, -(r.position.y + r.size.y * 0.5), z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_ink_mats.append(m)

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
	for m in _veil_mats:
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
		# one barrier per required count (coin doors store it in extra.rotation), so each opens on its own
		var groups := {}
		for t in lvl.find_all(id):
			var num := int(lvl.get_extra(t.x, t.y).get("rotation", 0))
			if not groups.has(num):
				groups[num] = [] as Array[Vector2i]
			groups[num].append(t)
		for num in groups:
			_build_barrier(id, groups[num])

func _build_barrier(id: int, tiles: Array[Vector2i]) -> void:
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
	mi.name = "Barrier_%d_%d_%d" % [id, tiles[0].x, tiles[0].y]
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
	var labels: Array[Label3D] = []
	var need := int(lvl.get_extra(tiles[0].x, tiles[0].y).get("rotation", 0))
	if not odyssey and style == 2:
		labels = _coin_labels(tiles, mask, need, front)
	_barriers.append({"id": id, "mats": mats, "reps": reps, "open": o, "target": o, "style": style,
		"center": _centroid(tiles), "color": spec[1], "flash": 0.0, "labels": labels, "need": need, "slab": mi})

## Coin door reached its count (non-Odyssey): the bars grind up with dust, sparks and a warm flare at every
## piece of the door; the grand final gate (the highest count in the level) gets a much bigger unsealing.
func _unseal(b: Dictionary) -> void:
	if bursts == null:
		return
	var grand := true
	for o in _barriers:
		if o.style == 2 and o.need > b.need:
			grand = false
	var col := Color(1.0, 0.78, 0.35)
	var spots: Array[Vector3] = []
	for l: Label3D in b.labels:
		spots.append(Vector3(l.position.x, l.position.y, 0.1))
	if spots.is_empty():
		spots.append(b.center)
	# only pieces near the ball (off-screen doors would just steal the burst pools)
	spots = spots.filter(func(q: Vector3) -> bool: return Vector2(q.x - _ball_pos.x, q.y - _ball_pos.y).length() < 30.0)
	for p in spots:
		bursts.play(&"dust", p + Vector3(0, -0.5, 0.2), Vector3.UP, Color(0.85, 0.75, 0.55), 1.0)
		bursts.play(&"sparks", p + Vector3(0, 0.4, 0.2), Vector3.UP, col, 1.0)
		bursts.flash(p, col, 5.0 if grand else 3.0, 0.7 if grand else 0.45, 7.0 if grand else 5.0)
		if grand:
			bursts.play(&"crown", p, Vector3.UP, col)
			bursts.play(&"coin_ring", p + Vector3(0, 0, 0.3), Vector3.UP, col)
			bursts.play(&"shards", p, Vector3.UP, col, 0.8)
	if mech:
		for p in spots:
			mech.spawn_ripple(p + Vector3(0, 0, 0.4), col, 6.0 if grand else 3.0, 1.2 if grand else 0.7, 3 if grand else 1)

var mech   # FxMechBlocks (ripple pool), set by ActorsView

## Readability: the number of coins a coin door needs, once per connected piece (EE prints it on the door).
func _coin_labels(tiles: Array[Vector2i], mask: Dictionary, need: int, _front: float) -> Array[Label3D]:
	var out: Array[Label3D] = []
	var seen := {}
	for t in tiles:
		if seen.has(t):
			continue
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [t]
		seen[t] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if mask.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		var l := Label3D.new()
		l.text = str(need)
		l.font_size = 72
		l.outline_size = 22
		l.pixel_size = 0.0068
		l.modulate = Color(1.0, 0.93, 0.62)
		l.outline_modulate = Color(0.08, 0.04, 0.0)
		l.shaded = false
		l.double_sided = false
		l.no_depth_test = false
		l.render_priority = 2
		var cm := Vector2.ZERO
		for q in comp:
			cm += Vector2(q) + Vector2(0.5, 0.5)
		cm /= comp.size()
		l.position = Vector3(cm.x, -cm.y, 0.24)   # in front of the bars (z 0.05 + radius)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(l)
		out.append(l)
	return out

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
	mi.name = "CoinGateBars_%d_%d" % [tiles[0].x, tiles[0].y]
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
		rmi.name = "CoinGateRails_%d_%d" % [tiles[0].x, tiles[0].y]
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
			var glint: ShaderMaterial = null
			if not odyssey:
				glint = _hero_relic(root, mi, sp, id == 101, t)
			_coins.append({"root": root, "mesh": mi, "tile": t, "id": id, "collected": false, "ph": randf() * TAU,
				"glint": glint, "seen": false})

## Non-Odyssey levels (FV: every gold coin is the prize at the end of a trial room): the coin becomes a
## floating relic: bigger, a shaft of light falling onto it, a glowing pedestal aura beneath, denser
## sparkles and a star glint that blooms every few seconds. Blue coins get a softer version.
func _hero_relic(root: Node3D, coin: MeshInstance3D, sparkles: GPUParticles3D, blue: bool, t: Vector2i) -> ShaderMaterial:
	var col := Color(0.35, 0.6, 1.0) if blue else Color(1.0, 0.72, 0.28)
	var k := 0.6 if blue else 1.0
	coin.scale = Vector3.ONE * (0.7 if blue else 0.8)
	# god ray: brightest where it lands on the relic, fading upward
	var ray := MeshInstance3D.new()
	ray.name = "GodRay"
	var rq := QuadMesh.new()
	rq.size = Vector2(1.5, 5.0)
	ray.mesh = rq
	var rm := ShaderMaterial.new()
	rm.shader = BEACON_SHADER
	rm.set_shader_parameter("color", col.lerp(Color.WHITE, 0.35))
	rm.set_shader_parameter("intensity", 0.8 * k)
	ray.material_override = rm
	ray.position = Vector3(0, 2.1, -0.45)
	ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ray)
	# pedestal aura: a wide soft ellipse of light under the relic
	var aura := MeshInstance3D.new()
	aura.name = "PedestalAura"
	var aq := QuadMesh.new()
	aq.size = Vector2(2.4, 0.8)
	aura.mesh = aq
	var am := ShaderMaterial.new()
	am.shader = GLOW_SHADER
	am.set_shader_parameter("color", col)
	am.set_shader_parameter("intensity", 0.7 * k)
	aura.material_override = am
	aura.position = Vector3(0, -0.5, -0.2)
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(aura)
	sparkles.amount = 10 if blue else 16
	# star glint (the "chime shimmer")
	var g := MeshInstance3D.new()
	g.name = "Glint"
	var gq := QuadMesh.new()
	gq.size = Vector2(1.8, 1.8)
	g.mesh = gq
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/fx/star_glint.gdshader")
	gm.set_shader_parameter("color", col.lerp(Color.WHITE, 0.4))
	gm.set_shader_parameter("intensity", 1.6 * k)
	gm.set_shader_parameter("phase", _tile_hash(t).x * 3.2)
	g.material_override = gm
	g.position = Vector3(0.18, 0.2, 0.25)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	# a small warm light so the relic lights its room
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.9 * k
	l.omni_range = 3.5
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	l.distance_fade_length = 8.0
	l.position = Vector3(0, 0, 0.6)
	root.add_child(l)
	return gm

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
		if odyssey:
			bursts.flash(pos, col, 3.0, 0.4, 5.0)
		else:
			# relic claimed: a crown of sparks, a big warm flare and a streak to the HUD
			bursts.play(&"crown", pos, Vector3.UP, col)
			bursts.flash(pos, col, 6.0 if c.id == 100 else 4.0, 0.7, 9.0)
	if c.get("glint"):
		c.glint.set_shader_parameter("pulse_boost", 2.0)
	_coin_fly.append({"c": c, "t": 0.0, "from": pos})

func _restore_coin(c: Dictionary) -> void:
	c.collected = false
	c.root.visible = true
	for nm in ["GodRay", "PedestalAura"]:
		var n := c.root.get_node_or_null(nm) as Node3D
		if n:
			n.visible = true
	c.root.scale = Vector3.ONE * _coin_scale
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
			if odyssey:
				rots.append(float(int(lvl.get_extra(t.x, t.y).get("rotation", 0))) / 4.0)
			else:
				# pair hue: a portal and its target share a colour (hash of the unordered id pair)
				var ex := lvl.get_extra(t.x, t.y)
				var a := int(ex.get("id", 0))
				var b := int(ex.get("target", 0))
				var key := mini(a, b) * 7919 + maxi(a, b) * 104729
				rots.append(fposmod(float((key * 2654435761) & 0xFFFF) / 65535.0, 1.0))
		if id == 242:
			_build_portal_blocks(tiles)
			continue
		var q := QuadMesh.new()
		q.size = Vector2(1.45, 1.45) if id == 242 else Vector2(1.2, 1.2)
		var m := ShaderMaterial.new()
		m.shader = PORTAL_SHADER
		if not odyssey:
			# "the Veil": shimmering membranes in stone rings instead of Odyssey's vortices
			m.shader = preload("res://shaders/fx/rift_portal.gdshader")   # voxel rifts (user: mirrors looked dumb)
			q.size = Vector2(1.22, 1.22) if id == 242 else Vector2(1.0, 1.0)   # <= 0.12 over neighbours
			_veil_mats.append(m)
		if id == 381:
			m.set_shader_parameter("invisible", 1.0)
		else:
			_portal_mat = m
		q.material = m
		var pmi := _multimesh(q, tiles, Vector3(0, 0, Z_PORTAL), 1.0, false, rots)
		pmi.name = "Portals_%d" % id
		if not odyssey:
			# daylight factor per rift (custom.z): brighter cores where open sky is nearby, halls unchanged
			var pm := pmi.multimesh
			for i in tiles.size():
				var c := pm.get_instance_custom_data(i)
				c.b = _daylight(tiles[i])
				pm.set_instance_custom_data(i, c)
		if id == 242:
			var gm := ShaderMaterial.new()
			gm.shader = GLOW_SHADER
			gm.set_shader_parameter("color", Color(0.3, 0.7, 1.0) if odyssey else Color(0.6, 0.85, 1.0))
			gm.set_shader_parameter("intensity", 0.35 if odyssey else 0.16)
			var gq := QuadMesh.new()
			gq.size = Vector2(2.4, 2.4)
			gq.material = gm
			var pg := _multimesh(gq, tiles, Vector3(0, 0, Z_PORTAL - 0.1), 1.0, false)
			pg.name = "PortalGlow"
			pg.visible = odyssey   # the rifts carry their own light

var _veil_mats: Array[ShaderMaterial] = []
var _veil_flares: Array = []   # Vector4(x, y, age, strength)

## Portals 242 on every level (user: "portal should be a 3D block based on the original EE design"): a
## crystal block per tile (one MultiMesh, one shader). Custom data: x = EE shimmer phase ((cx+cy) % 15)/15,
## y = rotation/4 (exit direction; the chevron points that way), z = random.
func _build_portal_blocks(tiles: Array[Vector2i]) -> void:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/portal_block.gdshader")
	var mesh := FxMeshes.portal_block().duplicate() as Mesh
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = tiles.size()
	for i in tiles.size():
		var t := tiles[i]
		var rot := int(lvl.get_extra(t.x, t.y).get("rotation", 0)) % 4
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, EECoords.tile_center(t.x, t.y)))
		mm.set_instance_custom_data(i, Color(float((t.x + t.y) % 15) / 15.0, rot / 4.0, _tile_hash(t).x, 0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "PortalBlocks"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_portal_mat = m
	_veil_mats.append(m)
	_hc_mats.append(m)

## 0..1: how bright the backdrop around a rift is: share of the 5x5 neighbourhood that is open air with the
## sky showing behind it (no back wall: bg empty or a painted-sky id). Roofed but sky-backed rooms count as
## daylight (that's what washes the cores out); walled halls stay dark.
const SKY_BG := [0, 530, 531, 540, 541, 542, 543, 544]

func _daylight(t: Vector2i) -> float:
	var n := 0
	var hit := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := t.x + dx
			var y := t.y + dy
			if x < 0 or y < 0 or x >= lvl.width or y >= lvl.height:
				continue
			n += 1
			if FxOverlayMaps.is_open(lvl, x, y) and SKY_BG.has(lvl.get_bg(x, y)):
				hit += 1
	return clampf(float(hit) / maxf(n, 1.0) * 1.6, 0.0, 1.0)

func portal_fx(from_tile, to_tile) -> void:
	for t in [from_tile, to_tile]:
		if t is Vector2i and not _veil_mats.is_empty():
			var c := EECoords.tile_center(t.x, t.y)
			_veil_flares.push_front(Vector4(c.x, c.y, 0.0, 1.0))
			if _veil_flares.size() > 4:
				_veil_flares.pop_back()
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
	for t0 in lvl.find_all(255):
		# the beacon stands on the floor the ball lands on (the spawn tile itself may hang in the air)
		var t := t0
		if not odyssey:
			while t.y + 1 < lvl.height and t.y - t0.y < 12 and FxOverlayMaps.is_open(lvl, t.x, t.y + 1):
				t.y += 1
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
		# non-Odyssey (user: "a weird glowing line above me"): only the floor ring, nothing above the ball
		var beam := MeshInstance3D.new()
		beam.visible = odyssey
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
		p.visible = odyssey
		root.add_child(p)
		if not odyssey:
			ring2.visible = false   # one subtle ring only
			rm.emission_energy_multiplier = 1.2
			# the spawn light lit the lone back-wall tile above the FV spawn into a glowing grey "cube"
			l.visible = false
		_spawn_nodes.append(root)

var _spawn_nodes: Array = []
var _trophies: Array = []

func _build_trophy() -> void:
	if not odyssey:
		return   # other levels: FxShrine turns 121 into the winner's crown relic on its summit
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
		if not odyssey:
			# daylight: a pale silver cup vanishes against a bright sky -> warm gold, self-lit, on a dark backing
			metal.albedo_color = Color(1.0, 0.8, 0.35)
			metal.emission = Color(1.0, 0.7, 0.25)
			metal.emission_energy_multiplier = 0.9
			var back := MeshInstance3D.new()
			var bq := QuadMesh.new()
			bq.size = Vector2(1.9, 1.9)
			back.mesh = bq
			var bm := ShaderMaterial.new()
			bm.shader = preload("res://shaders/fx/glyph_halo.gdshader")
			bm.set_shader_parameter("strength", 0.7)
			back.material_override = bm
			back.position = Vector3(0, 0, -0.35)
			back.scale = Vector3.ONE * 2.6   # glyph_halo radius is 0.36 of the quad's local units
			root.add_child(back)
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
	set_glyph_boost(1.5 if on else 1.0)

func set_glyph_boost(amount: float) -> void:
	var k := clampf((amount - 1.0) / 0.5, 0.0, 3.0)   # shader "hc" 1.0 == +50%
	_hc = k > 0.0
	_coin_scale = 1.0 + 0.35 * k
	for m in _hc_mats:
		m.set_shader_parameter("hc", k)
	for c in _coins:
		if not c.collected:
			c.root.scale = Vector3.ONE * _coin_scale
	if _portal_mat:
		_portal_mat.set_shader_parameter("intensity", 1.0 + 0.5 * k)

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
	if not _ink_mats.is_empty():
		var fa := _age_flares(5, delta)
		var fb := _age_flares(6, delta)
		for m in _ink_mats:
			m.set_shader_parameter("flares", fa)
			m.set_shader_parameter("flares_b", fb)
	# barriers
	for b in _barriers:
		var solid := _query_solid(b.reps[0], b.style)
		var tgt := 0.0 if solid else 1.0
		if tgt != b.target:
			b.target = tgt
			b.flash = 1.0
			if tgt == 1.0 and not odyssey and b.style == 2:
				_unseal(b)
		b.open = move_toward(b.open, b.target, delta / 0.45)
		b.flash = maxf(b.flash - delta * 2.0, 0.0)
		# a fully open coin door is just its gold frame (rails): the empty membrane slab left a dark void
		# over the recessed rooms behind, so it is not drawn at all once open
		if b.style == 2 and b.has("slab"):
			(b.slab as Node3D).visible = b.open < 0.999
		for m: ShaderMaterial in b.mats:
			m.set_shader_parameter("openness", b.open)
			m.set_shader_parameter("flash", b.flash)
		for l: Label3D in b.labels:
			l.modulate.a = 1.0 - b.open
			l.outline_modulate.a = 1.0 - b.open
			l.visible = b.open < 0.99
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
	if not _veil_mats.is_empty():
		var packed := PackedVector4Array()
		for i in range(_veil_flares.size() - 1, -1, -1):
			var f: Vector4 = _veil_flares[i]
			f.z += delta
			if f.z > 3.0:
				_veil_flares.remove_at(i)
			else:
				_veil_flares[i] = f
		for f in _veil_flares:
			packed.append(f)
		while packed.size() < 4:
			packed.append(Vector4.ZERO)
		for m in _veil_mats:
			m.set_shader_parameter("flares", packed)
	for n in _spawn_nodes:
		n.get_node("Inner").rotation.y = t * 1.5
	for c in _trophies:
		c.rotation.y = t * 0.8

## Flares of an id that has no gem material (all its tiles are ink): age them here.
func _age_flares(id: int, delta: float) -> PackedVector4Array:
	var packed := PackedVector4Array()
	if _flares.has(id):
		var arr: Array = _flares[id]
		if not _art_mats.has(id):
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
	return packed

## Collected coins spin up, rise and zip toward the top-left of the screen (where the HUD counter lives).
func _update_coin_fly(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var trail_at := Vector3.INF
	for i in range(_coin_fly.size() - 1, -1, -1):
		var f: Dictionary = _coin_fly[i]
		f.t += delta
		var c: Dictionary = f.c
		var k: float = f.t / (0.7 if odyssey else 0.95)
		if k >= 1.0:
			c.root.visible = false
			if c.get("glint"):
				c.glint.set_shader_parameter("pulse_boost", 0.0)
			_coin_fly.remove_at(i)
			continue
		if c.get("glint"):
			c.glint.set_shader_parameter("pulse_boost", 2.0 * (1.0 - k))
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
		if not odyssey:
			for nm in ["GodRay", "PedestalAura"]:
				var n := c.root.get_node_or_null(nm) as Node3D
				if n:
					n.visible = false   # the relic leaves its shrine; the shaft goes out
			trail_at = c.root.global_position
	if not odyssey:
		_drive_fly_trail(trail_at)

var _fly_trail: GPUParticles3D

## A glittering streak behind a relic coin flying to the HUD (world-space particles, one shared emitter).
func _drive_fly_trail(at: Vector3) -> void:
	if _fly_trail == null:
		_fly_trail = _coin_sparkles(false)
		_fly_trail.name = "CoinFlyTrail"
		_fly_trail.amount = 48
		_fly_trail.lifetime = 0.6
		_fly_trail.local_coords = false
		_fly_trail.visibility_aabb = AABB(Vector3(-30, -30, -10), Vector3(60, 60, 20))
		var pm := _fly_trail.process_material as ParticleProcessMaterial
		pm.emission_sphere_radius = 0.12
		pm.gravity = Vector3.ZERO
		pm.color = Color(1.0, 0.85, 0.5)
		add_child(_fly_trail)
	_fly_trail.emitting = at.x != INF
	if at.x != INF:
		_fly_trail.global_position = at
