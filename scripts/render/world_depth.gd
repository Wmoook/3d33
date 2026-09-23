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
const SEAM_D := 0.0            # side faces against a neighbouring mass begin this deep (overlapping the slab cliff)
const E_FULL := 24.8           # ground bodies end at z = -26.0
const STRUCT_CAP := 11.0
const GROUND_RW := 48          # horizontal run (tiles) that makes a mass a ground body
const GROUND_VT := 10          # ... and its vertical run
const CHUNK := 32
const BREAKS := [12.0, 14.0, 16.0, 18.5, 21.0, 23.0]   # depth subdivisions where the far shear acts
const HAZE_Z0 := -8.0            # near faces never haze (they are solid blocks); aerial haze only far back
const HAZE_Z1 := -30.0

var W := 0
var H := 0
var terrain: WorldTerrain
var mass := PackedByteArray()
var depth := PackedFloat32Array()   # E per tile (0 = no volume)
var material: ShaderMaterial
var timings := {}
var face_count := 0
var _noise := FastNoiseLite.new()
## Optional smooth heightfield skin over natural masses (rounded hills/peaks). DEFAULT OFF: the user prefers
## the blocky extrusion. Set before build().
var smooth_skin := false
## Tests: skip the window glass / shaft meshes (to check the openings are real holes).
static var debug_no_glass := false
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
	_skin_row.resize(W)
	_skin_row.fill(-1)
	_skin_d0.resize(W)
	_skin_d0.fill(SKIN_D0)
	if smooth_skin:
		_compute_skin()
	timings["depth_field"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_material()
	_build_mesh()
	_build_room_extras()
	if smooth_skin:
		_build_skin()
	terrain.material.set_shader_parameter("depth_cont", 1.0)
	timings["depth_mesh"] = Time.get_ticks_msec() - t0

# ---------------------------------------------------------------- depth field
func _compute_depth() -> void:
	var n := W * H
	mass.resize(n)
	depth.resize(n)
	var hollow := WorldForest.hollow_mask(terrain)
	for i in n:
		if hollow.size() == n and hollow[i] and not terrain.solid[i] and (terrain.wall_code.size() != n or terrain.wall_code[i] < 5):
			mass[i] = 0   # forest hollow: WorldForest fills the space behind
			continue
		mass[i] = 1 if (terrain.solid[i] or (terrain.backwall[i] and not terrain.window[i]) or terrain.pocket[i] == 1) else 0   # windows: holes through the volume (jambs)
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
	_make_rooms()
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
		var si: int = _skin_row[xi] * W + xi
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
			var sy: int = _skin_row[x]
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
	material.set_shader_parameter("forest_tex", ImageTexture.create_from_image(WorldForest.hollow_image(terrain)))
	var rg := PackedFloat32Array(); rg.resize(W * H * 2)
	for i in W * H:
		rg[i * 2] = depth[i]
		rg[i * 2 + 1] = _cover(i).x if mass[i] else 99.0   # where the tile's volume starts
	var dimg := Image.create_from_data(W, H, false, Image.FORMAT_RGF, rg.to_byte_array())
	material.set_shader_parameter("depth_tex", ImageTexture.create_from_image(dimg))

func _cover(i: int) -> Vector2:
	# depth interval [d0, d1] covered by tile i (d = Z_FRONT - z)
	if not mass[i]:
		return Vector2(-1.0, -1.0)
	if room.size() == W * H and room[i] != 0:
		return Vector2(room_r[i], depth[i])
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
	_build_room_backs(buckets)
	_build_cave_props(buckets)
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
	var lo := maxf(c.x, SEAM_D)   # starts inside the slab's cliff: overlap, no hairline seam
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

# ---------------------------------------------------------------- smooth skin (optional, default OFF)
const SKIN_D0 := 1.5            # voxels in front of this; the skin eases from the stepped profile to smooth by d0+4
const SKIN_ERO := 1             # samples (0.5 tile) of the x erosion: rounds steps, never rises above them
const SKIN_BLUR := 2            # samples of the x blur
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
			_skin_d0[x] = minf(SKIN_D0, e_top)
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
			# boundary samples: the mean of both columns (a one-tile slope instead of a spike)
			var sum := 0.0
			var cnt := 0
			for c in cols:
				if c < 0 or c >= W:
					continue
				var v := raw[c * nd + j]
				if not is_nan(v):
					sum += v
					cnt += 1
					if j == 0:
						floor_y[k] = -float(run_bot[c]) if is_nan(floor_y[k]) else minf(floor_y[k], -float(run_bot[c]))
						d0s[k] = _skin_d0[c]
			prof[k * nd + j] = sum / cnt if cnt > 0 else NAN
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

# ---------------------------------------------------------------- interior rooms (2.5D)
const ROOM_R_MIN := 3.0
const ROOM_R_MAX := 6.0
const ROOM_WALL := 1.2          # thickness of a room's back wall block
const RWIN_PITCH := 7           # rhythmic windows: one bay every this many columns ...
const RWIN_ROWS := 11           # ... and one storey every this many rows
var room := PackedInt32Array()      # per tile: room id + 1 (0 = not a room tile)
var room_r := PackedFloat32Array()
var room_earth := PackedByteArray()   # per tile: 1 = earth cave (dirt back wall, no windows)  # per tile: the room's back-wall depth (d)
var win := PackedByteArray()        # per tile: 1 = window opening (painted sky window or a rhythmic one)
var windows: Array = []             # [{rect: Rect2i, r: float, stained: bool}]

## Structure interiors (terrain.wall_code >= 5: stone walls + windows) become recessed ROOM BOXES: the back
## wall sits ROOM_R_MIN..MAX behind the gameplay front (bigger rooms deeper), the surrounding solids are
## extruded at least as deep so they form the receding side walls, floor and ceiling. Windows are holes in
## the back wall (glass pane + light shaft added by _build_room_extras); big blank walls of above-ground
## rooms get rhythmic lancet windows.
func _make_rooms() -> void:
	var n := W * H
	room.resize(n); room.fill(0)
	room_r.resize(n); room_r.fill(0.0)
	room_earth.resize(n); room_earth.fill(0)
	win.resize(n); win.fill(0)
	var code: PackedByteArray = terrain.wall_code
	if code.size() != n:
		return
	# stone interiors (code >= 5, win over forest hollows) and earth tunnels (code 2, not inside a forest
	# hollow) are both recessed rooms; one component spans both so neighbouring earth / stone share R
	var hol := WorldForest.hollow_mask(terrain)
	var is_room := func(i: int) -> bool:
		if terrain.solid[i]:
			return false
		if code[i] >= 5:
			return true
		return code[i] == 2 and not (hol.size() == n and hol[i] == 1)
	var rid := 0
	for start in n:
		if room[start] or not is_room.call(start):
			continue
		rid += 1
		var comp := PackedInt32Array([start])
		room[start] = rid
		var qi := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if room[j] == 0 and is_room.call(j):
					room[j] = rid
					comp.append(j)
		var r := clampf(2.4 + sqrt(float(comp.size())) * 0.12, ROOM_R_MIN, ROOM_R_MAX)
		var ag := _above_ground(comp)
		for i in comp:
			room_r[i] = r
			room_earth[i] = 1 if code[i] < 5 else 0
			if code[i] >= 20 and ag:
				win[i] = 1   # painted sky in a structure: a window only where the room can see out
		if comp.size() >= 80 and ag:
			_rhythm_windows(comp, rid)
	_drop_tiny_windows()
	# depths: room tiles cover [R, R + wall]; windows are holes; neighbouring solids reach past the back wall
	for i in n:
		if room[i] == 0:
			continue
		var r := room_r[i]
		if win[i]:
			mass[i] = 0
			depth[i] = 0.0
		else:
			mass[i] = 1
			depth[i] = r + ROOM_WALL   # exactly the back-wall slab: window reveals are 1.2 deep, the view goes out
		var x := i % W
		var y := i / W
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if room[j] == 0 and (terrain.solid[j] or mass[j]):
					depth[j] = maxf(depth[j], r + ROOM_WALL)   # every neighbouring mass closes the room's sides
	# window list for glass panes / shafts (one per connected window patch)
	var seen := PackedByteArray(); seen.resize(n)
	for start in n:
		if seen[start] or not win[start]:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var rect := Rect2i(start % W, start / W, 1, 1)
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			rect = rect.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if win[j] and not seen[j]:
					seen[j] = 1
					comp.append(j)
		windows.append({"tiles": comp, "rect": rect, "r": room_r[start], "stained": (rect.position.x * 7 + rect.position.y * 3) % 4 == 0,
			"frost": win[start] == 2})

## Painted window patches smaller than 2 x 2 (a stray sky speck in a hall's painting) read as a black slot
## with a glowing pane, not a window: they stay plain wall.
func _drop_tiny_windows() -> void:
	var n := W * H
	var seen := PackedByteArray(); seen.resize(n)
	var dropped := 0
	for start in n:
		if seen[start] or win[start] != 1:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var rect := Rect2i(start % W, start / W, 1, 1)
		var qi := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			rect = rect.expand(Vector2i(x + 1, y + 1))
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if win[j] == 1 and not seen[j]:
					seen[j] = 1
					comp.append(j)
		if rect.size.x < 2 or rect.size.y < 2:
			dropped += 1
			for i in comp:
				win[i] = 0
	timings["tiny_windows_dropped"] = dropped

## Earth caves recede visibly: roots hang from the ceiling at several depths and pebbles / small rocks lie on
## the floor going back (kind 14 = root, 15 = rock; closed boxes, never in front of the slab).
func _build_cave_props(buckets: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	for y in range(1, H - 1):
		for x in W:
			var i := y * W + x
			if room[i] == 0 or room_earth[i] == 0 or win[i]:
				continue
			var r := room_r[i]
			var key := Vector2i(x / CHUNK, y / CHUNK)
			if not buckets.has(key):
				buckets[key] = Bucket.new()
			var b: Bucket = buckets[key]
			if terrain.solid[i - W]:
				for k in 2:
					if rng.randf() > 0.55:
						continue
					var d := rng.randf_range(0.6, r - 0.3)
					var cx := x + rng.randf_range(0.15, 0.85)
					var len := rng.randf_range(0.35, 1.3)
					var w := rng.randf_range(0.04, 0.09)
					_prop_box(b, cx - w, cx + w, -float(y), -float(y) - len, Z_FRONT - d + w, Z_FRONT - d - w, Vector2(x + 0.5, y - 0.5), 14.0)
			if terrain.solid[i + W] and rng.randf() < 0.5:
				var d := rng.randf_range(0.5, r - 0.3)
				var cx := x + rng.randf_range(0.2, 0.8)
				var s := rng.randf_range(0.08, 0.22)
				_prop_box(b, cx - s, cx + s, -float(y) - 1.0 + s * 1.2, -float(y) - 1.0, Z_FRONT - d + s, Z_FRONT - d - s, Vector2(x + 0.5, y + 1.5), 15.0)

func _prop_box(b: Bucket, xa: float, xb: float, ya: float, yb: float, za: float, zb: float, uv: Vector2, kind: float) -> void:
	var c := [Vector3(xa, yb, zb), Vector3(xb, yb, zb), Vector3(xb, ya, zb), Vector3(xa, ya, zb),
		Vector3(xa, yb, za), Vector3(xb, yb, za), Vector3(xb, ya, za), Vector3(xa, ya, za)]
	var faces := [[[4, 5, 6, 7], Vector3(0, 0, 1)], [[0, 4, 7, 3], Vector3(-1, 0, 0)], [[5, 1, 2, 6], Vector3(1, 0, 0)],
		[[0, 1, 5, 4], Vector3(0, -1, 0)], [[3, 7, 6, 2], Vector3(0, 1, 0)]]
	for f in faces:
		var idx: Array = f[0]
		var out: Vector3 = f[1]
		var p := [c[idx[0]], c[idx[1]], c[idx[2]], c[idx[3]]]
		for j in [0, 1, 2, 0, 2, 3]:
			b.v.append(p[j])
			b.n.append(out)
			b.uv.append(uv)
			b.uv2.append(Vector2(1.0, kind))

func _touches_room(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < W and ny < H and room[ny * W + nx] != 0:
				return true
	return false

func _hollow(i: int) -> bool:
	var h := WorldForest.hollow_mask(terrain)
	return h.size() == W * H and h[i] == 1

## A room above the ground line (open sky within 10 tiles above or beside it) may look out through windows;
## underground trial halls don't.
func _above_ground(comp: PackedInt32Array) -> bool:
	for i in comp:
		var x := i % W
		var y := i / W
		for d in range(1, 11):
			for p in [Vector2i(x, y - d), Vector2i(x - d, y), Vector2i(x + d, y)]:
				if p.x >= 0 and p.y >= 0 and p.x < W and p.y < H and terrain.sky[p.y * W + p.x] and not terrain.solid[p.y * W + p.x]:
					return true
	return false

## Lancet windows 2 wide x 4 tall in a rhythm on big blank back walls: only where the whole 4 x 6 block
## around them is plain back wall of this room (never under a glyph-dense painted feature).
func _rhythm_windows(comp: PackedInt32Array, rid: int) -> void:
	var x0 := W
	var y0 := H
	for i in comp:
		x0 = mini(x0, i % W)
		y0 = mini(y0, i / W)
	for i in comp:
		var x := i % W
		var y := i / W
		if (x - x0) % RWIN_PITCH != 2 or (y - y0) % RWIN_ROWS != 2:
			continue
		var ok := true
		for dy in range(-1, 5):
			for dx in range(-1, 3):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					ok = false
					break
				var j := ny * W + nx
				if room[j] != rid or terrain.wall_code[j] >= 20 or terrain.wall_code[j] < 5 or WorldPalette.is_world_solid(terrain.level.fg[j]) or WorldPalette.is_key_door(terrain.level.fg[j]):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		for dy in 4:
			for dx in 2:
				win[(y + dy) * W + x + dx] = 2   # rhythmic lancet (frosted glass: may sit behind glyphs)

## +z faces of the room back walls (kind 4) at d = R, plus an opaque front cap (kind 5, just behind the slab)
## on every solid tile touching a room: the slab's rounded corners otherwise open slits onto what lies behind.
func _build_room_backs(buckets: Dictionary) -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			if room[i] == 0 and terrain.solid[i] and _touches_room(x, y):
				var kc := Vector2i(x / CHUNK, y / CHUNK)
				if not buckets.has(kc):
					buckets[kc] = Bucket.new()
				var bc: Bucket = buckets[kc]
				var zc := Z_FRONT - 0.02
				var pc := [Vector3(x, -y, zc), Vector3(x + 1, -y, zc), Vector3(x + 1, -y - 1, zc), Vector3(x, -y - 1, zc)]
				for j in [0, 1, 2, 0, 2, 3]:
					bc.v.append(pc[j])
					bc.n.append(Vector3(0, 0, 1))
					bc.uv.append(Vector2(x + 0.5, y + 0.5))
					bc.uv2.append(Vector2(1.0, 5.0))
				continue
			if room[i] == 0 or win[i]:
				continue
			var key := Vector2i(x / CHUNK, y / CHUNK)
			if not buckets.has(key):
				buckets[key] = Bucket.new()
			var b: Bucket = buckets[key]
			var z := Z_FRONT - room_r[i]
			var p := [Vector3(x, -y, z), Vector3(x + 1, -y, z), Vector3(x + 1, -y - 1, z), Vector3(x, -y - 1, z)]
			for j in [0, 1, 2, 0, 2, 3]:
				b.v.append(p[j])
				b.n.append(Vector3(0, 0, 1))
				b.uv.append(Vector2(x + 0.5, y + 0.5))
				b.uv2.append(Vector2(float(room_earth[i]), 4.0))   # x = 1: earth cave back wall

## Glass panes in every window opening + one soft light shaft per window falling into the room.
func _build_room_extras() -> void:
	if windows.is_empty() or debug_no_glass:
		return
	var gb := Bucket.new()
	var sb := Bucket.new()
	for w in windows:
		var r: float = w["r"]
		var z := Z_FRONT - r - 0.35
		var st := 1.0 if w["stained"] else 0.0
		var fr := 1.0 if w["frost"] else 0.0
		for i in (w["tiles"] as PackedInt32Array):
			var x := i % W
			var y := i / W
			var p := [Vector3(x, -y, z), Vector3(x + 1, -y, z), Vector3(x + 1, -y - 1, z), Vector3(x, -y - 1, z)]
			for j in [0, 1, 2, 0, 2, 3]:
				gb.v.append(p[j])
				gb.n.append(Vector3(0, 0, 1))
				gb.uv.append(Vector2(x, y))
				gb.uv2.append(Vector2(st, fr))
		var rect: Rect2i = w["rect"]
		var cx := rect.position.x + rect.size.x * 0.5
		var top := -float(rect.position.y) - 0.5
		var ww := clampf(float(rect.size.x), 1.2, 4.0)
		var len := minf(10.0, 3.0 + rect.size.y * 1.5)
		var dir := Vector3(0.45, -1.0, 0.0).normalized()
		var a := Vector3(cx, top, z + 0.1)
		var bpt := a + dir * len + Vector3(0, 0, r - 0.9)   # the shaft comes forward into the room
		var side := Vector3(ww * 0.5, 0, 0)
		var q := [a - side, a + side, bpt + side * 1.6, bpt - side * 1.6]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for j in [0, 1, 2, 0, 2, 3]:
			sb.v.append(q[j])
			sb.n.append(Vector3(0, 0, 1))
			sb.uv.append(uvs[j])
			sb.uv2.append(Vector2(st, 0))
	_add_mesh(gb, "WindowGlass", "res://shaders/world/window_glass.gdshader")
	_add_mesh(sb, "WindowShafts", "res://shaders/world/window_shaft.gdshader")

func _add_mesh(b: Bucket, nm: String, shader: String) -> void:
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
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = nm
	add_child(mi)
