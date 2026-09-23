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
const BALL_R := 2.6
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

## Worker thread: pieces + mesh arrays. cols: WorldVoxel block colours (linear), indexed by block id.
func generate(cols: PackedColorArray) -> void:
	_cols = cols
	vox.resize(FNX * FNY * FNZ)
	vox.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var fn := FastNoiseLite.new()
	fn.seed = 313
	fn.frequency = 0.35
	var step := 6
	for gy in range(2, H - 2, step):
		for gx in range(0, W, step):
			var tx := gx + rng.randi_range(0, step - 1)
			var ty := gy + rng.randi_range(0, step - 1)
			if tx >= W or ty >= H:
				continue
			var d := dist[ty * W + tx]
			if d < 1 or rng.randf() > (0.35 if d < 2 else 0.6):
				continue
			var r := rng.randf()
			if d >= 6 and r < 0.26:
				_trunk(tx, ty, d, rng)
			elif d >= 5 and r < 0.44:
				_pillar(tx, ty, d, rng)
			elif d >= 6 and r < 0.52:
				_arch(tx, ty, d, rng)
			elif d >= 4 and r < 0.7:
				_bank(tx, ty, d, rng, fn)
			else:
				_boulder(tx, ty, d, rng, fn)
			piece_count += 1
	_moss_tops(rng)
	_build_mesh()

# ---------------------------------------------------------------- pieces (world block coords, y up)
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

## Vertical run of coverable tiles through (tx, ty): [top ty, bottom ty] with dist >= 2.
func _vrun(tx: int, ty: int) -> Vector2i:
	var a := ty
	var b := ty
	while a > 0 and dist[(a - 1) * W + tx] >= 2:
		a -= 1
	while b < H - 1 and dist[(b + 1) * W + tx] >= 2:
		b += 1
	return Vector2i(a, b)

func _boulder(tx: int, ty: int, d: int, rng: RandomNumberGenerator, fn: FastNoiseLite) -> void:
	var r := rng.randf_range(1.0, maxf(1.2, minf(3.2, d * 0.6)))
	var cz := 1.0 + r + rng.randf_range(0.0, 3.0)
	var c := Vector3(tx + 0.5, -ty - 0.5, cz)
	var ri := int(ceil(r)) + 1
	var mat := WorldVoxel.STONE if rng.randf() < 0.7 else WorldVoxel.STONE_W
	for dz in range(-ri, ri + 1):
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var p := Vector3(dx, dy * 1.2, dz)
				if p.length() + fn.get_noise_3d(c.x + dx, c.y + dy, dz * 3.0) * 0.9 <= r:
					_fput(int(floorf(c.x)) + dx, int(floorf(c.y)) + dy, int(floorf(cz)) + dz, mat)

func _bank(tx: int, ty: int, d: int, rng: RandomNumberGenerator, fn: FastNoiseLite) -> void:
	var w := rng.randi_range(4, mini(10, d + 3))
	var hh := rng.randi_range(2, 3)
	var zc := rng.randi_range(1, 3)
	var x0 := tx - w / 2
	var y0 := -ty - hh
	for dx in w:
		var edge := mini(dx, w - 1 - dx)
		var ch := mini(hh, edge + 1 + int(fn.get_noise_1d((x0 + dx) * 2.0) * 1.5))
		for dz in range(0, rng.randi_range(2, 4)):
			for dy in maxi(ch - dz / 2, 1):
				_fput(x0 + dx, y0 + dy, zc + dz, WorldVoxel.DIRT)

func _trunk(tx: int, ty: int, _d: int, rng: RandomNumberGenerator) -> void:
	var run := _vrun(tx, ty)
	var top := run.x + rng.randi_range(1, 3)
	var bot := run.y
	if bot - top < 6:
		return
	var z := rng.randi_range(3, 7)
	var wide := rng.randf() < 0.35
	for ty2 in range(top, bot + 1):
		_fput(tx, -ty2 - 1, z, WorldVoxel.LOG)
		if wide:
			_fput(tx + 1, -ty2 - 1, z, WorldVoxel.LOG)
	# leaf clumps along the trunk and a crown at its top, vines hanging from them
	var clumps := [top]
	for _c in rng.randi_range(1, 2):
		clumps.append(rng.randi_range(top + 2, maxi(top + 3, (top + bot) / 2)))
	for cy: int in clumps:
		var rr := 2 if cy == top else 1
		for dz in range(-1, 2):
			for dy in range(-rr, rr + 1):
				for dx in range(-rr - 1, rr + 2):
					if absi(dx) + absi(dy) + absi(dz) > rr + 1 or rng.randf() < 0.2:
						continue
					if _fget(tx + dx, -cy - 1 + dy, z + dz) == 0:
						_fput(tx + dx, -cy - 1 + dy, z + dz, WorldVoxel.LEAVES)
		for _v in rng.randi_range(1, 3):
			var vx := tx + rng.randi_range(-rr - 1, rr + 1)
			var ln := rng.randi_range(2, 6)
			for q in ln:
				if -cy - 2 - q < -bot - 1:
					break
				_fput(vx, -cy - 2 - q, z + 1, WorldVoxel.PINE)

func _pillar(tx: int, ty: int, _d: int, rng: RandomNumberGenerator) -> void:
	var run := _vrun(tx, ty)
	var bot := run.y
	var top := maxi(run.x + 1, bot - rng.randi_range(4, 11))
	if bot - top < 3:
		return
	var z := rng.randi_range(2, 5)
	for ty2 in range(top, bot + 1):
		for q in 4:
			if ty2 == top and rng.randf() < 0.45:
				continue   # broken top
			_fput(tx + q % 2, -ty2 - 1, z + q / 2, WorldVoxel.RUIN)
	# plinth + moss cap + a hanging vine
	for dx in range(-1, 3):
		_fput(tx + dx, -bot - 1, z - 1 if z > 1 else z, WorldVoxel.RUIN)
	_fput(tx, -top, z, WorldVoxel.RUIN_MOSS)
	if rng.randf() < 0.6:
		for q in rng.randi_range(2, 5):
			_fput(tx + 1, -top - 1 - q, z + 2, WorldVoxel.PINE)

func _arch(tx: int, ty: int, d: int, rng: RandomNumberGenerator) -> void:
	var span := mini(rng.randi_range(3, 5), d - 2)
	var hh := mini(rng.randi_range(4, 7), d)
	var z := rng.randi_range(2, 4)
	var base := -ty + hh / 2
	for side: int in [-1, 1]:
		var px := tx + side * (span / 2 + 1)
		for y in hh:
			_fput(px, base - 1 - y, z, WorldVoxel.RUIN)
	var broken := rng.randf() < 0.5
	for dx in range(-(span / 2 + 1), span / 2 + 2):
		if broken and dx > 0:
			continue
		_fput(tx + dx, base, z, WorldVoxel.RUIN_MOSS if rng.randf() < 0.4 else WorldVoxel.RUIN)
	if rng.randf() < 0.7:
		for q in rng.randi_range(2, 4):
			_fput(tx - 1, base - 1 - q, z + 1, WorldVoxel.PINE)

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
						uvs.append(Vector2(ao, 0.0))
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

## Fallback when nobody feeds the ball: keep a wide clear circle around the camera's aim point.
func fallback_from_camera(cam: Camera3D) -> void:
	if material == null or cam == null or Time.get_ticks_msec() - _last_focus_ms < 300:
		return
	var p := cam.global_position
	material.set_shader_parameter("ball_pos", Vector3(p.x, p.y, 0.0))
	material.set_shader_parameter("ball_r", 5.0)

## Tests: flat magenta output for the safety check.
func set_debug_mask(on: bool) -> void:
	if material:
		material.set_shader_parameter("debug_mask", 1.0 if on else 0.0)

func set_fade(f: float) -> void:
	if material:
		material.set_shader_parameter("fade", f)
