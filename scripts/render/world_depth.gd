class_name WorldDepth
extends Node3D
## Depth continuation (day levels): the level's own masses continue BACKWARD as real 3D volume behind the
## gameplay slab, so a hilltop reads as a hillside rolling away and a spire as a tower with sides, not a
## painted cutout. Every mass tile (solid, back wall, pocket) is extruded from behind the slab (z -1.2, or
## -2.0 for back-wall tiles so nothing pokes in front of a recess) to a per-tile depth E:
##   - ground bodies (wide + tall natural masses): all the way to z = -26 (sky's WorldVista picks up there)
##   - everything else (spires, ruins, islands, letters): about its width, capped at STRUCT_CAP tiles
## Only faces that border a shallower neighbour are built (tops, sides, undersides), tile-exact, so the
## volumes are closed from every angle the camera can reach. Far ground (d > 12) rolls and sinks gently
## (a continuous downward shear, so the mesh stays watertight and never rises into gameplay air).
## Non-colliding decor: everything lies strictly behind z = -1.2.
## API for decoration / the vista seam: depth_top_y(), depth_mat(), depth_seam().

const Z_FRONT := -1.2          # solid tiles start here (inside the slab's cliff, which reaches ~-2.3)
const Z_FRONT_BG := -2.0       # back-wall / pocket tiles start behind the recess (-1.9)
const E_FULL := 24.8           # ground bodies end at z = -26.0
const STRUCT_CAP := 11.0
const GROUND_RW := 48          # horizontal run (tiles) that makes a mass a ground body
const GROUND_VT := 10          # ... and its vertical run
const CHUNK := 32
const BREAKS := [12.0, 14.0, 16.0, 18.5, 21.0, 23.0]   # depth subdivisions where the far shear acts
const HAZE_Z0 := -2.0
const HAZE_Z1 := -26.0

var W := 0
var H := 0
var terrain: WorldTerrain
var mass := PackedByteArray()
var depth := PackedFloat32Array()   # E per tile (0 = no volume)
var material: ShaderMaterial
var timings := {}
var face_count := 0
var _noise := FastNoiseLite.new()
var _records := []                  # per column: [[y, E], ...] with increasing E, top to bottom

class Bucket:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

static func _natural(m: int) -> bool:
	return m == WorldPalette.M_EARTH or m == WorldPalette.M_GRASS or m == WorldPalette.M_FOLIAGE \
		or m == WorldPalette.M_STONE or m == WorldPalette.M_CRAG or m == WorldPalette.M_SAND \
		or m == WorldPalette.M_SNOW

func build(t: WorldTerrain) -> void:
	terrain = t
	W = t.W
	H = t.H
	_noise.seed = 5151
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.045
	_noise.fractal_octaves = 2
	var t0 := Time.get_ticks_msec()
	_compute_depth()
	timings["depth_field"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_material()
	_build_mesh()
	terrain.material.set_shader_parameter("depth_cont", 1.0)
	timings["depth_mesh"] = Time.get_ticks_msec() - t0

# ---------------------------------------------------------------- depth field
func _compute_depth() -> void:
	var n := W * H
	mass.resize(n)
	depth.resize(n)
	for i in n:
		mass[i] = 1 if (terrain.solid[i] or terrain.backwall[i] or terrain.pocket[i] == 1) else 0
	var rw := PackedInt32Array(); rw.resize(n)
	var vt := PackedInt32Array(); vt.resize(n)
	for y in H:
		var x := 0
		while x < W:
			if not mass[y * W + x]:
				x += 1
				continue
			var x1 := x
			while x1 < W and mass[y * W + x1]:
				x1 += 1
			for k in range(x, x1):
				rw[y * W + k] = x1 - x
			x = x1
	for x in W:
		var y := 0
		while y < H:
			if not mass[y * W + x]:
				y += 1
				continue
			var y1 := y
			while y1 < H and mass[y1 * W + x]:
				y1 += 1
			for k in range(y, y1):
				vt[k * W + x] = y1 - y
			y = y1
	var scroll := WorldPalette.FV_RECT_SCROLL
	for y in H:
		for x in W:
			var i := y * W + x
			if not mass[i]:
				depth[i] = 0.0
				continue
			var e := clampf(minf(0.8 * rw[i], 2.0 + 1.2 * vt[i]), 1.0, STRUCT_CAP)
			if rw[i] >= GROUND_RW and vt[i] >= GROUND_VT and (not terrain.solid[i] or _natural(terrain.mat_ids[i])):
				e = E_FULL
			if scroll.has_point(Vector2i(x, y)):
				e = 0.8   # the hanging parchment stays a thin sheet
			depth[i] = e
	# records per column for depth_top_y: the topmost tile reaching a given depth
	_records.resize(W)
	for x in W:
		var rec := []
		var best := 0.0
		for y in H:
			var e := depth[y * W + x]
			if e > best + 0.001:
				rec.append([y, e])
				best = e
		_records[x] = rec

## Downward shear of the far ground (<= 0 everywhere: nothing ever rises above its front silhouette).
func dy_at(x: float, d: float) -> float:
	var r := smoothstep(12.0, E_FULL, d)
	if r <= 0.0:
		return 0.0
	var nv := _noise.get_noise_2d(x, d * 1.6) * 0.5 + 0.5
	return -r * (1.2 + 2.6 * nv)

# ---------------------------------------------------------------- API
## World y of the topmost extruded surface at world (x, z); NAN where there is none (or in front of it).
func depth_top_y(x: float, z: float) -> float:
	var xi := int(floor(x))
	if xi < 0 or xi >= W:
		return NAN
	var d := Z_FRONT - z
	if d < 0.0:
		return NAN
	for r in _records[xi]:
		if r[1] >= d:
			var y: int = r[0]
			if d < Z_FRONT - Z_FRONT_BG and not terrain.solid[y * W + xi]:
				continue
			return -float(y) + dy_at(x, d)
	return NAN

## WorldPalette material of that top (-1 = none / a back-wall tile).
func depth_mat(x: float, z: float) -> int:
	var xi := int(floor(x))
	if xi < 0 or xi >= W:
		return -1
	var d := Z_FRONT - z
	if d < 0.0:
		return -1
	for r in _records[xi]:
		if r[1] >= d:
			var i: int = r[0] * W + xi
			return terrain.mat_ids[i] if terrain.solid[i] else -1
	return -1

## The back edge of the ground bodies for sky's vista: {z, height (world y per column, NAN = none),
## color (the painted colour of that top tile, sRGB)}.
func depth_seam() -> Dictionary:
	var hs := PackedFloat32Array(); hs.resize(W)
	var cs := PackedColorArray(); cs.resize(W)
	for x in W:
		hs[x] = NAN
		cs[x] = Color(0, 0, 0, 0)
		for r in _records[x]:
			if r[1] >= E_FULL - 0.01:
				var y: int = r[0]
				hs[x] = -float(y) + dy_at(x + 0.5, E_FULL)
				cs[x] = terrain.fgcol_img.get_pixel(x, y) if terrain.solid[y * W + x] else terrain.bgcol_img.get_pixel(x, y)
				break
	return {"z": Z_FRONT - E_FULL, "height": hs, "color": cs}

# ---------------------------------------------------------------- mesh
func _make_material() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/world/depth_volume.gdshader")
	var tm := terrain.material
	for k in ["fgcol_tex", "bgcol_tex", "level_size", "detail_nrm2", "detail_hgt",
			"pbr_tex", "pbr_level", "pbr_strength", "pbr_canopy_tex", "pbr_level_size"]:
		material.set_shader_parameter(k, tm.get_shader_parameter(k))
	material.set_shader_parameter("haze_z", Vector2(HAZE_Z0, HAZE_Z1))

func _cover(i: int) -> Vector2:
	# depth interval [d0, d1] covered by tile i (d = Z_FRONT - z)
	if not mass[i]:
		return Vector2(-1.0, -1.0)
	return Vector2(0.0 if terrain.solid[i] else Z_FRONT - Z_FRONT_BG, depth[i])

func _build_mesh() -> void:
	var buckets := {}
	for y in H:
		for x in W:
			var i := y * W + x
			if not mass[i]:
				continue
			var c := _cover(i)
			var solid_t := terrain.solid[i] == 1
			for side in 4:
				var nx := x + (1 if side == 1 else (-1 if side == 0 else 0))
				var ny := y + (1 if side == 3 else (-1 if side == 2 else 0))
				var nc := Vector2(-1.0, -1.0)
				if nx >= 0 and ny >= 0 and nx < W and ny < H:
					nc = _cover(ny * W + nx)
				elif nx < 0 or nx >= W or ny >= H:
					continue   # the level border: the margin mass continues there
				for piece in _pieces(c, nc):
					_face(buckets, x, y, side, piece.x, piece.y, solid_t)
	for key in buckets:
		var b: Bucket = buckets[key]
		if b.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.v
		arr[Mesh.ARRAY_NORMAL] = b.n
		arr[Mesh.ARRAY_TEX_UV] = b.uv
		arr[Mesh.ARRAY_TEX_UV2] = b.uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Depth_%d_%d" % [key.x, key.y]
		add_child(mi)

## Parts of interval c not covered by the neighbour's interval nc. Against another mass tile, nothing in
## front of the recess depth is built (the slab's own cliff covers it).
func _pieces(c: Vector2, nc: Vector2) -> Array:
	var out := []
	if nc.y < 0.0:
		out.append(c)
		return out
	var lo := maxf(c.x, Z_FRONT - Z_FRONT_BG)
	if nc.x > lo:
		var e := minf(c.y, nc.x)
		if e > lo + 0.01:
			out.append(Vector2(lo, e))
	var s := maxf(lo, nc.y)
	if c.y > s + 0.01:
		out.append(Vector2(s, c.y))
	return out

func _face(buckets: Dictionary, x: int, y: int, side: int, d0: float, d1: float, solid_t: bool) -> void:
	var key := Vector2i(x / CHUNK, y / CHUNK)
	if not buckets.has(key):
		buckets[key] = Bucket.new()
	var b: Bucket = buckets[key]
	var cuts := [d0]
	for br in BREAKS:
		if br > d0 + 0.05 and br < d1 - 0.05:
			cuts.append(br)
	cuts.append(d1)
	var uv := Vector2(x + 0.5, y + 0.5)
	var uv2 := Vector2(1.0 if solid_t else 0.0, float(side))
	for k in cuts.size() - 1:
		var da: float = cuts[k]
		var db: float = cuts[k + 1]
		var za := Z_FRONT - da
		var zb := Z_FRONT - db
		var p: Array[Vector3] = []
		var out := Vector3.ZERO
		match side:
			0:   # -x
				p = [Vector3(x, -y, za), Vector3(x, -y - 1, za), Vector3(x, -y - 1, zb), Vector3(x, -y, zb)]
				out = Vector3(-1, 0, 0)
			1:   # +x
				p = [Vector3(x + 1, -y, za), Vector3(x + 1, -y - 1, za), Vector3(x + 1, -y - 1, zb), Vector3(x + 1, -y, zb)]
				out = Vector3(1, 0, 0)
			2:   # top
				p = [Vector3(x, -y, za), Vector3(x + 1, -y, za), Vector3(x + 1, -y, zb), Vector3(x, -y, zb)]
				out = Vector3(0, 1, 0)
			3:   # underside
				p = [Vector3(x, -y - 1, za), Vector3(x + 1, -y - 1, za), Vector3(x + 1, -y - 1, zb), Vector3(x, -y - 1, zb)]
				out = Vector3(0, -1, 0)
		for j in 4:
			p[j].y += dy_at(p[j].x, Z_FRONT - p[j].z)
		var nrm := (p[1] - p[0]).cross(p[2] - p[0])
		if nrm.length_squared() < 1e-10:
			nrm = (p[2] - p[0]).cross(p[3] - p[0])
		nrm = nrm.normalized()
		# Godot front faces are clockwise seen from outside: the cross product must point inward
		if nrm.dot(out) > 0.0:
			p = [p[0], p[3], p[2], p[1]]
		else:
			nrm = -nrm
		var tri := [0, 1, 2, 0, 2, 3]
		for j in tri:
			b.v.append(p[j])
			b.n.append(nrm)
			b.uv.append(uv)
			b.uv2.append(uv2)
		face_count += 1
