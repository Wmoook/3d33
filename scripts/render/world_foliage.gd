class_name WorldFoliage
extends Node3D
## Canopy leaf cards: alpha-tested photoscanned leaf clusters (assets/world/pbr/leaf_cluster_*.png, from
## Poly Haven shrub_04, CC0) layered over the painted tree canopies (world's leaf domes stay the base).
## Tinted by the painting (hue = each tile's colour; the texture adds leaf luminance + normals), soft
## backlit translucency, wind flutter (shaders/world/leaf_card.gdshader).
## Readability: cards stay inside the canopy's solid footprint; they may overhang open air by at most
## EDGE_OVER (sides/bottom) or TOP_OVER (top fringe, like grass).
## Also exposes `leaf_spawn_points` (world positions under canopy bottoms) for falling-leaf FX.

const CHUNK := 24
const EDGE_OVER := 0.12
const TOP_OVER := 0.3
const VIS_R := 0.43               # visible cluster radius as a fraction of the card size

var material: ShaderMaterial
var stats := {}
var leaf_spawn_points := PackedVector3Array()
var _rng := RandomNumberGenerator.new()
var _chunks := {}

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	_rng.seed = 777
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/world/leaf_card.gdshader")
	material.set_shader_parameter("leaf_albedo", load("res://assets/world/pbr/leaf_cluster_albedo.png"))
	material.set_shader_parameter("leaf_normal", load("res://assets/world/pbr/leaf_cluster_normal.png"))
	material.set_shader_parameter("day", 0.0 if WorldPalette.is_odyssey() else 1.0)
	WorldGrass.bind_height(material, terrain)
	var W := lvl.width
	var H := lvl.height
	var canopy := PackedByteArray()
	canopy.resize(W * H)
	for y in H:
		for x in W:
			canopy[y * W + x] = 1 if _is_canopy(terrain, x, y, W, H) else 0
	var cols := terrain.fgcol_img
	var n_front := 0
	var n_fringe := 0
	var n_edge := 0
	var n_litter := 0
	for y in H:
		for x in W:
			var i := y * W + x
			if not canopy[i]:
				continue
			var base := cols.get_pixel(x, y)
			# open-air reach in each direction (tiles of leafy/woody mass before air or other terrain)
			var ext_l := _reach(terrain, canopy, x, y, -1, 0, W, H)
			var ext_r := _reach(terrain, canopy, x, y, 1, 0, W, H)
			var ext_u := _reach(terrain, canopy, x, y, 0, -1, W, H)
			var ext_d := _reach(terrain, canopy, x, y, 0, 1, W, H)
			var inner := minf(minf(ext_l, ext_r), minf(ext_u, ext_d))
			var key := Vector2i(x / CHUNK, y / CHUNK)
			# front cards: 1-2 per tile, bigger deeper inside the canopy
			var nf := 2 if inner >= 1.0 else 1
			for k in nf:
				var size := _rng.randf_range(0.8, 1.15) * clampf(0.95 + inner * 0.35, 0.95, 1.7)
				var c := _fit(x, y, size * VIS_R, ext_l + 0.5 + EDGE_OVER, ext_r + 0.5 + EDGE_OVER,
					ext_u + 0.5 + (TOP_OVER if ext_u < 0.5 else EDGE_OVER), ext_d + 0.5 + EDGE_OVER)
				if c.z <= 0.05:
					continue
				size = c.z / VIS_R
				# depth: SNAP onto the sculpted canopy surface, layered 0.03-0.3 in front of it
				var z := 0.03 + _rng.randf() * 0.27
				_push(key, Vector3(c.x, c.y, z), size, base, 0.75 + 0.25 * _rng.randf(), true)
				n_front += 1
			# top fringe: leafy silhouette over the canopy top (seen along the top strip)
			if ext_u < 0.5:
				for k in 3:
					var r := _rng.randf_range(0.22, 0.34)
					var cx := x + _rng.randf_range(0.15, 0.85)
					var cy := -y - r + TOP_OVER * _rng.randf_range(0.5, 1.0)
					_push(key, Vector3(cx, cy, _rng.randf_range(-1.6, 0.35)), r / VIS_R, base, 0.6 + 0.3 * _rng.randf())
					n_fringe += 1
			# outline breakers: small clusters hugging every open side (overhang <= EDGE_OVER) so the crown's
			# silhouette is leafy instead of the sculpted blob edge
			for side in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var e: float = ext_l if side.x < 0 else (ext_r if side.x > 0 else ext_d)
				if e >= 0.5:
					continue
				for k in 2:
					var r := _rng.randf_range(0.17, 0.27)
					var along := _rng.randf_range(0.1, 0.9)
					var out := 0.5 + EDGE_OVER - r      # centre offset from the tile centre toward the side
					var cx: float = x + (0.5 + side.x * out if side.x != 0 else along)
					var cy: float = y + (0.5 + side.y * out if side.y != 0 else along)
					_push(key, Vector3(cx, -cy, _rng.randf_range(0.02, 0.15)), r / VIS_R, base, 0.55 + 0.35 * _rng.randf(), true)
					n_edge += 1
			if ext_d < 0.5 and _rng.randf() < 0.35:
				leaf_spawn_points.append(Vector3(x + _rng.randf(), -y - 1.0, _rng.randf_range(-0.6, 0.6)))
	n_litter = _build_litter(lvl, terrain, canopy)
	for key in _chunks:
		_make_chunk(key, _chunks[key])
	_chunks.clear()
	stats = {"front": n_front, "fringe": n_fringe, "edge": n_edge, "litter": n_litter, "spawn_points": leaf_spawn_points.size()}

## Fallen leaves on the ground under / beside crowns: small leaf piles lying on the top strip, tilted a
## little toward the camera; colour = the crown's painted colour faded toward the ground's (dry litter).
func _build_litter(lvl: EELevel, terrain: WorldTerrain, canopy: PackedByteArray) -> int:
	var W := lvl.width
	var H := lvl.height
	var lm := litter_map(terrain)
	var cols := terrain.fgcol_img
	var n := 0
	for y in range(1, H):
		for x in W:
			var i := y * W + x
			if lm[i] < 60 or terrain.solid[i - W]:
				continue
			var above: int = lvl.fg[i - W]
			if above != 0 and not WorldPalette.is_world_solid(above) and not WorldPalette.is_world_deco(above):
				continue   # never over a gameplay glyph
			# the crown this litter fell from: first crown tile up the column
			var crown := cols.get_pixel(x, y)
			for d in range(1, 18):
				if y - d < 0:
					break
				if canopy[(y - d) * W + x]:
					crown = cols.get_pixel(x, y - d)
					break
			var ground := cols.get_pixel(x, y)
			var key := Vector2i(x / CHUNK, y / CHUNK)
			var cnt := int(2.0 + 5.0 * lm[i] / 255.0)
			for k in cnt:
				var size := _rng.randf_range(0.3, 0.5)
				var z := _rng.randf_range(-1.7, 0.3)
				var p := Vector3(x + _rng.randf_range(0.1, 0.9), -y + 0.015 - WorldGrass._bevel_drop(z), z)
				var c := crown.lerp(ground, _rng.randf_range(0.25, 0.55)).darkened(_rng.randf_range(0.1, 0.3))
				var roll := _rng.randf() * TAU
				var b := Basis(Vector3.RIGHT, -PI * 0.5 + _rng.randf_range(0.25, 0.6)) * Basis(Vector3.BACK, roll)
				_push_basis(key, Transform3D(b.scaled(Vector3.ONE * size), p), c, 0.35 + 0.35 * _rng.randf())
				n += 1
	return n

func update_focus(world_pos: Vector3, _delta: float) -> void:
	if material:
		material.set_shader_parameter("ball_pos", world_pos)

## Tree canopy: M_FOLIAGE that is not a ground mantle (walking down the column ends in air or a trunk).
static func _is_canopy(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> bool:
	var i := y * W + x
	if not terrain.solid[i] or not WorldGrass.is_leafy(terrain.mat_ids[i]):
		return false
	return WorldGrass.canopy_column(terrain, x, y, W, H)

## Leaf-litter weight per tile (0..255), cached on the terrain: the ground under a crown (first solid top
## below the crown's underside, within 14 tiles of air) and the trunk / earth right beside a crown, spread
## sideways with a soft falloff. Crown tiles themselves are 0.
static func litter_map(terrain: WorldTerrain) -> PackedByteArray:
	if terrain.has_meta(&"litter_map"):
		return terrain.get_meta(&"litter_map")
	var W := terrain.W
	var H := terrain.H
	var cm := WorldGrass.canopy_map(terrain)
	var raw := PackedFloat32Array()
	raw.resize(W * H)
	for x in W:
		var under := -1   # rows of air since the last crown tile above (-1 = no crown above)
		for y in H:
			var i := y * W + x
			if cm[i]:
				under = 0
				continue
			if not terrain.solid[i]:
				if under >= 0:
					under += 1
					if under > 14:
						under = -1
				continue
			if under >= 0:
				# ground under the crown: strongest right below it, fading with the drop
				var w := 1.0 - float(under) / 16.0
				raw[i] = maxf(raw[i], w)
				if y + 1 < H and terrain.solid[i + W]:
					raw[i + W] = maxf(raw[i + W], w * 0.5)   # the front face just under the top
			under = -1
	# beside crowns: trunks / earth / stone touching a crown tile get a litter dusting
	for y in H:
		for x in range(1, W - 1):
			var i := y * W + x
			if not terrain.solid[i] or cm[i]:
				continue
			var n := 0
			for d in [-1, 1, -W, W]:
				var j: int = i + d
				if j >= 0 and j < W * H and cm[j]:
					n += 1
			if n > 0:
				raw[i] = maxf(raw[i], 0.45 + 0.15 * n)
	var out := PackedByteArray()
	out.resize(W * H)
	for y in H:
		for x in W:
			var v := raw[y * W + x]
			for dx in [-2, -1, 1, 2]:
				var xx: int = clampi(x + dx, 0, W - 1)
				v = maxf(v, raw[y * W + xx] * (1.0 - absf(dx) * 0.3))
			if not terrain.solid[y * W + x] or cm[y * W + x]:
				v = 0.0
			out[y * W + x] = int(clampf(v, 0.0, 1.0) * 255.0)
	terrain.set_meta(&"litter_map", out)
	return out

## Tiles of canopy/trunk mass beyond (x, y) in direction (dx, dy) before open air, capped at 3.
## Leaves may spill over the first non-crown solid tile (trunk, bark top, earth) and stop there.
static func _reach(terrain: WorldTerrain, canopy: PackedByteArray, x: int, y: int, dx: int, dy: int, W: int, H: int) -> float:
	var n := 0
	for k in range(1, 4):
		var nx := x + dx * k
		var ny := y + dy * k
		if nx < 0 or ny < 0 or nx >= W or ny >= H:
			break
		var j := ny * W + nx
		if not terrain.solid[j]:
			break
		n = k
		if not canopy[j]:
			break   # leaves spill over one tile of the trunk / bark / earth they touch, never further
	return float(n)

## Random centre for a cluster of radius r inside the tile, limited by the allowed extents measured from
## the tile centre (left, right, up, down). Returns (cx, cy_world, r_fitted).
func _fit(x: int, y: int, r: float, el: float, er: float, eu: float, ed: float) -> Vector3:
	r = minf(r, minf(minf(el, er), minf(eu, ed)))
	var lo_x := -(el - r)
	var hi_x := er - r
	var lo_y := -(eu - r)
	var hi_y := ed - r
	var ox := _rng.randf_range(maxf(lo_x, -0.5), minf(hi_x, 0.5))
	var oy := _rng.randf_range(maxf(lo_y, -0.5), minf(hi_y, 0.5))
	return Vector3(x + 0.5 + ox, -(y + 0.5 + oy), r)

## snap: p.z is an offset from the sculpted surface under the card centre (resolved on the GPU).
func _push(key: Vector2i, p: Vector3, size: float, c: Color, shade: float, snap := false) -> void:
	var roll := _rng.randf() * TAU
	var b := Basis(Vector3.BACK, roll)
	b = Basis(Vector3.RIGHT, _rng.randf_range(-0.35, 0.35)) * Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)) * b
	_push_basis(key, Transform3D(b.scaled(Vector3.ONE * size), p), c, shade, snap)

func _push_basis(key: Vector2i, t: Transform3D, c: Color, shade: float, snap := false) -> void:
	if not _chunks.has(key):
		_chunks[key] = [[], []]
	_chunks[key][0].append(t)
	var lc := c.srgb_to_linear()
	var f := 1.0 + _rng.randf_range(-0.12, 0.12)
	# custom: rgb = tint (linear), a = atlas cell (0..3) + shade (0..0.99)
	_chunks[key][1].append(Color(lc.r * f, lc.g * f, lc.b * f, float(_rng.randi() % 4) + clampf(shade, 0.0, 0.99) + (10.0 if snap else 0.0)))

func _make_chunk(key: Vector2i, ch: Array) -> void:
	var origin := Vector3((key.x + 0.5) * CHUNK, -(key.y + 0.5) * CHUNK, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var xs: Array = ch[0]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xs.size()
	for k in xs.size():
		var t: Transform3D = xs[k]
		t.origin -= origin
		mm.set_instance_transform(k, t)
		mm.set_instance_custom_data(k, ch[1][k])
	var mi := MultiMeshInstance3D.new()
	mi.name = "L_%d_%d" % [key.x, key.y]
	mi.multimesh = mm
	mi.material_override = material
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 110.0
	mi.visibility_range_end_margin = 10.0
	add_child(mi)
