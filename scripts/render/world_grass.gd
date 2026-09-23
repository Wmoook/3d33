class_name WorldGrass
extends Node3D
## Dense GPU-instanced grass carpet on every up-facing grass surface (M_GRASS tops, and M_FOLIAGE tops
## that are ground mantles rather than tree canopies). MultiMesh chunks (frustum + range culled); each
## instance is a clump of curved, tapered blades (tall / short grass, clover, small flowers).
## Shader: shaders/world/grass_blade.gdshader (root->tip gradient, sun translucency, noise wind, ball push).
## Readability: blades never rise more than MAX_OVER_AIR over the tile top, stay short in front of the
## gameplay plane, are flattened around the ball, and stay tiny under gameplay glyph tiles.
## Usage: add_child(g); g.build(lvl, terrain); every frame g.update_focus(ball_world_pos, delta).

const CHUNK := 24                 # tiles per chunk side
const MAX_OVER_AIR := 0.35        # tallest blade tip above the tile top (tiles)
const Z_BACK := -1.8              # top strip runs from the back wall (~-1.9) ...
const Z_FRONT_TALL := -0.45       # ... tall grass only behind the ball's depth
const Z_LIP := 0.42               # short fuzz continues over the rounded front bevel up to here
const BEVEL_Z := 0.62             # terrain pillow profile (terrain_common Z_FG_TOP)

enum Kind { TALL, SHORT, CLOVER, FLOWER }

var material: ShaderMaterial
var stats := {}
var _rng := RandomNumberGenerator.new()
var _meshes := {}
var _chunks := {}                 # Vector2i -> {kind: [[Transform3D], [Color custom]]}

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	_rng.seed = 4242
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/world/grass_blade.gdshader")
	material.set_shader_parameter("day", 0.0 if WorldPalette.is_odyssey() else 1.0)
	bind_height(material, terrain)
	_meshes = {
		Kind.TALL: _clump_mesh(14, 0.18, 0.34, 0.016, 0.034, 0.17, 5, 1),
		Kind.SHORT: _clump_mesh(16, 0.07, 0.16, 0.014, 0.026, 0.14, 3, 2),
		Kind.CLOVER: _clover_mesh(),
		Kind.FLOWER: _flower_mesh(),
	}
	var W := lvl.width
	var H := lvl.height
	var cols := terrain.fgcol_img
	var sites := 0
	var n_inst := {Kind.TALL: 0, Kind.SHORT: 0, Kind.CLOVER: 0, Kind.FLOWER: 0}
	for y in range(1, H):
		for x in W:
			var i := y * W + x
			if not terrain.solid[i] or terrain.solid[i - W]:
				continue
			if not _is_ground_grass(terrain, lvl, x, y, W, H):
				continue
			sites += 1
			var base := cols.get_pixel(x, y)
			# glyph above (keys, arrows, coins, portals... any non-world block) -> keep it tiny
			var above: int = lvl.fg[i - W]
			var glyph := above != 0 and not WorldPalette.is_world_solid(above) and not WorldPalette.is_world_deco(above)
			var hmul := 0.3 if glyph else 1.0
			# ends of a ledge are rounded by the terrain: keep blades off the last few centimetres
			var open_l := x == 0 or not terrain.solid[i - 1] or (terrain.solid[i - 1] and terrain.solid[i - 1 - W])
			var open_r := x == W - 1 or not terrain.solid[i + 1] or (terrain.solid[i + 1] and terrain.solid[i + 1 - W])
			var x0 := x + (0.14 if open_l else 0.0)
			var x1 := x + 1.0 - (0.14 if open_r else 0.0)
			var zb := Z_BACK
			if terrain.pocket[i - W]:
				zb = -1.35
			var key := Vector2i(x / CHUNK, y / CHUNK)
			# tall grass on the top strip (behind the gameplay depth)
			var nt := 24 if not glyph else 0
			for k in nt:
				var p := Vector3(_rng.randf_range(x0, x1), -y, _rng.randf_range(zb, Z_FRONT_TALL))
				var s := _rng.randf_range(0.75, 1.05) * hmul
				_push(key, Kind.TALL, p, s, _vary(base, 0.12), _rng.randf() * 0.99)
				n_inst[Kind.TALL] += 1
			# short grass over the strip
			for k in 12:
				var p := Vector3(_rng.randf_range(x0, x1), -y, _rng.randf_range(zb, 0.0))
				_push(key, Kind.SHORT, p, _rng.randf_range(0.7, 1.15) * hmul, _vary(base, 0.12), _rng.randf() * 0.99)
				n_inst[Kind.SHORT] += 1
			# the rounded front lip: turf growing out of the bevel, perpendicular to it, so the lawn edge
			# reads as soft grass instead of a hard line (SNAP: rooted exactly on the sculpted surface;
			# covers only the solid tile's own front face)
			for k in 14:
				var d := _rng.randf_range(0.01, 0.3)
				var up := Vector3(0.0, 1.0, 0.2 + d * 0.8).normalized()
				var p := Vector3(_rng.randf_range(x0, x1), -y - d, -0.01)
				_push(key, Kind.SHORT, p, _rng.randf_range(0.75, 1.1) * minf(hmul, 0.85), _vary(base, 0.12), _rng.randf() * 0.99, up, true)
				n_inst[Kind.SHORT] += 1
			if _rng.randf() < 0.45:
				var z := _rng.randf_range(zb, 0.25)
				var p := Vector3(_rng.randf_range(x0, x1), -y - _bevel_drop(z), z)
				_push(key, Kind.CLOVER, p, _rng.randf_range(0.8, 1.2), _vary(base, 0.08), _rng.randf() * 0.99)
				n_inst[Kind.CLOVER] += 1
			if not glyph and _rng.randf() < 0.12:
				var p := Vector3(_rng.randf_range(x0, x1), -y, _rng.randf_range(zb, Z_FRONT_TALL - 0.2))
				_push(key, Kind.FLOWER, p, _rng.randf_range(0.8, 1.15), _vary(base, 0.08), 1.0 + float(_rng.randi() % 5) + _rng.randf() * 0.99)
				n_inst[Kind.FLOWER] += 1
	n_inst[Kind.SHORT] += _build_fringes(lvl, terrain)
	for key in _chunks:
		_make_chunk(key, _chunks[key])
	stats = {"sites": sites, "chunks": _chunks.size(), "tall": n_inst[Kind.TALL], "short": n_inst[Kind.SHORT],
		"clover": n_inst[Kind.CLOVER], "flower": n_inst[Kind.FLOWER]}
	_chunks.clear()

## Grass fringes where the lawn meets other ground: (a) tufts drooping from the lawn's lower edge over the
## front face of the earth / stone below it (covers only solid tiles), (b) blades leaning out over the open
## side of a lawn ledge (overhang <= 0.12 tile).
func _build_fringes(lvl: EELevel, terrain: WorldTerrain) -> int:
	var W := lvl.width
	var H := lvl.height
	var cols := terrain.fgcol_img
	var cm := canopy_map(terrain)
	var n := 0
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if not terrain.solid[i] or cm[i] or not is_leafy(terrain.mat_ids[i]):
				continue
			var base := cols.get_pixel(x, y)
			var key := Vector2i(x / CHUNK, y / CHUNK)
			var below := i + W
			# (the sculpted front sits ~0.9-1.1 deep inside a mass, so the tufts root just proud of it)
			if terrain.solid[below] and not is_leafy(terrain.mat_ids[below]):
				for k in 8:
					var up := Vector3(_rng.randf_range(-0.25, 0.25), -0.8, 0.6).normalized()
					var p := Vector3(x + _rng.randf(), -(y + 1) + _rng.randf_range(0.04, 0.14), -0.01)
					_push(key, Kind.SHORT, p, _rng.randf_range(0.9, 1.35), _vary(base, 0.12), _rng.randf() * 0.99, up, true)
					n += 1
			for side: int in [-1, 1]:
				var j: int = i + side
				if terrain.solid[j] and not is_leafy(terrain.mat_ids[j]) and terrain.solid[j - W]:
					for k in 4:
						var up := Vector3(side * 0.75, _rng.randf_range(-0.4, 0.1), 0.55).normalized()
						var p := Vector3(x + (0.0 if side < 0 else 1.0) - side * _rng.randf_range(0.04, 0.12), -(y + _rng.randf()), -0.01)
						_push(key, Kind.SHORT, p, _rng.randf_range(0.8, 1.2), _vary(base, 0.12), _rng.randf() * 0.99, up, true)
						n += 1
			if not terrain.solid[i - W]:
				for side: int in [-1, 1]:
					if terrain.solid[i + side]:
						continue
					for k in 4:
						var up := Vector3(side * 0.6, 0.8, _rng.randf_range(-0.1, 0.2)).normalized()
						var ex: float = x + (0.0 if side < 0 else 1.0) - side * _rng.randf_range(0.04, 0.12)
						var z := _rng.randf_range(-1.6, 0.25)
						var p := Vector3(ex, -y - _bevel_drop(z) - _rng.randf_range(0.0, 0.08), z)
						_push(key, Kind.SHORT, p, _rng.randf_range(0.6, 0.9), _vary(base, 0.12), _rng.randf() * 0.99, up)
						n += 1
	return n

## Shares the terrain's baked height field with a detail material (for SNAP instances).
static func bind_height(m: ShaderMaterial, terrain: WorldTerrain) -> void:
	if terrain.material:
		m.set_shader_parameter("height_tex", terrain.material.get_shader_parameter("height_tex"))
		m.set_shader_parameter("height_margin", terrain.material.get_shader_parameter("height_margin"))
	m.set_shader_parameter("level_size", Vector2(terrain.W, terrain.H))

## Every frame: the ball flattens nearby blades.
func update_focus(world_pos: Vector3, _delta: float) -> void:
	if material:
		material.set_shader_parameter("ball_pos", world_pos)

## A top that is lawn: M_GRASS, or an M_FOLIAGE mantle lying on earth/stone (not a tree canopy).
static func _is_ground_grass(terrain: WorldTerrain, lvl: EELevel, x: int, y: int, W: int, H: int) -> bool:
	var m: int = terrain.mat_ids[y * W + x]
	if m == WorldPalette.M_GRASS and WorldPalette.is_odyssey():
		return true
	if m != WorldPalette.M_FOLIAGE and m != WorldPalette.M_GRASS:
		return false
	return not canopy_column(terrain, x, y, W, H)

static func is_leafy(m: int) -> bool:
	return m == WorldPalette.M_FOLIAGE or m == WorldPalette.M_GRASS

## Walking down the column from a leafy tile: a tree canopy ends in a real gap (>= 3 tiles of air: the
## space under the crown) or on a trunk (wood); a ground mantle ends on earth / stone, possibly across
## small holes (windows, pores). Shared with WorldFoliage.
static func canopy_column(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> bool:
	return canopy_map(terrain)[y * W + x] == 1

## Per-tile canopy classification (1 = tree crown), cached on the terrain. Each 4-connected leafy mass
## votes with the column walk (_canopy_walk) of its tiles: a mass is a crown if >= 35% of its tiles walk
## down into open space or a trunk; otherwise it is a ground mantle (lawn).
static func canopy_map(terrain: WorldTerrain) -> PackedByteArray:
	if terrain.has_meta(&"canopy_map"):
		return terrain.get_meta(&"canopy_map")
	var W := terrain.W
	var H := terrain.H
	var out := PackedByteArray()
	out.resize(W * H)
	var seen := PackedByteArray()
	seen.resize(W * H)
	for i0 in W * H:
		if seen[i0] or not terrain.solid[i0] or not is_leafy(terrain.mat_ids[i0]):
			continue
		var comp := PackedInt32Array()
		var stack := PackedInt32Array([i0])
		seen[i0] = 1
		var votes := 0
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			comp.append(i)
			var x := i % W
			var y := i / W
			if WorldPalette.is_odyssey():
				if y < 22:
					votes += 1
			elif _canopy_walk(terrain, x, y, W, H) or _leafy_extent(terrain, x, y, W, H) >= 6:
				votes += 1   # hangs over open space / a trunk, or is a thick crown (lawns are thin mantles)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if not seen[j] and terrain.solid[j] and is_leafy(terrain.mat_ids[j]):
					seen[j] = 1
					stack.append(j)
		if float(votes) >= 0.35 * comp.size():
			for i in comp:
				out[i] = 1
	terrain.set_meta(&"canopy_map", out)
	return out

## Contiguous leafy tiles in the column through (x, y).
static func _leafy_extent(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> int:
	var n := 1
	for dir: int in [-1, 1]:
		var yy: int = y + dir
		while yy >= 0 and yy < H and terrain.solid[yy * W + x] and is_leafy(terrain.mat_ids[yy * W + x]):
			n += 1
			yy += dir
	return n

static func _canopy_walk(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> bool:
	var air := 0
	for d in range(1, 30):
		var yy := y + d
		if yy >= H:
			return false
		var j := yy * W + x
		if not terrain.solid[j]:
			# only real open space counts (not the pores / windows of a dithered mass)
			if not terrain.pocket[j] and _open_row(terrain, x, yy, W):
				air += 1
				if air >= 3:
					return true
			continue
		air = 0
		var mj: int = terrain.mat_ids[j]
		if is_leafy(mj):
			continue   # FV paints its crowns with a foliage/grass dither
		# a trunk (wood, or a narrow earth column standing in open air) holds up a crown
		if mj == WorldPalette.M_WOOD:
			return true
		return yy + 2 < H and _narrow_run(terrain, x, yy, W, 7) and _narrow_run(terrain, x, yy + 1, W, 7) and _narrow_run(terrain, x, yy + 2, W, 7)
	return false

## At least 4 of the 5 tiles centred on (x, y) in the row are air.
static func _open_row(terrain: WorldTerrain, x: int, y: int, W: int) -> bool:
	var n := 0
	for dx in range(-2, 3):
		var xx := clampi(x + dx, 0, W - 1)
		if not terrain.solid[y * W + xx]:
			n += 1
	return n >= 3

## True if the solid run through (x, y) along the row is at most `maxw` wide with open air at both ends.
static func _narrow_run(terrain: WorldTerrain, x: int, y: int, W: int, maxw: int) -> bool:
	var l := x
	if not terrain.solid[y * W + x]:
		return false
	while l > 0 and terrain.solid[y * W + l - 1] and x - l < maxw:
		l -= 1
	var r := x
	while r < W - 1 and terrain.solid[y * W + r + 1] and r - x < maxw:
		r += 1
	if r - l + 1 > maxw:
		return false
	if l <= 0 or r >= W - 1:
		return false
	var a := y * W + l - 1
	var b := y * W + r + 1
	# open air on both sides (not the pores of a dithered mass)
	return not terrain.solid[a] and not terrain.solid[b] and not terrain.pocket[a] and not terrain.pocket[b]

## The terrain's rounded front bevel: how far below the tile top the surface is at depth z (> 0).
static func _bevel_drop(z: float) -> float:
	if z <= 0.0:
		return 0.0
	var u := clampf(z / BEVEL_Z, 0.0, 0.98)
	return 0.5 * (1.0 - sqrt(1.0 - u * u)) + 0.015

## c = painted tint (sRGB); code = random in [0,1) or 1 + flower palette index + random.
## snap: p.z is an offset from the sculpted surface at the root (resolved on the GPU from the height bake).
func _push(key: Vector2i, kind: int, p: Vector3, s: float, c: Color, code: float, up := Vector3.UP, snap := false) -> void:
	if snap:
		code += 10.0
	if not _chunks.has(key):
		_chunks[key] = {}
	var ch: Dictionary = _chunks[key]
	if not ch.has(kind):
		ch[kind] = [[], []]
	var yaw := _rng.randf_range(-1.1, 1.1)   # blades mostly face the camera (never edge-on slivers)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s))
	if up != Vector3.UP:
		b = Basis(Quaternion(Vector3.UP, up)) * b
	ch[kind][0].append(Transform3D(b, p))
	var lc := c.srgb_to_linear()
	ch[kind][1].append(Color(lc.r, lc.g, lc.b, code))

func _make_chunk(key: Vector2i, ch: Dictionary) -> void:
	var origin := Vector3((key.x + 0.5) * CHUNK, -(key.y + 0.5) * CHUNK, 0.0)
	for kind in ch:
		var xs: Array = ch[kind][0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false   # vertex COLOR carries blade data; the tint lives in custom data
		mm.use_custom_data = true
		mm.mesh = _meshes[kind]
		mm.instance_count = xs.size()
		for k in xs.size():
			var t: Transform3D = xs[k]
			t.origin -= origin
			mm.set_instance_transform(k, t)
			mm.set_instance_custom_data(k, ch[kind][1][k])
		var mi := MultiMeshInstance3D.new()
		mi.name = "G_%d_%d_%d" % [key.x, key.y, kind]
		mi.multimesh = mm
		mi.material_override = material
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 95.0 if kind != Kind.SHORT else 80.0
		mi.visibility_range_end_margin = 8.0
		add_child(mi)

func _vary(c: Color, a: float) -> Color:
	var f := 1.0 + _rng.randf_range(-a, a)
	return Color(c.r * f, c.g * f, c.b * f, 1.0)

## Clump of n curved tapered blades. Vertex COLOR: r = t along blade (0 root..1 tip), g = per-blade
## random, b = part (0 blade, 0.5 stem, 1 petal/leaf), a = sway weight. UV.x across the blade.
func _clump_mesh(n: int, hmin: float, hmax: float, wmin: float, wmax: float, radius: float, segs: int, seed_v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 97 + 13
	for b in n:
		var ang := r.randf() * TAU
		var rad := radius * sqrt(r.randf())
		var root := Vector3(cos(ang) * rad, -0.01, sin(ang) * rad * 0.8)
		var h := r.randf_range(hmin, hmax)
		var w := r.randf_range(wmin, wmax)
		var face := r.randf_range(-0.9, 0.9)
		var lean := Vector3(sin(face + r.randf_range(-1.2, 1.2)), 0, cos(face + r.randf_range(-1.2, 1.2))).normalized()
		var curve := r.randf_range(0.15, 0.55)
		_blade(st, root, h, w, face, lean, curve, segs, r.randf(), 0.0)
	return st.commit()

func _blade(st: SurfaceTool, root: Vector3, h: float, w: float, face: float, lean: Vector3, curve: float, segs: int, rnd: float, part: float) -> void:
	var side := Vector3(cos(face), 0, -sin(face))       # across the blade (horizontal)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_t := 0.0
	for j in segs + 1:
		var t := float(j) / segs
		# arc: rises and bends over along `lean` (quadratic), keeping roughly constant length
		var bend := curve * t * t
		var c := root + Vector3.UP * h * t * (1.0 - 0.35 * bend) + lean * h * bend
		var wd := w * (1.0 - pow(t, 1.6)) * (0.6 + 0.4 * sin(minf(t * 3.0, 1.0) * PI * 0.5))
		var tang := (Vector3.UP * (1.0 - 0.7 * curve * t) + lean * 2.0 * curve * t).normalized()
		var nrm := side.cross(tang).normalized()
		var l := c - side * wd * 0.5
		var rr := c + side * wd * 0.5
		if j > 0:
			var a := pow(prev_t, 1.5)
			var a2 := pow(t, 1.5)
			var c0 := Color(prev_t, rnd, part, a)
			var c1 := Color(t, rnd, part, a2)
			var n0 := nrm
			_v(st, prev_l, (n0 - side * 0.45).normalized(), c0, Vector2(0, prev_t))
			_v(st, prev_r, (n0 + side * 0.45).normalized(), c0, Vector2(1, prev_t))
			_v(st, rr, (n0 + side * 0.45).normalized(), c1, Vector2(1, t))
			_v(st, prev_l, (n0 - side * 0.45).normalized(), c0, Vector2(0, prev_t))
			_v(st, rr, (n0 + side * 0.45).normalized(), c1, Vector2(1, t))
			_v(st, l, (n0 - side * 0.45).normalized(), c1, Vector2(0, t))
		prev_l = l
		prev_r = rr
		prev_t = t

func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.set_uv(uv)
	st.add_vertex(p)

## Low clover patch: several trefoils (three heart leaflets on short stems) + a few short blades.
func _clover_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 555
	for k in 5:
		var ang := r.randf() * TAU
		var rad := 0.1 * sqrt(r.randf())
		var c := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad * 0.8)
		var hh := r.randf_range(0.035, 0.075)
		var top := c + Vector3(0, hh, 0)
		_blade(st, c, hh, 0.006, r.randf() * TAU, Vector3.UP, 0.0, 1, r.randf(), 0.5)
		var rot0 := r.randf() * TAU
		var tilt := r.randf_range(0.35, 0.8)   # leaflets tilt up toward the light / camera
		var rnd := r.randf()
		for l in 3:
			var a := rot0 + l * TAU / 3.0
			var dir := Vector3(cos(a), 0, sin(a))
			var up := Vector3(0, 1, 0).lerp(Vector3(0, 0, 1), 0.3).normalized()
			var ls := r.randf_range(0.026, 0.036)
			# heart leaflet as a small fan, tilted up
			var ctr := top + dir * ls * 0.55 + Vector3.UP * ls * 0.25
			var nrm := (up + dir * tilt * 0.4).normalized()
			var pts: Array[Vector3] = []
			for s in 9:
				var th := float(s) / 8.0 * TAU
				var rr: float = ls * (0.62 + 0.38 * abs(sin(th * 0.5 + 0.0))) * (0.85 + 0.15 * cos(th))
				var q: Vector3 = Vector3(cos(th), 0, sin(th)) * rr * 0.55
				# rotate leaflet into place (tilted plane)
				var qq: Vector3 = (dir * q.x + dir.cross(Vector3.UP) * q.z)
				pts.append(ctr + qq + Vector3.UP * q.x * tilt * 0.8)
			var cc := Color(0.6, rnd, 1.0, 0.4)
			var cc0 := Color(0.45, rnd, 1.0, 0.3)
			for s in 8:
				_v(st, ctr, nrm, cc0, Vector2(0.5, 0.5))
				_v(st, pts[s], nrm, cc, Vector2(0, 1))
				_v(st, pts[s + 1], nrm, cc, Vector2(1, 1))
	for b in 4:
		var ang := r.randf() * TAU
		var root := Vector3(cos(ang) * 0.1, -0.01, sin(ang) * 0.08)
		_blade(st, root, r.randf_range(0.05, 0.1), 0.012, r.randf_range(-0.8, 0.8), Vector3(r.randf_range(-1, 1), 0, 1).normalized(), 0.3, 3, r.randf(), 0.0)
	return st.commit()

## Small wild flower: a thin stem with leaves and a 6-petal head facing up/forward (petal colour =
## INSTANCE_CUSTOM.rgb).
func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 909
	for f in 2:
		var root := Vector3(r.randf_range(-0.05, 0.05), -0.01, r.randf_range(-0.04, 0.04))
		var h := r.randf_range(0.17, 0.27) if f == 0 else r.randf_range(0.11, 0.17)
		var lean := Vector3(r.randf_range(-0.4, 0.4), 0, 1).normalized()
		_blade(st, root, h, 0.007, r.randf_range(-0.5, 0.5), lean, 0.12, 3, r.randf(), 0.5)
		var head := root + Vector3.UP * h * (1.0 - 0.35 * 0.12) + lean * h * 0.12
		var nrm := Vector3(0, 0.75, 0.66).normalized()
		var ax1 := Vector3(1, 0, 0)
		var ax2 := nrm.cross(ax1).normalized()
		var pr := r.randf_range(0.022, 0.03)
		for p in 6:
			var a0 := p * TAU / 6.0
			var a1 := a0 + TAU / 6.0 * 0.5
			var a2 := a0 - TAU / 6.0 * 0.5
			var tip := head + (ax1 * cos(a0) + ax2 * sin(a0)) * pr
			var s1 := head + (ax1 * cos(a1) + ax2 * sin(a1)) * pr * 0.55
			var s2 := head + (ax1 * cos(a2) + ax2 * sin(a2)) * pr * 0.55
			var cp := Color(1.0, 0.5, 1.0, 1.0)
			_v(st, head, nrm, Color(0.95, 0.5, 1.0, 1.0), Vector2(0.5, 0.5))
			_v(st, s2, nrm, cp, Vector2(0, 1))
			_v(st, tip, nrm, cp, Vector2(0.5, 1))
			_v(st, head, nrm, Color(0.95, 0.5, 1.0, 1.0), Vector2(0.5, 0.5))
			_v(st, tip, nrm, cp, Vector2(0.5, 1))
			_v(st, s1, nrm, cp, Vector2(1, 1))
		# golden centre (uv.x = 2 marks it)
		for s in 6:
			var a0 := s * TAU / 6.0
			var a1 := a0 + TAU / 6.0
			var cc := Color(1.0, 0.5, 1.0, 1.0)
			_v(st, head + nrm * 0.003, nrm, cc, Vector2(2, 0))
			_v(st, head + nrm * 0.003 + (ax1 * cos(a0) + ax2 * sin(a0)) * pr * 0.28, nrm, cc, Vector2(2, 0))
			_v(st, head + nrm * 0.003 + (ax1 * cos(a1) + ax2 * sin(a1)) * pr * 0.28, nrm, cc, Vector2(2, 0))
	# a few short grass blades around the stems
	for b in 5:
		var ang := r.randf() * TAU
		var root := Vector3(cos(ang) * 0.07, -0.01, sin(ang) * 0.06)
		_blade(st, root, r.randf_range(0.06, 0.12), 0.013, r.randf_range(-0.8, 0.8), Vector3(r.randf_range(-1, 1), 0, 1).normalized(), 0.3, 3, r.randf(), 0.0)
	return st.commit()
