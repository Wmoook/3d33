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
				var z := 0.72 + _rng.randf() * 0.38 + minf(inner, 3.0) * 0.1
				_push(key, Vector3(c.x, c.y, z), size, base, 0.75 + 0.25 * _rng.randf())
				n_front += 1
			# top fringe: leafy silhouette over the canopy top (seen along the top strip)
			if ext_u < 0.5:
				for k in 3:
					var r := _rng.randf_range(0.22, 0.34)
					var cx := x + _rng.randf_range(0.15, 0.85)
					var cy := -y - r + TOP_OVER * _rng.randf_range(0.5, 1.0)
					_push(key, Vector3(cx, cy, _rng.randf_range(-1.6, 0.35)), r / VIS_R, base, 0.6 + 0.3 * _rng.randf())
					n_fringe += 1
			if ext_d < 0.5 and _rng.randf() < 0.35:
				leaf_spawn_points.append(Vector3(x + _rng.randf(), -y - 1.0, _rng.randf_range(-0.6, 0.6)))
	for key in _chunks:
		_make_chunk(key, _chunks[key])
	_chunks.clear()
	stats = {"front": n_front, "fringe": n_fringe, "spawn_points": leaf_spawn_points.size()}

func update_focus(world_pos: Vector3, _delta: float) -> void:
	if material:
		material.set_shader_parameter("ball_pos", world_pos)

## Tree canopy: M_FOLIAGE that is not a ground mantle (walking down the column ends in air or a trunk).
static func _is_canopy(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> bool:
	var i := y * W + x
	if not terrain.solid[i] or terrain.mat_ids[i] != WorldPalette.M_FOLIAGE:
		return false
	if WorldPalette.is_odyssey():
		return y < 22
	for d in range(1, 24):
		var yy := y + d
		if yy >= H:
			return false
		var j := yy * W + x
		if not terrain.solid[j]:
			return true
		var mj: int = terrain.mat_ids[j]
		if mj == WorldPalette.M_FOLIAGE:
			continue
		return mj == WorldPalette.M_WOOD
	return false

## Tiles of canopy/trunk mass beyond (x, y) in direction (dx, dy) before open air, capped at 3.
## Other terrain (earth, stone) counts as a hard stop (the leaves may only touch it).
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
		if not canopy[j] and terrain.mat_ids[j] != WorldPalette.M_WOOD:
			break
		n = k
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

func _push(key: Vector2i, p: Vector3, size: float, c: Color, shade: float) -> void:
	if not _chunks.has(key):
		_chunks[key] = [[], []]
	var roll := _rng.randf() * TAU
	var b := Basis(Vector3.BACK, roll)
	b = Basis(Vector3.RIGHT, _rng.randf_range(-0.35, 0.35)) * Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)) * b
	b = b.scaled(Vector3.ONE * size)
	_chunks[key][0].append(Transform3D(b, p))
	var lc := c.srgb_to_linear()
	var f := 1.0 + _rng.randf_range(-0.12, 0.12)
	# custom: rgb = tint (linear), a = atlas cell (0..3) + shade (0..0.99)
	_chunks[key][1].append(Color(lc.r * f, lc.g * f, lc.b * f, float(_rng.randi() % 4) + clampf(shade, 0.0, 0.99)))

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
