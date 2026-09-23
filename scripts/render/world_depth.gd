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
	_compute_skin()
	timings["depth_field"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_material()
	_build_mesh()
	_build_skin()
	_build_lip()
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
	if _skin_row[xi] >= 0 and d >= _skin_d0[xi] and not is_nan(skin_at(x, d)):
		return skin_at(x, d)
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
	if _skin_row[xi] >= 0 and d >= _skin_d0[xi] and not is_nan(skin_at(x, d)):
		var si := _skin_row[xi] * W + xi
		return terrain.mat_ids[si] if terrain.solid[si] else -1
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
		if _skin_row[x] >= 0 and not is_nan(skin_at(x + 0.5, E_FULL)):
			var sy := _skin_row[x]
			hs[x] = skin_at(x + 0.5, E_FULL)
			cs[x] = terrain.fgcol_img.get_pixel(x, sy) if terrain.solid[sy * W + x] else terrain.bgcol_img.get_pixel(x, sy)
			continue
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
	var dimg := Image.create_from_data(W, H, false, Image.FORMAT_RF, depth.to_byte_array())
	material.set_shader_parameter("depth_tex", ImageTexture.create_from_image(dimg))

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

# ---------------------------------------------------------------- foreground lip
const LIP_MARGIN := 16          # extends across the side margins too
const LIP_BAND := 5             # the lip top never sits higher than this many tiles above the bottom edge
const LIP_CLEAR := 2            # ... and stays this many tiles below the bottom mass's top (only solid behind it)

## The world's bottom edge comes TOWARD the camera: the bottom earth mass continues forward (z +0.5 .. +7)
## as a grassy ledge that rounds off into a cliff dropping away into the sky below the level. It only ever
## sits in front of solid tiles (LIP_CLEAR below the top of the bottom mass, widened over +-3 columns),
## so perspective can only push it further over solid rock, never over gameplay air.
func _build_lip() -> void:
	var btop := PackedInt32Array(); btop.resize(W)
	for x in W:
		var y := H - 1
		while y > 0 and terrain.solid[(y - 1) * W + x]:
			y -= 1
		btop[x] = y if terrain.solid[(H - 1) * W + x] else H
	var ln := FastNoiseLite.new()
	ln.seed = 777
	ln.frequency = 0.08
	var b := Bucket.new()
	var x0 := float(-LIP_MARGIN)
	var x1 := float(W + LIP_MARGIN)
	var step := 0.5
	var nx := int((x1 - x0) / step)
	var zs: Array[float] = [0.4, 1.2, 2.0, 2.8, 3.6, 4.4, 5.2, 6.0]
	var bottom := -float(H) - 7.0
	# per x sample: top height and lip reach
	var tops := PackedFloat32Array(); tops.resize(nx + 1)
	var reach := PackedFloat32Array(); reach.resize(nx + 1)
	for k in nx + 1:
		var x := x0 + k * step
		var worst := 0
		for dx in range(-3, 4):
			var cx := clampi(int(floor(x)) + dx, 0, W - 1)
			worst = maxi(worst, btop[cx])
		var yt := maxf(float(worst + LIP_CLEAR), float(H - LIP_BAND))
		tops[k] = -yt + ln.get_noise_2d(x * 3.0, 11.0) * 0.12
		reach[k] = 4.2 + 2.6 * (ln.get_noise_1d(x) * 0.5 + 0.5)
	for k in nx:
		var xa := x0 + k * step
		var xb := xa + step
		var colx := Vector2(clampf(xa + 0.25, 0.5, W - 0.5), H - 0.5)
		# top surface (x, z) with a rounded front edge
		var prof_a := _lip_profile(tops[k], reach[k], zs, ln, xa)
		var prof_b := _lip_profile(tops[k + 1], reach[k + 1], zs, ln, xb)
		for j in prof_a.size() - 1:
			_quad(b, [Vector3(xa, prof_a[j].y, prof_a[j].x), Vector3(xb, prof_b[j].y, prof_b[j].x),
				Vector3(xb, prof_b[j + 1].y, prof_b[j + 1].x), Vector3(xa, prof_a[j + 1].y, prof_a[j + 1].x)],
				Vector3(0, 1, 0.3), colx, 10.0)
		# cliff face dropping from the rounded edge into the sky, receding slightly as it falls
		var ea: Vector2 = prof_a[prof_a.size() - 1]
		var eb: Vector2 = prof_b[prof_b.size() - 1]
		var rows := 6
		for r in rows:
			var ta := float(r) / rows
			var tb := float(r + 1) / rows
			var ya0 := lerpf(ea.y, bottom, ta)
			var ya1 := lerpf(ea.y, bottom, tb)
			var yb0 := lerpf(eb.y, bottom, ta)
			var yb1 := lerpf(eb.y, bottom, tb)
			var za0 := ea.x - ta * ta * 2.5 + ln.get_noise_2d(xa * 2.0, ya0 * 1.5) * 0.35
			var za1 := ea.x - tb * tb * 2.5 + ln.get_noise_2d(xa * 2.0, ya1 * 1.5) * 0.35
			var zb0 := eb.x - ta * ta * 2.5 + ln.get_noise_2d(xb * 2.0, yb0 * 1.5) * 0.35
			var zb1 := eb.x - tb * tb * 2.5 + ln.get_noise_2d(xb * 2.0, yb1 * 1.5) * 0.35
			_quad(b, [Vector3(xa, ya0, za0), Vector3(xb, yb0, zb0), Vector3(xb, yb1, zb1), Vector3(xa, ya1, za1)],
				Vector3(0, 0, 1), colx, 11.0)
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
	mi.name = "Lip"
	add_child(mi)

## (z, y) points of the lip top from the slab front to the rounded edge.
func _lip_profile(top: float, reach: float, zs: Array[float], ln: FastNoiseLite, x: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var r := 1.3
	for k in zs.size():
		var z := lerpf(zs[0], reach - r, float(k) / (zs.size() - 1))   # same vertex count for every column
		out.append(Vector2(z, top - 0.05 * z + ln.get_noise_2d(x * 1.3, z * 1.3) * 0.12))
	var base: Vector2 = out[out.size() - 1]
	for q in range(1, 6):
		var a := float(q) / 5.0 * PI * 0.5
		var zz := (reach - r) + sin(a) * r
		out.append(Vector2(zz, base.y - (1.0 - cos(a)) * r))
	return out

func _quad(b: Bucket, p: Array, out: Vector3, uv: Vector2, kind: float) -> void:
	var nrm: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
	if nrm.length_squared() < 1e-12:
		return
	nrm = nrm.normalized()
	if nrm.dot(out) > 0.0:
		p = [p[0], p[3], p[2], p[1]]
	else:
		nrm = -nrm
	for j in [0, 1, 2, 0, 2, 3]:
		b.v.append(p[j])
		b.n.append(nrm)
		b.uv.append(uv)
		b.uv2.append(Vector2(1.0, kind))

# ---------------------------------------------------------------- smooth skin over the far ground
const SKIN_D0 := 4.0            # ground: the first tiles behind the slab stay tile-matched to the silhouette
const SKIN_ERO := 3             # samples (0.5 tile) of the x erosion: rounds steps, never rises above them
const SKIN_BLUR := 4            # samples of the x blur
const SKIN_DS := [1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.5, 11.0, 12.5, 14.0, 16.0, 18.5, 21.0, 23.0, 24.8]
var _skin_row := PackedInt32Array()   # per column: top row of the natural run under the skin (-1 none)
var _skin_d0 := PackedFloat32Array()  # per column: depth where the skin takes over from the voxels
var _skin := PackedFloat32Array()     # (2W+1) x SKIN_DS.size() heights (world y), NAN = none
var _skin_nx := 0

## Natural masses (earth, grass, foliage, stone, crag... and the ground bodies) get one smooth heightfield
## skin over their topmost run: the stepped depth profile (the top of the highest tile reaching each depth)
## is eroded + blurred along x and blurred along the depth, so peaks become rounded mountains and lawns
## rolling hillsides; ruins keep their masonry blocks. The first d0 tiles stay tile-matched to the silhouette
## (4 for ground, less for small masses). The skin never rises above the stepped profile (so never above the
## front silhouette), never sinks below the run it covers, and the voxel tiles under it are clipped to it.
func _compute_skin() -> void:
	var nd: int = SKIN_DS.size()
	_skin_row.resize(W)
	_skin_row.fill(-1)
	_skin_d0.resize(W)
	var run_bot := PackedInt32Array(); run_bot.resize(W)
	for x in W:
		for y in H:
			var i := y * W + x
			if depth[i] <= 0.0:
				continue
			if terrain.solid[i] and not _natural(terrain.mat_ids[i]):
				break   # masonry on top: the column keeps its blocks
			var yb := y
			while yb + 1 < H:
				var j := (yb + 1) * W + x
				if depth[j] <= 0.0 or (terrain.solid[j] and not _natural(terrain.mat_ids[j])):
					break
				yb += 1
			_skin_row[x] = y
			run_bot[x] = yb
			var e_top := depth[i]
			_skin_d0[x] = SKIN_D0 if e_top >= E_FULL - 0.01 else clampf(0.4 * e_top, 1.0, SKIN_D0)
			break
	# stepped profile per column and depth
	var raw := PackedFloat32Array(); raw.resize(W * nd)
	for x in W:
		for j in nd:
			raw[x * nd + j] = NAN
		if _skin_row[x] < 0:
			continue
		for j in nd:
			var d: float = SKIN_DS[j]
			for y in range(_skin_row[x], run_bot[x] + 1):
				if depth[y * W + x] >= d - 0.001:
					raw[x * nd + j] = -float(y)
					break
	_skin_nx = 2 * W + 1
	var prof := PackedFloat32Array(); prof.resize(_skin_nx * nd)
	var floor_y := PackedFloat32Array(); floor_y.resize(_skin_nx)
	var d0s := PackedFloat32Array(); d0s.resize(_skin_nx)
	for k in _skin_nx:
		var cols: Array = [k / 2 - 1, k / 2] if k % 2 == 0 else [k / 2]
		floor_y[k] = NAN
		d0s[k] = SKIN_D0
		for j in nd:
			var best := NAN
			for c in cols:
				if c < 0 or c >= W:
					continue
				var v := raw[c * nd + j]
				if not is_nan(v) and (is_nan(best) or v > best):
					best = v
					if j == 0:
						floor_y[k] = -float(run_bot[c])
						d0s[k] = _skin_d0[c]
			prof[k * nd + j] = best
	# erode + blur along x (valid samples only), then blur along the depth
	var ero := PackedFloat32Array(); ero.resize(_skin_nx * nd)
	for j in nd:
		for k in _skin_nx:
			var v := prof[k * nd + j]
			if is_nan(v):
				ero[k * nd + j] = NAN
				continue
			for q in range(maxi(0, k - SKIN_ERO), mini(_skin_nx, k + SKIN_ERO + 1)):
				var u := prof[q * nd + j]
				if not is_nan(u):
					v = minf(v, u)
			ero[k * nd + j] = v
	var smx := PackedFloat32Array(); smx.resize(_skin_nx * nd)
	for j in nd:
		for k in _skin_nx:
			if is_nan(ero[k * nd + j]):
				smx[k * nd + j] = NAN
				continue
			var sum := 0.0
			var cnt := 0
			for q in range(maxi(0, k - SKIN_BLUR), mini(_skin_nx, k + SKIN_BLUR + 1)):
				var u := ero[q * nd + j]
				if not is_nan(u):
					sum += u
					cnt += 1
			smx[k * nd + j] = sum / cnt
	_skin.resize(_skin_nx * nd)
	for k in _skin_nx:
		for j in nd:
			var v := smx[k * nd + j]
			if is_nan(v):
				_skin[k * nd + j] = NAN
				continue
			var sum := v * 2.0
			var cnt := 2.0
			for dj in [-1, 1]:
				var jj: int = j + dj
				if jj >= 0 and jj < nd and not is_nan(smx[k * nd + jj]):
					sum += smx[k * nd + jj]
					cnt += 1.0
			var smooth := minf(sum / cnt, prof[k * nd + j])
			var d: float = SKIN_DS[j]
			var w := smoothstep(d0s[k], d0s[k] + 4.0, d)
			var h := lerpf(prof[k * nd + j], smooth, w) + dy_at(k * 0.5, d)
			if not is_nan(floor_y[k]):
				h = maxf(h, floor_y[k] + 0.5)
			_skin[k * nd + j] = h
	# clip the natural voxels to the skin: each tile ends where the skin first passes below its top
	for x in W:
		if _skin_row[x] < 0:
			continue
		for y in range(_skin_row[x], run_bot[x] + 1):
			var i := y * W + x
			if y == _skin_row[x]:
				depth[i] = minf(depth[i], _skin_d0[x])
				continue
			var top := -float(y)
			var cut := depth[i]
			for j in nd:
				var dj: float = SKIN_DS[j]
				if dj < _skin_d0[x] or dj > depth[i]:
					continue
				if _skin_min(x, j) < top - 0.02:
					cut = maxf(_skin_d0[x], SKIN_DS[maxi(j - 1, 0)])
					break
			depth[i] = minf(depth[i], cut)
	# records follow the clipped depths
	for x in W:
		var rec := []
		var best := 0.0
		for y in H:
			var e := depth[y * W + x]
			if e > best + 0.001:
				rec.append([y, e])
				best = e
		_records[x] = rec

func _skin_min(x: int, j: int) -> float:
	var nd: int = SKIN_DS.size()
	var m := INF
	for k in [2 * x, 2 * x + 1, 2 * x + 2]:
		var v := _skin[k * nd + j]
		if not is_nan(v):
			m = minf(m, v)
	return m

## Skin height at world x and depth d (bilinear over the sample grid).
func skin_at(x: float, d: float) -> float:
	var nd: int = SKIN_DS.size()
	var kf := clampf(x * 2.0, 0.0, _skin_nx - 1.001)
	var k := int(kf)
	var fx := kf - k
	var j := 0
	while j < nd - 2 and SKIN_DS[j + 1] < d:
		j += 1
	var fz := clampf((d - SKIN_DS[j]) / (SKIN_DS[j + 1] - SKIN_DS[j]), 0.0, 1.0)
	var a := _skin[k * nd + j]
	var b := _skin[(k + 1) * nd + j]
	var c := _skin[k * nd + j + 1]
	var e := _skin[(k + 1) * nd + j + 1]
	if is_nan(b): b = a
	if is_nan(a): a = b
	if is_nan(e): e = c
	if is_nan(c): c = e
	return lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fz)

func _build_skin() -> void:
	var nd: int = SKIN_DS.size()
	var b := Bucket.new()
	for k in _skin_nx - 1:
		for j in nd - 1:
			var h00 := _skin[k * nd + j]
			var h10 := _skin[(k + 1) * nd + j]
			var h01 := _skin[k * nd + j + 1]
			var h11 := _skin[(k + 1) * nd + j + 1]
			if is_nan(h00) or is_nan(h10) or is_nan(h01) or is_nan(h11):
				continue
			var xa := k * 0.5
			var xb := xa + 0.5
			var za: float = Z_FRONT - SKIN_DS[j]
			var zb: float = Z_FRONT - SKIN_DS[j + 1]
			var col := clampi(int(xa + 0.25), 0, W - 1)
			if _skin_row[col] < 0 or SKIN_DS[j] < _skin_d0[col] - 0.01:
				continue   # the voxels are the surface in front of d0
			var uv := Vector2(col + 0.5, _skin_row[col] + 0.5)
			var p := [Vector3(xa, h00, za), Vector3(xb, h10, za), Vector3(xb, h11, zb), Vector3(xa, h01, zb)]
			var ns := [_skin_normal(k, j), _skin_normal(k + 1, j), _skin_normal(k + 1, j + 1), _skin_normal(k, j + 1)]
			# winding: Godot front faces are clockwise seen from outside (above)
			var order := [0, 2, 1, 0, 3, 2]
			var fn: Vector3 = ((p[2] as Vector3) - (p[0] as Vector3)).cross((p[1] as Vector3) - (p[0] as Vector3))
			if fn.y > 0.0:
				order = [0, 1, 2, 0, 2, 3]
			for q in order:
				b.v.append(p[q])
				b.n.append(ns[q])
				b.uv.append(uv)
				b.uv2.append(Vector2(1.0, 12.0))
	if b.v.is_empty():
		return
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
	mi.name = "Skin"
	add_child(mi)

func _skin_normal(k: int, j: int) -> Vector3:
	var nd: int = SKIN_DS.size()
	var h := _skin[k * nd + j]
	var hl := _skin[maxi(k - 1, 0) * nd + j]
	var hr := _skin[mini(k + 1, _skin_nx - 1) * nd + j]
	var hb := _skin[k * nd + maxi(j - 1, 0)]
	var hf := _skin[k * nd + mini(j + 1, nd - 1)]
	if is_nan(hl): hl = h
	if is_nan(hr): hr = h
	if is_nan(hb): hb = h
	if is_nan(hf): hf = h
	var dx := (hr - hl) / 1.0
	var dzs: float = SKIN_DS[mini(j + 1, nd - 1)] - SKIN_DS[maxi(j - 1, 0)]
	# d grows toward -z, so dh/dz = -(hf - hb) / dzs
	var dz := -(hf - hb) / maxf(dzs, 0.01)
	return Vector3(-dx, 1.0, -dz).normalized()
