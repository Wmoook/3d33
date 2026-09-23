class_name WorldVoxelFore
extends Node3D
@warning_ignore_start("integer_division")
## WorldVoxel phase 2: a sparse FOREGROUND voxel band in front of the gameplay plane (z +1 .. +13), in the same
## block language as the landscape behind: mossy boulders, grassy block banks, tree trunks with leaf clumps and
## hanging vines, broken ruin pillars and arches. Darker, cooler and softer than the level (it frames the view).
##
## OCCLUSION-SAFE (hard rule): voxel_fore.gdshader casts the ray camera -> fragment onto the gameplay plane z = 0
## and DISCARDS the fragment unless that point lies inside the interior of static solid rock (the level's solid
## mask eroded by one tile, with key doors / gates / switch doors / one-ways / coin doors and every non-solid
## gameplay block counted as air), and never within BALL_R tiles of the ball. So a foreground piece can only
## ever be drawn over rock that the player never needs to see; everything gameplay-relevant stays visible.
## No shadows are cast (the sun shines from the camera side and would darken gameplay tiles).
## Built on WorldVoxel's worker thread (generate()), uploaded on the main thread (upload()).

const FX0 := -4
const FNX := 408
const FY0 := -204
const FNY := 208
const FZ0 := 1
const FNZ := 12
const BALL_R := 6.0             # fully clear radius around the ball (tiles); fades back in over BALL_FADE
const BALL_FADE := 3.0
const MARGIN := 0               # mask covers exactly the level; outside it counts as air

var W := 400
var H := 200
var vox := PackedByteArray()      # (k * FNY + j) * FNX + i ; block (i,j,k) spans x [FX0+i,+1], y [FY0+j,+1], z [FZ0+k,+1]
var mask := PackedByteArray()     # per tile (y down): 255 = foreground may cover this tile
var dist := PackedInt32Array()    # Chebyshev distance (tiles) to the nearest non-coverable tile
var material: ShaderMaterial
var piece_count := 0
var voxel_count := 0
var _arrays := []
var _cols := PackedColorArray()
var _last_focus_ms := -100000

## Main thread: the coverable mask from the static level (cheap).
func setup(terrain: WorldTerrain) -> void:
	W = terrain.W
	H = terrain.H
	var lvl := terrain.level
	var raw := PackedByteArray()
	raw.resize(W * H)
	for i in W * H:
		var id: int = lvl.fg[i]
		var ok: bool = terrain.solid[i] == 1 and terrain.art_door[i] == 0
		if WorldPalette.is_key_door(id) or id == 43 or (id >= 1001 and id <= 1499) or id == 87:
			ok = false   # dynamic doors / gates / one-ways / coin doors / the sky's stepping-stone birds
		raw[i] = 1 if ok else 0
	# erode by one tile: only the interior of masses, their edges always stay visible
	mask.resize(W * H)
	for y in H:
		for x in W:
			var v := 255
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H or raw[ny * W + nx] == 0:
						v = 0
			mask[y * W + x] = v
	# Chebyshev distance to the nearest non-coverable tile (two passes)
	dist.resize(W * H)
	for i in W * H:
		dist[i] = 0 if mask[i] == 0 else 9999
	for y in H:
		for x in W:
			var i := y * W + x
			if dist[i] == 0:
				continue
			var m := dist[i]
			if x > 0: m = mini(m, dist[i - 1] + 1)
			if y > 0: m = mini(m, dist[i - W] + 1)
			if x > 0 and y > 0: m = mini(m, dist[i - W - 1] + 1)
			if x < W - 1 and y > 0: m = mini(m, dist[i - W + 1] + 1)
			if x == 0 or y == 0 or x == W - 1: m = mini(m, 1)
			dist[i] = m
	for y in range(H - 1, -1, -1):
		for x in range(W - 1, -1, -1):
			var i := y * W + x
			if dist[i] == 0:
				continue
			var m := dist[i]
			if x < W - 1: m = mini(m, dist[i + 1] + 1)
			if y < H - 1: m = mini(m, dist[i + W] + 1)
			if x < W - 1 and y < H - 1: m = mini(m, dist[i + W + 1] + 1)
			if x > 0 and y < H - 1: m = mini(m, dist[i + W - 1] + 1)
			if y == H - 1: m = mini(m, 1)
			dist[i] = m

## Worker thread: framing layers + mesh arrays. cols: WorldVoxel block colours (linear), indexed by block id.
## Everything is GROUNDED on the level's own masses: for every vertical run of coverable rock in a tile column
##   - BANKS rise from the bottom of the run (its floor) to an organic, noise-driven top edge (layered: a near
##     dark bank z +1..+3 and a taller one behind it, boulders bulging out of both),
##   - HANGS drop from the top of the run (its ceiling) with jagged stalactite / root edges and vines,
##   - a few big TRUNKS span a whole tall run, flaring roots at the floor and a leaf canopy at the ceiling.
## Adjacent columns share the same noise, so the layers are continuous silhouettes, never isolated cubes.
func generate(cols: PackedColorArray) -> void:
	_cols = cols
	vox.resize(FNX * FNY * FNZ)
	vox.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var fn := FastNoiseLite.new()
	fn.seed = 313
	fn.frequency = 0.07
	fn.fractal_octaves = 3
	var trunk_x := -100
	for tx in W:
		var ty := 0
		while ty < H:
			if mask[ty * W + tx] == 0:
				ty += 1
				continue
			var a := ty
			while ty < H and mask[ty * W + tx] > 0:
				ty += 1
			var b := ty - 1
			var ln := b - a + 1
			if ln < 3:
				continue
			_column(tx, a, b, ln, fn, rng)
			if ln >= 12 and tx - trunk_x > 26 and rng.randf() < 0.3 and dist[((a + b) / 2) * W + tx] >= 2:
				trunk_x = tx
				_trunk(tx, a, b, rng)
	_boulders(rng, fn)
	_moss_tops(rng)
	_build_mesh()

## One tile column of one run: bank from the floor, hang from the ceiling (world block y = -tile - 1).
func _column(tx: int, a: int, b: int, ln: int, fn: FastNoiseLite, rng: RandomNumberGenerator) -> void:
	var x := float(tx)
	var nb := fn.get_noise_2d(x, 0.0)            # where banks grow (continuous along x)
	var nh := fn.get_noise_2d(x, 200.0)          # where hangs grow
	var jag := fn.get_noise_2d(x * 3.0, 50.0)    # edge roughness
	# near bank: z 1..(2..3), top at 25..70 % of the run height above its floor
	if nb > -0.05 and ln >= 4:
		var hgt := int(round(ln * clampf(0.3 + nb * 0.6 + jag * 0.12, 0.15, 0.8)))
		var depth := 2 + (1 if nb > 0.25 else 0)
		for ty in range(b - hgt + 1, b + 1):
			for z in range(FZ0, FZ0 + depth):
				_fput(tx, -ty - 1, z, WorldVoxel.STONE if ty > b - hgt + 3 else WorldVoxel.DIRT)
		# the taller bank behind it (z 4..6), a little higher and offset
		var hb := hgt + int(round(ln * (0.15 + 0.2 * fn.get_noise_2d(x * 1.7, 90.0))))
		if nb > 0.12:
			for ty in range(b - mini(hb, ln - 1) + 1, b + 1):
				for z in range(FZ0 + 3, FZ0 + 6):
					_fput(tx, -ty - 1, z, WorldVoxel.STONE_W if ty > b - hb + 2 else WorldVoxel.DIRT)
	# hang from the ceiling: stone / earth with a stalactite edge, roots and vines below it
	if nh > 0.05 and ln >= 5:
		var hl := int(round(ln * clampf(0.15 + nh * 0.5 + jag * 0.15, 0.1, 0.55)))
		var z0 := FZ0 + 1 + (1 if nh > 0.3 else 0)
		for ty in range(a, a + hl):
			for z in range(z0, z0 + 3):
				_fput(tx, -ty - 1, z, WorldVoxel.STONE if ty < a + hl - 2 else WorldVoxel.DIRT)
		if rng.randf() < 0.35:
			var vl := rng.randi_range(2, 5)
			for q in vl:
				var vy := a + hl + q
				if vy >= b:
					break
				_fput(tx, -vy - 1, z0, WorldVoxel.PINE if q < vl - 1 or rng.randf() < 0.5 else WorldVoxel.LEAVES)
		elif rng.randf() < 0.25:
			for q in rng.randi_range(1, 3):
				var vy := a + hl + q
				if vy >= b:
					break
				_fput(tx, -vy - 1, z0 + 1, WorldVoxel.LOG)   # a root

## A big tree: 2x2 trunk over the whole run (z 6..7), flaring roots at the floor, canopy at the ceiling.
func _trunk(tx: int, a: int, b: int, rng: RandomNumberGenerator) -> void:
	var z := FZ0 + 6
	for ty in range(a, b + 1):
		for q in 4:
			_fput(tx + q % 2, -ty - 1, z + q / 2, WorldVoxel.LOG)
	# roots
	for side: int in [-1, 1]:
		var ox := tx + (2 if side > 0 else -1)
		for q in rng.randi_range(2, 4):
			_fput(ox + side * q, -b - 1 + (1 if q == 0 else 0), z - (q % 2), WorldVoxel.LOG)
			_fput(ox + side * (q - 1), -b - 1, z, WorldVoxel.LOG)
	# canopy hugging the ceiling: a wide flattened blob of leaves (clipped by the rock outline)
	var r := rng.randf_range(4.0, 6.0)
	var cy := -a - 1 - 1
	for dz in range(-2, 3):
		for dy in range(-3, 3):
			for dx in range(-int(r) - 1, int(r) + 2):
				var p := Vector3(dx / r, dy / 2.6, dz / 2.2)
				if p.length() <= 1.0 + rng.randf_range(-0.12, 0.08):
					if _fget(tx + dx, cy + dy, z + dz) == 0:
						_fput(tx + dx, cy + dy, z + dz, WorldVoxel.LEAVES if rng.randf() < 0.8 else WorldVoxel.PINE)
	# a few hanging vines from the canopy
	for _v in 6:
		var vx := tx + rng.randi_range(-int(r), int(r))
		for q in rng.randi_range(2, 6):
			if -a - 5 - q < -b - 1:
				break
			_fput(vx, -a - 5 - q, z - 2, WorldVoxel.PINE)

## Layered boulders bulging out of the banks (always touching a bank block below them).
func _boulders(rng: RandomNumberGenerator, fn: FastNoiseLite) -> void:
	for _n in 90:
		var tx := rng.randi_range(0, W - 1)
		var ty := rng.randi_range(0, H - 1)
		if dist[ty * W + tx] < 2:
			continue
		var wy := -ty - 1
		# needs bank support right below (grounded)
		if _fget(tx, wy - 1, FZ0) == 0 and _fget(tx, wy - 1, FZ0 + 1) == 0:
			continue
		var r := rng.randf_range(1.3, minf(2.8, dist[ty * W + tx] * 0.7))
		var cz := float(FZ0) + r * 0.8
		var ri := int(ceil(r)) + 1
		var mat := WorldVoxel.STONE if rng.randf() < 0.6 else WorldVoxel.STONE_W
		for dz in range(-ri, ri + 1):
			for dy in range(-1, ri + 1):
				for dx in range(-ri, ri + 1):
					var p := Vector3(dx, dy * 1.25, dz)
					if p.length() + fn.get_noise_3d((tx + dx) * 5.0, (wy + dy) * 5.0, dz * 5.0) * 0.8 <= r:
						_fput(tx + dx, wy + dy, int(cz) + dz, mat)

func _fput(x: int, y: int, z: int, id: int) -> void:
	var i := x - FX0
	var j := y - FY0
	var k := z - FZ0
	if i < 0 or j < 0 or k < 0 or i >= FNX or j >= FNY or k >= FNZ:
		return
	vox[(k * FNY + j) * FNX + i] = id

func _fget(x: int, y: int, z: int) -> int:
	var i := x - FX0
	var j := y - FY0
	var k := z - FZ0
	if i < 0 or j < 0 or k < 0 or i >= FNX or j >= FNY or k >= FNZ:
		return 0
	return vox[(k * FNY + j) * FNX + i]

## Exposed tops of dirt / stone turn to grass (moss), like the landscape.
func _moss_tops(rng: RandomNumberGenerator) -> void:
	for k in FNZ:
		for j in range(0, FNY - 1):
			for i in FNX:
				var p := (k * FNY + j) * FNX + i
				var id := vox[p]
				if (id == WorldVoxel.DIRT or id == WorldVoxel.STONE or id == WorldVoxel.STONE_W) and vox[p + FNX] == 0:
					if id == WorldVoxel.DIRT or rng.randf() < 0.55:
						vox[p] = WorldVoxel.GRASS

# ---------------------------------------------------------------- mesh (per face, CPU vertex AO)
func _occ(i: int, j: int, k: int) -> bool:
	if i < 0 or j < 0 or k < 0 or i >= FNX or j >= FNY or k >= FNZ:
		return false
	var v := vox[(k * FNY + j) * FNX + i]
	return v > 0 and v < 64

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# faces: normal, then two in-face axes (cell space)
	var dirs := [
		[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
		[Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
	]
	for k in FNZ:
		for j in FNY:
			for i in FNX:
				var id := vox[(k * FNY + j) * FNX + i]
				if id == 0:
					continue
				voxel_count += 1
				var bc: Color = _cols[id] if id < _cols.size() else Color(0.3, 0.3, 0.3)
				# blocks stacked above this one (-> darker toward the bottom of every mass: grounded, AO-like)
				var above := 0
				while above < 12 and _occ(i, j + above + 1, k):
					above += 1
				for dd: Array in dirs:
					var n: Vector3i = dd[0]
					if _occ(i + n.x, j + n.y, k + n.z):
						continue
					var a: Vector3i = dd[1]
					var b: Vector3i = dd[2]
					var l := Vector3i(i, j, k) + n
					# face origin: the block corner on the face plane
					var o := Vector3(FX0 + i, FY0 + j, FZ0 + k)
					if n.x > 0 or n.y > 0 or n.z > 0:
						o += Vector3(n)
					var base := verts.size()
					for c in 4:
						var su := 1 if (c == 1 or c == 2) else 0
						var sv := 1 if c >= 2 else 0
						var p := o + Vector3(a) * su + Vector3(b) * sv
						var da := a * (1 if su == 1 else -1)
						var db := b * (1 if sv == 1 else -1)
						var s1 := 1.0 if _occ(l.x + da.x, l.y + da.y, l.z + da.z) else 0.0
						var s2 := 1.0 if _occ(l.x + db.x, l.y + db.y, l.z + db.z) else 0.0
						var cc := 1.0 if _occ(l.x + da.x + db.x, l.y + da.y + db.y, l.z + da.z + db.z) else 0.0
						var ao := 0.0 if s1 + s2 > 1.5 else (3.0 - s1 - s2 - cc) / 3.0
						verts.append(p)
						norms.append(Vector3(n))
						colors.append(Color(bc.r, bc.g, bc.b, float(id) / 255.0))
						uvs.append(Vector2(ao, above + (FY0 + j + 1.0 - p.y)))
					var nf := Vector3(n)
					var fl := Vector3(a).cross(Vector3(b)).dot(nf) > 0.0
					idx.append_array(PackedInt32Array([base, base + (2 if fl else 1), base + (1 if fl else 2),
						base, base + (3 if fl else 2), base + (2 if fl else 3)]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	_arrays = arr

# ---------------------------------------------------------------- main thread
func upload(sun_dir: Vector3) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/world/voxel_fore.gdshader")
	var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, mask)
	material.set_shader_parameter("fg_mask", ImageTexture.create_from_image(img))
	material.set_shader_parameter("mask_size", Vector2(W, H))
	material.set_shader_parameter("ball_pos", Vector3(-1000, -1000, 0))
	material.set_shader_parameter("ball_r", BALL_R)
	material.set_shader_parameter("ball_fade", BALL_FADE)
	material.set_shader_parameter("sun_dir", sun_dir)
	material.set_shader_parameter("fade", 0.0)
	WorldPbr.bind(material, false, 1.0)
	if _cols.size() > WorldVoxel.GRASS:
		var dc := _cols[WorldVoxel.DIRT]
		var gc := _cols[WorldVoxel.GRASS]
		material.set_shader_parameter("dirt_col", Vector3(dc.r, dc.g, dc.b))
		material.set_shader_parameter("grass_col", Vector3(gc.r, gc.g, gc.b))
	var verts: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX] if not _arrays.is_empty() else PackedVector3Array()
	if verts.is_empty():
		return
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	var mi := MeshInstance3D.new()
	mi.name = "ForeMesh"
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	_arrays = []

## The ball (interpolated world centre) every frame.
func set_ball(p: Vector3) -> void:
	_last_focus_ms = Time.get_ticks_msec()
	if material:
		material.set_shader_parameter("ball_pos", p)
		material.set_shader_parameter("ball_r", BALL_R)
		material.set_shader_parameter("ball_fade", BALL_FADE)

## Fallback when nobody feeds the ball: keep a wide clear circle around the camera's aim point.
func fallback_from_camera(cam: Camera3D) -> void:
	if material == null or cam == null or Time.get_ticks_msec() - _last_focus_ms < 300:
		return
	var p := cam.global_position
	material.set_shader_parameter("ball_pos", Vector3(p.x, p.y, 0.0))
	material.set_shader_parameter("ball_r", 8.0)

## Tests: flat magenta output for the safety check.
func set_debug_mask(on: bool) -> void:
	if material:
		material.set_shader_parameter("debug_mask", 1.0 if on else 0.0)

func set_fade(f: float) -> void:
	if material:
		material.set_shader_parameter("fade", f)
