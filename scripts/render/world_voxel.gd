class_name WorldVoxel
extends Node3D
@warning_ignore_start("integer_division")
## Day levels: a MINECRAFT-STYLE procedural voxel landscape behind the level, in the level's own block
## language (1-unit cubes, the level's palette: grass 35/19, earth 45/47/48, stone 9/46/86, leaves 14,
## trunks 16/48, water 54/10, sand 88, ruin stone 42).
##
## Volume: x [X0, X0+NX), y [Y0, Y0+NY), z from -Z0 back to BACK_Z (voxel k spans z [-(Z0+k+1), -(Z0+k)]).
## Generation (deterministic, seeded):
##   - macro landform = the sky's WorldVista.sample() (the level's ground profile, the falls' river, the home
##     island), continued from world's depth seam (WorldDepth.depth_seam) at z -26 and blended back into the
##     vista exactly at BACK_Z, so the smooth far land continues the voxels;
##   - Minecraft relief on top: fbm hills, ridged mountains with snow caps, terraced cliffs, 3D-noise overhangs,
##     a river valley kept open, a lake at WATER_Y, a floating-island keel underside with voxel stalactites;
##   - floating voxel islands (ruins held aloft) with tapering undersides and waterfalls, voxel oaks / pines /
##     big oaks, bushes, tall grass + flowers, small ruins (pillars, arches, broken walls), cliff waterfalls.
## READABILITY: nothing is ever in front of z = -Z0; right behind open sky-connected air the terrain stays
## below the local air bottom (a clearance that only relaxes >= 20 units back), and everything hazes toward
## the sky colour with depth (voxel_block.gdshader), so open air keeps reading as open.
## Meshing: face-culled (only faces the fixed front camera can see: +-x, +-y, +z), side faces merged vertically,
## chunked; per-block colour, smooth Minecraft vertex-style AO, bevels and edge seams are all resolved in the
## shader from a 3D block-id texture (so merged faces cost nothing). Built on worker threads AFTER the level is
## playable (start()), then chunks are uploaded over a few frames and the whole landscape fades in.
## Usage (WorldView, day levels): add_child; setup(terrain, depth, vista) during the build; start() when built.

signal finished

const X0 := -104
const NX := 608
const Y0 := -256
const NY := 320
const Z0 := 3
const NZ := 160
const BACK_Z := -163.0           # = -(Z0 + NZ): the vista (near_limit) starts here
const CHX := 32
const CHY := 40
const CHK := 20
const WATER_Y := -172            # lake / river surface (top of the water blocks), = WorldVista.FLOOR_Y
const NEAR_K := 24               # voxel rows inside world's depth-extrusion range (z > -27)
const G3 := 4                    # 3D noise lattice spacing
const SHADOW_K := 60             # chunks starting in front of this row cast sun shadows
const PLANT_K := 60              # plants only in front of this row (sub-pixel beyond)
const UPLOADS_PER_FRAME := 24
const FADE_TIME := 1.6

enum { AIR, GRASS, DIRT, DIRT_L, CLAY, STONE, STONE_W, STONE_L, SAND, SNOW, SNOW_GRASS, LOG, LEAVES, PINE,
	RUIN, RUIN_MOSS, GRAVEL, PINE_LOG, N_SOLID }
const WATER := 64
const WATER_MIST := 65           # the last blocks of a free fall: dissolving spray
const TALLGRASS := 70            # >= TALLGRASS: plants (crossed quads)
const FLOWER_R := 71
const FLOWER_Y := 72
const FLOWER_B := 73
const FERN := 74
const FALL_MAX := 26             # free-falling island waterfalls dissolve into mist after this many blocks

## Tests: false disables the landscape (WorldView checks it).
static var enabled := true

var W := 400                      # level width
var vox := PackedByteArray()      # block ids, index (k * NY + j) * NX + i
var timings := {}
var face_count := 0
var is_ready := false
var material: ShaderMaterial
var water_material: ShaderMaterial
var plant_material: ShaderMaterial
var vol_tex: ImageTexture3D
var sun_dir := Vector3(-0.30, 0.67, 0.68)

var _ab := PackedFloat32Array()   # per level column: world y of the bottom of the deepest open-sky air tile
var _seam := PackedFloat32Array() # per level column: world's depth seam height (NAN = none)
var _dtop := PackedFloat32Array() # level column x NEAR_K: world's depth top (NAN = none)
var _vg := PackedFloat32Array()   # vista macro heights on a G3 grid
var _vgx := 0
var _vgk := 0
var _river := PackedFloat32Array()  # vista river x per voxel row k
var _has_vista := false
var _palette := {}                # level block id -> Color (sRGB)
# column fields (NX * NZ, index k * NX + i)
var _H := PackedFloat32Array()
var _B := PackedFloat32Array()
var _AMP := PackedFloat32Array()
var _HMAX := PackedFloat32Array()
var _FOR := PackedFloat32Array()
var _n3 := PackedFloat32Array()
var _g3x := 0
var _g3y := 0
var _g3k := 0
var _islands: Array[PackedFloat32Array] = []   # [cx, cy, ck, R, Rz, D, falls, ruin]
var _rows: Array = []
var _slices: Array = []
var _images: Array[Image] = []
var _chunks: Array = []
var _thread: Thread
var _abort := false
var _upload_i := 0
var _uploading := false
var _fade_t := -1.0
var _vista: WorldVista
## Phase 2: the foreground band in front of the gameplay plane (occlusion-safe, see WorldVoxelFore).
var fore: WorldVoxelFore
var _terrain_mat: ShaderMaterial
var _sh_block: Shader
var _sh_water: Shader
var _sh_plant: Shader
var _dE := PackedFloat32Array()   # world depth volume extrusion E per level tile (0 = none)
var _dH := 0
var _fz := PackedFloat32Array()   # forest-zone weight per voxel column
var _templates: Array[Dictionary] = []   # the level's own crown silhouettes (see _crown_templates)
var _hollow_img: Image   # keep-out depth per tile (forest hollows, interior rooms), see _keep_out_image
## OFF by default (lead / user: "random blocks in random places"); tests may set it true before build.
static var fore_enabled := false
var _lin_cols := PackedColorArray()
var _grass_b := Color(-1, 0, 0)
var _shrine := Vector2(-10000.0, 0.0)   # level-specific keep-out (FV: the summit shrine), world x / y
var _rim := PackedFloat32Array()   # vista island_edge (depth of the home island rim) per G3 x column

class Noises:
	var hill := FastNoiseLite.new()
	var detail := FastNoiseLite.new()
	var mask := FastNoiseLite.new()
	var ridge := FastNoiseLite.new()
	var cliff := FastNoiseLite.new()
	var forest := FastNoiseLite.new()
	var under := FastNoiseLite.new()
	var biome := FastNoiseLite.new()
	var cave := FastNoiseLite.new()

	func _init() -> void:
		_cfg(hill, 101, 0.014, 4, FastNoiseLite.FRACTAL_FBM)
		_cfg(detail, 102, 0.11, 2, FastNoiseLite.FRACTAL_FBM)
		_cfg(mask, 103, 0.0085, 3, FastNoiseLite.FRACTAL_FBM)
		_cfg(ridge, 104, 0.011, 4, FastNoiseLite.FRACTAL_RIDGED)
		_cfg(cliff, 105, 0.012, 2, FastNoiseLite.FRACTAL_FBM)
		_cfg(forest, 106, 0.016, 3, FastNoiseLite.FRACTAL_FBM)
		_cfg(under, 107, 0.07, 3, FastNoiseLite.FRACTAL_RIDGED)
		_cfg(biome, 108, 0.014, 2, FastNoiseLite.FRACTAL_FBM)
		_cfg(cave, 109, 0.06, 3, FastNoiseLite.FRACTAL_FBM)

	func _cfg(n: FastNoiseLite, s: int, f: float, o: int, t: FastNoiseLite.FractalType) -> void:
		n.seed = s
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = f
		n.fractal_octaves = o
		n.fractal_type = t

class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

static func _occ(id: int) -> bool:
	return id > 0 and id < 64

func _exit_tree() -> void:
	_abort = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()

# =================================================================== setup (main thread, fast)
## Reads everything it needs from the other world modules (all three may be null except terrain).
func setup(terrain: WorldTerrain, depth: WorldDepth, vista: WorldVista) -> void:
	var t0 := Time.get_ticks_msec()
	W = terrain.W
	var H := terrain.H
	_vista = vista
	if vista:
		sun_dir = vista.sun_dir
	_ab.resize(W)
	for x in W:
		var deep := -1
		for y in H:
			var i := y * W + x
			if terrain.sky[i] and not terrain.solid[i]:
				deep = y
		_ab[x] = -float(deep + 1) if deep >= 0 else 0.0
	_seam.resize(W)
	_seam.fill(NAN)
	_dtop.resize(W * NEAR_K)
	_dtop.fill(NAN)
	if depth:
		var sm: Dictionary = depth.depth_seam()
		var hs: PackedFloat32Array = sm.get("height", PackedFloat32Array())
		for x in mini(W, hs.size()):
			_seam[x] = hs[x]
		for k in NEAR_K:
			var z := -(Z0 + k + 0.5)
			for x in W:
				_dtop[k * W + x] = depth.depth_top_y(x + 0.5, z)
		_dE = depth.depth.duplicate()
		_dH = terrain.H
	_has_vista = vista != null
	if fore_enabled:
		fore = WorldVoxelFore.new()
		fore.name = "Fore"
		add_child(fore)
		fore.setup(terrain)
	if not WorldPalette.is_odyssey():
		_shrine = Vector2(WorldPalette.FV_SHRINE.x + 0.5, -float(WorldPalette.FV_SHRINE.y))
	_load_palette(terrain.ref_dir)
	_lin_cols.resize(N_SOLID)
	var table := _color_table()
	for id: int in table:
		_lin_cols[id] = (table[id] as Color).srgb_to_linear()
	_level_colors(terrain)
	_terrain_mat = terrain.material
	if not WorldPalette.is_odyssey():
		_build_forest_zone(terrain)
	_hollow_img = _keep_out_image(terrain, depth)
	timings["voxel_setup"] = Time.get_ticks_msec() - t0

## Per level tile: how far back (units, R8) no voxel may be seen through that tile - the ray from the camera to a
## voxel fragment crosses the gameplay plane at the tile, and the fragment lies in front of z = -value:
##   - detail's forest hollows (WorldForest.hollow_image): 63 (their deep trunk field + backstop at -62);
##   - world's recessed interior rooms (depth.room / room_r): the room's back wall block, 1.2 + R + 1.2 (+0.2),
##     so rooms show their masonry, and windows see the landscape only behind it.
func _keep_out_image(terrain: WorldTerrain, depth: WorldDepth) -> Image:
	var W2 := terrain.W
	var b := PackedByteArray()
	b.resize(W2 * terrain.H)
	if not WorldPalette.is_odyssey():
		var hm := WorldForest.hollow_mask(terrain)
		for i in mini(hm.size(), b.size()):
			if hm[i]:
				b[i] = 63
	if depth and depth.room.size() == b.size():
		var rooms := 0
		var H2 := terrain.H
		for i in b.size():
			if depth.room[i] != 0:
				var v := clampi(int(ceil(2.6 + depth.room_r[i])), 1, 255)
				# dilated 1 tile: rays grazing past the slab's rounded corners around a room showed voxel slivers
				var x := i % W2
				var y := i / W2
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and ny >= 0 and nx < W2 and ny < H2:
							var j := ny * W2 + nx
							b[j] = maxi(b[j], v)
				rooms += 1
		print("WorldVoxel keep-out: %d room tiles" % rooms)
	# the landscape is only ever seen through OPEN SKY: any other tile has its own geometry behind it (slab,
	# depth volume, room, forest, cave), and a ray grazing past a solid's rounded corner in that tile's
	# footprint showed voxel land as pale slivers along block edges (flickering as the camera moved)
	if terrain.sky.size() == b.size():
		var room_ok: bool = depth != null and depth.room.size() == b.size()
		for i in b.size():
			var open_sky: bool = terrain.sky[i] != 0 and not terrain.solid[i]
			if open_sky or b[i] == 63 or (room_ok and depth.room[i] != 0):
				continue
			b[i] = 255
	return Image.create_from_data(W2, terrain.H, false, Image.FORMAT_R8, b)

## The vista's macro landform on a G3 grid (worker thread: WorldVista.sample() only reads its built state).
func _sample_vista() -> void:
	_vgx = NX / G3 + 1
	_vgk = NZ / G3 + 1
	_vg.resize(_vgx * _vgk)
	_rim.resize(_vgx)
	_river.resize(NZ)
	for gi in _vgx:
		_rim[gi] = _vista.island_edge(X0 + gi * G3 + 0.5) if _vista else 1000.0
	for gk in _vgk:
		var z := -(Z0 + gk * G3 + 0.5)
		for gi in _vgx:
			var x := X0 + gi * G3 + 0.5
			_vg[gk * _vgx + gi] = _vista.sample(x, z).x if _vista else _fallback_base(x)
	for k in NZ:
		_river[k] = _vista.river_x(Z0 + k + 0.5) if _vista else 148.0

func _fallback_base(x: float) -> float:
	var lx := clampi(int(floorf(x)), 0, W - 1)
	return maxf(_ab[lx] - 6.0, float(WATER_Y) - 2.0)

func _load_palette(ref_dir: String) -> void:
	var f := FileAccess.open(ref_dir.path_join("minimap_colors.json"), FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for key: String in (d as Dictionary):
			var v: Variant = d[key]
			if v is String:
				_palette[int(key)] = Color.html(v as String)

func _pal(id: int, fallback: Color) -> Color:
	return _palette.get(id, fallback)

# =================================================================== async build
func start() -> void:
	if _thread:
		return
	_thread = Thread.new()
	_thread.start(_run)

func _group(fn: Callable, n: int) -> void:
	var g := WorkerThreadPool.add_group_task(fn, n, -1, false, "WorldVoxel")
	WorkerThreadPool.wait_for_group_task_completion(g)

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_sample_vista()
	timings["voxel_vista_grid"] = Time.get_ticks_msec() - t0
	# P1: column fields
	_rows.resize(NZ)
	_group(_row_task, NZ)
	if _abort: return
	for k in NZ:
		var r: Array = _rows[k]
		_H.append_array(r[0])
		_B.append_array(r[1])
		_AMP.append_array(r[2])
		_HMAX.append_array(r[3])
		_FOR.append_array(r[4])
	_rows.clear()
	_place_islands()
	timings["voxel_fields"] = Time.get_ticks_msec() - t0
	# P2: 3D noise lattice
	var t1 := Time.get_ticks_msec()
	_g3x = NX / G3 + 2
	_g3y = NY / G3 + 2
	_g3k = NZ / G3 + 2
	_rows.resize(_g3k)
	_group(_n3_task, _g3k)
	if _abort: return
	for k in _g3k:
		_n3.append_array(_rows[k])
	_rows.clear()
	# P3: fill
	_slices.resize(NZ)
	_group(_fill_task, NZ)
	if _abort: return
	vox = PackedByteArray()
	for k in NZ:
		vox.append_array(_slices[k])
	_slices.clear()
	timings["voxel_fill"] = Time.get_ticks_msec() - t1
	# P4: features
	t1 = Time.get_ticks_msec()
	_stamp_features()
	timings["voxel_features"] = Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	if fore:
		fore.generate(_lin_cols)
	timings["voxel_fore"] = Time.get_ticks_msec() - t1
	if _abort: return
	# P5: texture slices + meshes
	t1 = Time.get_ticks_msec()
	var sl := NX * NY
	for k in NZ:
		_images.append(Image.create_from_data(NX, NY, false, Image.FORMAT_R8, vox.slice(k * sl, (k + 1) * sl)))
	var ncx := NX / CHX
	var ncy := NY / CHY
	var nck := NZ / CHK
	_chunks.resize(ncx * ncy * nck)
	_group(_mesh_task, _chunks.size())
	timings["voxel_mesh"] = Time.get_ticks_msec() - t1
	# the 3D block texture is created here too (RenderingServer resource creation is thread-safe), so the
	# main thread never blocks on the 30 MB upload
	t1 = Time.get_ticks_msec()
	vol_tex = ImageTexture3D.new()
	vol_tex.create(Image.FORMAT_R8, NX, NY, NZ, false, _images)
	_images.clear()
	timings["voxel_tex_thread"] = Time.get_ticks_msec() - t1
	# shaders parse / compile off the main thread too
	t1 = Time.get_ticks_msec()
	_sh_block = load("res://shaders/world/voxel_block.gdshader")
	_sh_water = load("res://shaders/world/voxel_water.gdshader")
	_sh_plant = load("res://shaders/world/voxel_plant.gdshader")
	_make_materials()   # new, not yet used resources: safe to set up off the main thread
	timings["voxel_shader_thread"] = Time.get_ticks_msec() - t1
	timings["voxel_thread_total"] = Time.get_ticks_msec() - t0
	if not _abort:
		call_deferred("_on_generated")

# ------------------------------------------------------------------- P1 column fields
func _row_task(k: int) -> void:
	var nz := Noises.new()
	var d := k + 0.5
	var z := -(Z0 + d)
	var hs := PackedFloat32Array(); hs.resize(NX)
	var bs := PackedFloat32Array(); bs.resize(NX)
	var am := PackedFloat32Array(); am.resize(NX)
	var hm := PackedFloat32Array(); hm.resize(NX)
	var fo := PackedFloat32Array(); fo.resize(NX)
	# clearance: sliding min of the air bottom over a window that widens with depth (camera parallax)
	var r := 1 + int(d * 0.42)
	var cl := PackedFloat32Array(); cl.resize(W)
	for x in W:
		var m := INF
		for q in range(maxi(0, x - r), mini(W, x + r + 1)):
			m = minf(m, _ab[q])
		cl[x] = m
	# above the local air bottom only well behind the plane, rising like a hillside (never a wall)
	# the sky stays dominant: low for the first ~32 units, gentle rise, real height only far back (z < -60)
	var rise := maxf(d - 32.0, 0.0) * 0.45 + maxf(d - 60.0, 0.0) * 0.65
	var riv := _river[k]
	var shrine_x := _shrine.x
	var shrine_y := _shrine.y
	var env_h := smoothstep(18.0, 40.0, d) * (1.0 - smoothstep(NZ - 12.0, NZ - 2.0, d))
	var mtn_env := smoothstep(58.0, 95.0, d) * (1.0 - smoothstep(NZ - 16.0, NZ - 2.0, d))
	for i in NX:
		var x := X0 + i + 0.5
		var lx := clampi(int(floorf(x)), 0, W - 1)
		var hmax := cl[lx] - 1.5 + rise
		if shrine_x > -1000.0 and absf(x - shrine_x) < 9.0 + d * 0.45 and d < 110.0:
			hmax = minf(hmax, shrine_y - 12.0 + maxf(d - 80.0, 0.0) * 1.2)   # the finale's light pillar stays open
		var v := _vista_at(i, k)
		var base := v
		var sv := _seam[lx]
		var valley := 0.0
		if not is_nan(sv):
			var near := sv - maxf(d - 23.0, 0.0) * 0.05
			base = lerpf(near, v, smoothstep(23.0, 70.0, d))
		else:
			valley = 1.0 - smoothstep(-160.0, -135.0, v)
		var high := smoothstep(-150.0, -110.0, v)   # highlands (massif, plateau) carry the mountains
		# distance to the home island's rim (the vista's cliff into the cloud sea): relief calms down there
		var gx := clampi(int(float(i) / G3 + 0.5), 0, _vgx - 1)
		var rim_k := smoothstep(6.0, 40.0, _rim[gx] - (d + Z0))
		var h := base
		h += nz.hill.get_noise_2d(x, z) * 9.0 * env_h * rim_k
		h += nz.detail.get_noise_2d(x, z) * 0.7 * env_h
		var mask := smoothstep(-0.08, 0.32, nz.mask.get_noise_2d(x, z)) * mtn_env * rim_k
		var rv := smoothstep(16.0, 52.0, absf(x - riv))
		mask *= lerpf(1.0, rv, valley) * lerpf(0.45 * smoothstep(60.0, 80.0, d), 1.0, high)
		# behind the Elder Grove and the Eastern Wood the land continues as FOREST: rolling, no big mountains
		mask *= 1.0 - 0.85 * _forest_zone(x) * (1.0 - smoothstep(100.0, 140.0, d))
		var rg := nz.ridge.get_noise_2d(x, z) * 0.5 + 0.5
		h += mask * (10.0 + 60.0 * rg * rg)
		# the river valley (continues the falls' pool) and the lake floor
		if valley > 0.2:
			var rd := absf(x - riv)
			if rd < 6.0:
				h = minf(h, lerpf(WATER_Y - 4.0, WATER_Y - 0.5, rd / 6.0))
		# readability clamp with an irregular ceiling (hillsides, not a regular staircase), then cliffs
		var hn := nz.hill.get_noise_2d(x * 1.7 + 311.0, z * 1.7) * 0.5 + 0.5
		h = minf(h, hmax - hn * 5.0 * smoothstep(20.0, 40.0, d))
		var cliffy := smoothstep(0.3, 0.55, nz.cliff.get_noise_2d(x, z)) * env_h
		if cliffy > 0.0:
			var tstep := 6.0
			var q := h / tstep
			var f := q - floorf(q)
			h = lerpf(h, (floorf(q) + smoothstep(0.5, 0.8, f)) * tstep, cliffy)
		h = minf(h, hmax)
		# the back rows melt exactly into the vista's land (its first row is at BACK_Z)
		h = lerpf(h, v + nz.detail.get_noise_2d(x, z) * 1.0, smoothstep(NZ - 14.0, NZ - 2.0, d))
		if k < NEAR_K and x >= 0.0 and x < W:
			var dt := _dtop[k * W + lx]
			if not is_nan(dt):
				h = minf(h, dt - 1.0)
		# keel underside (follows the vista's home keel, a little deeper so that one stays hidden)
		var u := (x - 200.0) / 280.0
		var dk := 190.0 * pow(maxf(1.0 - pow(absf(u), 1.8), 0.0), 0.7) + 8.0
		var t := _keel_t(-z, absf(u))
		var ky := -196.0 - dk * pow(t, 1.15)
		var s01 := nz.under.get_noise_2d(x, z) * 0.5 + 0.5
		# a few broad, tapered hanging lobes instead of a curtain of thin columns (smooth, low-frequency)
		var lobe := smoothstep(0.55, 0.95, s01)
		# (the first rows under the level stay a clean edge: per-column steps there read as vertical stripes)
		var lobe_k := smoothstep(30.0, 70.0, d)
		var b := ky - 4.0 - (lobe * lobe * 12.0 + absf(nz.detail.get_noise_2d(x * 0.6, z * 0.6)) * 1.5) * lobe_k
		b = maxf(b, float(Y0) + 0.5)
		# beyond the level's x edges the land sets back the further out it is (no face right beside the level,
		# which the zoomed-out overview saw as a flat wall); an irregular cliff line
		var outx := maxf(-x, x - float(W))
		var setback := 0.0 if outx <= 0.0 else 3.0 + outx * 0.9 + nz.hill.get_noise_2d(x * 0.8, 77.0) * 4.0
		if outx > 0.0:
			# ... and stays low near the level: a hillside rising away, never a wall beside the level edge
			h = minf(h, -205.0 + maxf(d - setback - outx * 0.3, 0.0) * 1.3)
		if d < setback or (outx > 0.0 and h < b + 2.0):
			h = -INF
			b = INF
		elif v < b + 2.0 and d > 30.0:
			h = -INF   # beyond the rim: open air down to the cloud sea
			b = INF
		else:
			h = maxf(h, b + 2.0)
		var amp := mask * 5.0 * smoothstep(60.0, 80.0, d)
		amp = clampf(minf(amp, hmax - h - 1.0), 0.0, 9.0)
		hs[i] = h
		bs[i] = b
		am[i] = amp
		hm[i] = hmax
		fo[i] = nz.forest.get_noise_2d(x, z)
	_rows[k] = [hs, bs, am, hm, fo]

func _vista_at(i: int, k: int) -> float:
	var fx := float(i) / G3
	var fk := float(k) / G3
	var gi := mini(int(fx), _vgx - 2)
	var gk := mini(int(fk), _vgk - 2)
	var tx := fx - gi
	var tk := fk - gk
	var a := _vg[gk * _vgx + gi]
	var b := _vg[gk * _vgx + gi + 1]
	var c := _vg[(gk + 1) * _vgx + gi]
	var e := _vg[(gk + 1) * _vgx + gi + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, e, tx), tk)

## Parameter t of the vista's home keel surface at depth dz behind z = 0 (inverts its z(t)).
func _keel_t(dz: float, au: float) -> float:
	if dz <= 4.0:
		return 0.0
	var lo := 0.0
	var hi := 1.0
	for _it in 22:
		var m := (lo + hi) * 0.5
		var zz := 4.0 + pow(m, 0.8) * 300.0 + au * m * 40.0
		if zz < dz:
			lo = m
		else:
			hi = m
	return (lo + hi) * 0.5

# ------------------------------------------------------------------- floating islands
func _place_islands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var tries := 0
	while _islands.size() < 12 and tries < 2500:
		tries += 1
		var cx := rng.randf_range(-70.0, 470.0)
		var style := rng.randi_range(0, 2)
		var R := rng.randf_range(6.0, 11.0) if _islands.size() > 3 else rng.randf_range(13.0, 18.0)
		var Rz := R * rng.randf_range(0.55, 0.85)
		var ck := rng.randf_range(maxf(60.0 + Rz * 0.5, 118.0 if R > 12.0 else 0.0), NZ - 6.0 - Rz)
		var D := R * rng.randf_range(1.3, 1.9) * (0.7 if style == 1 else (1.5 if style == 2 else 1.0))
		var ground := -INF
		for s in 9:
			var px := int(cx - X0 + (s % 3 - 1) * R * 0.9)
			var pk := int(ck + (s / 3 - 1) * Rz * 0.9)
			if px < 0 or px >= NX or pk < 0 or pk >= NZ:
				continue
			ground = maxf(ground, _H[pk * NX + px] + _AMP[pk * NX + px])
		var lo := ground + D + 9.0
		var hi := minf(ground + D + 110.0, 16.0)
		if lo > hi:
			continue
		var cy := rng.randf_range(maxf(lo, -125.0), hi) if hi > -125.0 else rng.randf_range(lo, hi)
		# few islands in the gameplay band close behind the level (they'd crowd the play air)
		if ck < 95.0 and cy > -140.0 and cy < -15.0 and rng.randf() < 0.75:
			continue
		var ok := true
		for o in _islands:
			if absf(o[0] - cx) < (o[3] + R) * 1.15 and absf(o[2] - ck) < (o[4] + Rz) * 1.3 and absf(o[1] - cy) < o[5] + D + 6.0:
				ok = false
				break
		if not ok:
			continue
		var falls := 1.0 if (R > 8.0 and rng.randf() < 0.45) else 0.0
		var ruin := 1.0 if rng.randf() < 0.55 else 0.0
		# a second lobe so islands aren't all one round cone
		var la := rng.randf_range(0.0, TAU)
		var lr := rng.randf_range(0.4, 0.75) if rng.randf() < 0.7 else 0.0
		_islands.append(PackedFloat32Array([cx, floorf(cy), ck, R, Rz, D, falls, ruin,
			cos(la) * R * 0.75, sin(la) * Rz * 0.75, lr, float(style)]))

## Island top / bottom at a column, or Vector2(NAN, NAN).
func _island_col(isl: PackedFloat32Array, x: float, k: float, nz: Noises) -> Vector2:
	var qx := (x - isl[0]) / isl[3]
	var qk := (k - isl[2]) / isl[4]
	var q := qx * qx + qk * qk
	if isl[10] > 0.0:
		var lx := (x - isl[0] - isl[8]) / (isl[3] * isl[10])
		var lk := (k - isl[2] - isl[9]) / (isl[4] * isl[10])
		q = minf(q, lx * lx + lk * lk)
	if q > 1.35:
		return Vector2(NAN, NAN)
	q += nz.detail.get_noise_2d(x * 1.4 + isl[0], k * 1.4) * 0.28
	if q >= 1.0:
		return Vector2(NAN, NAN)
	var top := isl[1] + (1.0 - q) * (1.6 + isl[3] * 0.12) + nz.hill.get_noise_2d(x * 2.0, k * 2.0) * (0.9 + isl[3] * 0.08)
	var s01 := nz.under.get_noise_2d(x * 1.3 + 50.0, k * 1.3) * 0.5 + 0.5
	var ex := 0.62 if isl[11] < 0.5 else (0.35 if isl[11] < 1.5 else 0.9)
	var bot := isl[1] - isl[5] * pow(1.0 - q, ex) * (0.7 + 0.6 * s01) - 1.0
	return Vector2(floorf(top) + 1.0, bot)

# ------------------------------------------------------------------- P2 3D noise lattice
func _n3_task(gk: int) -> void:
	var nz := Noises.new()
	var out := PackedFloat32Array(); out.resize(_g3x * _g3y)
	var z := -(Z0 + gk * G3)
	for gj in _g3y:
		var y := Y0 + gj * G3
		for gi in _g3x:
			out[gj * _g3x + gi] = nz.cave.get_noise_3d(X0 + gi * G3, y, z)
	_rows[gk] = out

func _n3_at(i: int, j: int, k: int) -> float:
	var gi := i / G3
	var gj := j / G3
	var gk := k / G3
	var tx := float(i - gi * G3) / G3
	var ty := float(j - gj * G3) / G3
	var tk := float(k - gk * G3) / G3
	var sx := 1
	var sy := _g3x
	var sk := _g3x * _g3y
	var o := gk * sk + gj * sy + gi
	var c00 := lerpf(_n3[o], _n3[o + sx], tx)
	var c10 := lerpf(_n3[o + sy], _n3[o + sy + sx], tx)
	var c01 := lerpf(_n3[o + sk], _n3[o + sk + sx], tx)
	var c11 := lerpf(_n3[o + sk + sy], _n3[o + sk + sy + sx], tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tk)

# ------------------------------------------------------------------- P3 fill
func _fill_task(k: int) -> void:
	var nz := Noises.new()
	var buf := PackedByteArray(); buf.resize(NX * NY)
	var z := -(Z0 + k + 0.5)
	var kf := k + 0.5
	var col := PackedByteArray(); col.resize(NY)
	for i in NX:
		var ci := k * NX + i
		var h := _H[ci]
		var b := _B[ci]
		var amp := _AMP[ci]
		var x := X0 + i + 0.5
		var hl := _H[ci - 1] if i > 0 else h
		var hr := _H[ci + 1] if i < NX - 1 else h
		var hf := _H[ci - NX] if k > 0 else h
		var hb := _H[ci + NX] if k < NZ - 1 else h
		var slope := maxf(absf(hr - hl), absf(hb - hf)) * 0.5
		var snow_y := -16.0 + nz.biome.get_noise_2d(x, z) * 6.0
		if h < b:
			var any_isl := false
			for isl: PackedFloat32Array in _islands:
				if absf(x - isl[0]) < isl[3] * 1.2 and absf(kf - isl[2]) < isl[4] * 1.2:
					any_isl = true
			if not any_isl:
				continue
			h = float(Y0) - 10.0
			b = float(Y0) - 11.0
		var jhi := mini(NY - 1, int(floorf(h + amp - Y0)) + 1)
		var jlo := maxi(0, int(floorf(b - Y0)))
		col.fill(0)
		# solid mask (with 3D overhangs in the band around the surface)
		for j in range(jlo, jhi + 1):
			var yc := Y0 + j + 0.5
			if yc <= b:
				continue
			var dens := h - yc
			if amp > 0.5 and absf(dens) < amp:
				dens += amp * _n3_at(i, j, k) * 1.6
			if dens > 0.0:
				col[j] = 1
		# islands
		for isl: PackedFloat32Array in _islands:
			if absf(x - isl[0]) > isl[3] * 1.2 or absf(kf - isl[2]) > isl[4] * 1.2:
				continue
			var tb := _island_col(isl, x, kf, nz)
			if is_nan(tb.x):
				continue
			for j in range(maxi(0, int(floorf(tb.y - Y0))), mini(NY, int(tb.x - Y0))):
				col[j] = 2
		# materials, top-down
		var dep := 0
		var dirt_n := 3 + int(absf(nz.detail.get_noise_2d(x * 2.0, z * 2.0)) * 3.0)
		if slope > 2.0:
			dirt_n = 0 if slope > 3.0 else 1
		var clay := nz.biome.get_noise_2d(x * 3.0 + 99.0, z * 3.0) > 0.58
		var lighter := nz.detail.get_noise_2d(x * 0.7 + 30.0, z * 0.7) > 0.25
		for jj in range(NY - 1, -1, -1):
			if col[jj] == 0:
				dep = 0
				if h < WATER_Y and Y0 + jj + 1 <= WATER_Y and jj >= jlo:
					buf[jj * NX + i] = WATER
				continue
			var yt := Y0 + jj + 1.0   # top of this block
			var id := STONE
			var isl_blk := col[jj] == 2
			if dep == 0:
				if yt <= WATER_Y and not isl_blk:
					id = SAND if (i * 7 + k * 13) % 5 != 0 else GRAVEL
				elif yt <= WATER_Y + 1.5 and not isl_blk:
					id = SAND
				elif yt > snow_y and not isl_blk:
					id = SNOW if slope > 2.2 else SNOW_GRASS
				elif slope > 2.6 and not isl_blk:
					id = STONE
				else:
					id = GRASS
			elif dep <= (2 if isl_blk else dirt_n):
				if yt <= WATER_Y + 1.5 and not isl_blk:
					id = SAND
				elif yt > snow_y + 4.0 and not isl_blk:
					id = STONE
				else:
					id = CLAY if clay else (DIRT_L if lighter else DIRT)
			else:
				var nv := _n3_at(i, jj, k) if (h - yt) < 40.0 else 0.0
				id = STONE_L if nv > 0.45 else (STONE_W if nv < -0.45 else STONE)
			buf[jj * NX + i] = id
			dep += 1
	_slices[k] = buf

# =================================================================== P4 features (serial, member vox)
func _vi(i: int, j: int, k: int) -> int:
	return (k * NY + j) * NX + i

func _vget(i: int, j: int, k: int) -> int:
	if i < 0 or j < 0 or k < 0 or i >= NX or j >= NY or k >= NZ:
		return AIR
	return vox[(k * NY + j) * NX + i]

func _put(i: int, j: int, k: int, id: int, only_air := true) -> void:
	if i < 0 or j < 0 or k < 0 or i >= NX or j >= NY or k >= NZ:
		return
	var p := (k * NY + j) * NX + i
	if only_air and _occ(vox[p]):
		return
	vox[p] = id

## Topmost solid block j of a column (-1 = none), scanning down from `from_j`.
func _top(i: int, k: int, from_j: int) -> int:
	var j := mini(from_j, NY - 1)
	var base := k * NY * NX + i
	while j >= 0:
		if _occ(vox[base + j * NX]):
			return j
		j -= 1
	return -1

func _col_top(i: int, k: int) -> int:
	var ci := k * NX + i
	return _top(i, k, int(_H[ci] + _AMP[ci] - Y0) + 2)

func _stamp_features() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777001
	var nz := Noises.new()
	_island_features(rng)
	_ruins(rng)
	_trees(rng, nz)
	_cliff_falls(rng)
	_plants(rng, nz)
	_clear_depth_volume()

## Keep voxels strictly out of world's depth volume: no block inside or right next to (1 tile, 1 unit behind)
## an extruded level mass, so no voxel face is ever coplanar with / poking through a depth-volume face
## (z-fighting shimmer, e.g. the Eastern Wood).
func _clear_depth_volume() -> void:
	if _dE.is_empty():
		return
	var cleared := 0
	for ty in _dH:
		for tx in W:
			var e := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := tx + dx
					var ny := ty + dy
					if nx >= 0 and ny >= 0 and nx < W and ny < _dH:
						e = maxf(e, _dE[ny * W + nx])
			if e <= 0.0:
				continue
			var i := tx - X0
			var j := -ty - 1 - Y0
			if i < 0 or i >= NX or j < 0 or j >= NY:
				continue
			# voxel k spans z [-(Z0+k+1), -(Z0+k)]; the volume reaches z = -1.2 - e: clear to 1 unit behind it
			var kmax := mini(NZ - 1, int(ceil(1.2 + e + 1.0 - Z0)))
			for k in kmax + 1:
				var p := (k * NY + j) * NX + i
				if vox[p] != AIR:
					vox[p] = AIR
					cleared += 1
	timings["voxel_depth_cleared"] = cleared

func _hmax(i: int, k: int) -> float:
	return _HMAX[k * NX + i]

## Ceiling for trees / ruins: a few blocks under the terrain clearance while still near the plane, so no
## canopy or pillar pokes up behind open gameplay air.
func _feat_max(i: int, k: int) -> float:
	return _HMAX[k * NX + i] - 7.0 * (1.0 - smoothstep(38.0, 72.0, k + 0.5))

# ---- trees
## 1 behind the level's forest regions (WorldForest.RECTS, detail's regions: the Elder Grove, the Eastern
## Wood, ...; widened, soft edges; the volume beyond the level edge continues the edge region), 0 elsewhere.
func _forest_zone(x: float) -> float:
	if _fz.is_empty():
		return 0.0
	return _fz[clampi(int(floorf(x)) - X0, 0, NX - 1)]

func _build_forest_zone(terrain: WorldTerrain) -> void:
	_fz.resize(NX)
	_fz.fill(0.0)
	var bands: Array[Vector3] = []   # x0, x1, soft edge
	for r: Rect2i in WorldForest.RECTS:
		bands.append(Vector3(r.position.x, r.end.x, 26.0))
	# detail's detected forest regions near the surface (e.g. the keep courtyard): smaller soft edge
	for r: Rect2i in WorldForest.regions(terrain):
		if r.position.y < 125 and r.size.x >= 5:
			bands.append(Vector3(r.position.x, r.end.x, 12.0))
	for bd in bands:
		var x0 := bd.x
		var x1 := bd.y
		if x0 <= 0.5:
			x0 = float(X0)          # the forest continues past the level's left edge
		if x1 >= W - 0.5:
			x1 = float(X0 + NX)     # ... and past its right edge
		for i in NX:
			var x := X0 + i + 0.5
			var dout := maxf(x0 - x, x - x1)
			_fz[i] = maxf(_fz[i], 1.0 - smoothstep(-4.0, bd.z, dout))
	_crown_templates(terrain)

## The level's own tree crowns (connected canopy components in the forest bands) as 2D silhouettes, so the
## far forest is built from the same block tree shapes: per row [left, right] spans + the trunk length.
func _crown_templates(terrain: WorldTerrain) -> void:
	var cm := WorldGrass.canopy_map(terrain)
	var W2 := terrain.W
	var H2 := terrain.H
	var seen := PackedByteArray()
	seen.resize(W2 * H2)
	for start in W2 * H2:
		if not cm[start] or seen[start]:
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var c: int = stack.pop_back()
			comp.append(c)
			var cx := c % W2
			var cy := c / W2
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := cx + o.x
				var ny := cy + o.y
				if nx < 0 or ny < 0 or nx >= W2 or ny >= H2:
					continue
				var ni := ny * W2 + nx
				if cm[ni] and not seen[ni]:
					seen[ni] = 1
					stack.append(ni)
		var minx := W2
		var maxx := 0
		var miny := H2
		var maxy := 0
		for c in comp:
			minx = mini(minx, c % W2); maxx = maxi(maxx, c % W2)
			miny = mini(miny, c / W2); maxy = maxi(maxy, c / W2)
		var w := maxx - minx + 1
		var h := maxy - miny + 1
		if w < 4 or w > 22 or h < 3 or h > 16 or comp.size() < 10:
			continue
		var rows := PackedInt32Array()   # per row from the top: left, right (relative), -1 = none
		rows.resize(h * 2)
		rows.fill(-1)
		for c in comp:
			var u := c % W2 - minx
			var v := c / W2 - miny
			if rows[v * 2] < 0 or u < rows[v * 2]:
				rows[v * 2] = u
			rows[v * 2 + 1] = maxi(rows[v * 2 + 1], u)
		# trunk: tiles below the crown's bottom centre down to solid ground
		var bx := (minx + maxx) / 2
		var th := 0
		while maxy + 1 + th < H2 and th < 10 and not (terrain.solid[(maxy + 1 + th) * W2 + bx] and not cm[(maxy + 1 + th) * W2 + bx]):
			th += 1
		_templates.append({"w": w, "h": h, "rows": rows, "trunk": clampi(th, 2, 8)})
	print("WorldVoxel: %d crown templates from the level's trees" % _templates.size())

## A tree stamped from one of the level's own crown silhouettes: each row's span is revolved around the
## trunk into a lumpy disc (depth = 0.75 x its half width), on a trunk of the painted length.
func _template_tree(i: int, j: int, k: int, rng: RandomNumberGenerator, room: float) -> bool:
	if _templates.is_empty():
		return false
	var tpl: Dictionary = _templates[rng.randi_range(0, _templates.size() - 1)]
	var w: int = tpl["w"]
	var h: int = tpl["h"]
	var th: int = tpl["trunk"]
	if room < th + h + 1:
		return false
	var rows: PackedInt32Array = tpl["rows"]
	var flip := rng.randf() < 0.5
	for y in th + 1:
		_put(i, j + y, k, LOG, false)
	var top := j + th + h - 1
	for v in h:
		var a := rows[v * 2]
		var b := rows[v * 2 + 1]
		if a < 0:
			continue
		if flip:
			var na := w - 1 - b
			b = w - 1 - a
			a = na
		var cxr := (a + b) * 0.5
		var r := (b - a + 1) * 0.5
		var rz := maxf(1.0, r * 0.75)
		var rzi := int(ceil(rz))
		for u in range(a, b + 1):
			for dz in range(-rzi, rzi + 1):
				var q := pow((u - cxr) / r, 2.0) + pow(dz / rz, 2.0)
				if q <= 1.0 + rng.randf_range(-0.15, 0.1):
					_leaf(i + u - w / 2, top - v, k + dz, LEAVES)
	return true

func _trees(rng: RandomNumberGenerator, nz: Noises) -> void:
	var cell := 3
	for ck in range(0, NZ, cell):
		for cx in range(0, NX, cell):
			var i := cx + rng.randi_range(0, cell - 1)
			var k := ck + rng.randi_range(0, cell - 1)
			if i >= NX or k >= NZ or k < 18:
				continue
			var f := _FOR[k * NX + i]
			var fz := _forest_zone(X0 + i + 0.5)
			var dens := smoothstep(-0.05, 0.2, f) * 0.55   # clear forests, open meadows between
			dens = maxf(dens, fz * 0.92)                  # continuous canopy behind the level's forests
			if rng.randf() > dens + 0.01:
				continue
			var j := _col_top(i, k)
			if j < 0 or _vget(i, j, k) != GRASS and _vget(i, j, k) != SNOW_GRASS:
				continue
			var y := Y0 + j + 1.0
			var room := _feat_max(i, k) - y
			# the level's trees are round leaf-cluster crowns: mostly crown trees, pines only up high
			var pine := (y > -62.0 + f * 12.0 and fz < 0.5) or _vget(i, j, k) == SNOW_GRASS or (fz > 0.5 and rng.randf() < 0.12)
			if pine:
				var ph := rng.randi_range(7, 12)
				if room < ph + 1:
					continue
				_pine(i, j + 1, k, ph, rng)
			elif rng.randf() < 0.12 and room > 14.0:
				_big_oak(i, j + 1, k, rng)
			else:
				var th := rng.randi_range(3, 6)
				if room < th + 6:
					continue
				if not _template_tree(i, j + 1, k, rng, room):
					_crown_tree(i, j + 1, k, th, rng)

## A round leaf-cluster crown (2-4 overlapping lumpy spheres) on a short trunk, like the level's trees.
func _crown_tree(i: int, j: int, k: int, h: int, rng: RandomNumberGenerator) -> void:
	for y in h + 1:
		_put(i, j + y, k, LOG, false)
	var R := rng.randf_range(2.4, 3.6)
	var cy := j + h + int(R * 0.7)
	var blobs: Array[Vector4] = [Vector4(0, 0, 0, R)]
	for _b in rng.randi_range(1, 3):
		blobs.append(Vector4(rng.randf_range(-R, R) * 0.7, rng.randf_range(-0.6, 0.5) * R, rng.randf_range(-R, R) * 0.5, R * rng.randf_range(0.6, 0.85)))
	for bl: Vector4 in blobs:
		var ri := int(ceil(bl.w)) + 1
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				for dk in range(-ri, ri + 1):
					var d := Vector3(dx - bl.x, (dy - bl.y) * 1.15, dk - bl.z).length()
					if d <= bl.w + rng.randf_range(-0.35, 0.2):
						_leaf(i + dx, cy + dy, k + dk, LEAVES)

func _leaf(i: int, j: int, k: int, id: int) -> void:
	_put(i, j, k, id, true)

func _oak(i: int, j: int, k: int, h: int, rng: RandomNumberGenerator) -> void:
	for y in h:
		_put(i, j + y, k, LOG, false)
	var tj := j + h
	for dy in range(-2, 2):
		var r := 2 if dy < 0 else 1
		for dx in range(-r, r + 1):
			for dk in range(-r, r + 1):
				var corner := absi(dx) == r and absi(dk) == r
				if corner and (dy == 1 or rng.randf() < 0.5):
					continue
				if dx == 0 and dk == 0 and dy < 0:
					continue
				_leaf(i + dx, tj + dy, k + dk, LEAVES)
	_leaf(i, tj + 1, k, LEAVES)

func _pine(i: int, j: int, k: int, h: int, rng: RandomNumberGenerator) -> void:
	for y in h:
		_put(i, j + y, k, PINE_LOG, false)
	var start := 2 + rng.randi_range(0, 1)
	for y in range(start, h + 1):
		var t := float(h - y) / float(h - start)
		var r := int(round(t * 2.6))
		if (y - start) % 2 == 1:
			r = maxi(r - 1, 0)
		for dx in range(-r, r + 1):
			for dk in range(-r, r + 1):
				if absi(dx) + absi(dk) > r + (1 if r >= 2 else 0):
					continue
				if dx == 0 and dk == 0 and y < h:
					continue
				_leaf(i + dx, j + y, k + dk, PINE)
	_leaf(i, j + h + 1, k, PINE)

func _big_oak(i: int, j: int, k: int, rng: RandomNumberGenerator) -> void:
	var h := rng.randi_range(8, 11)
	for y in h:
		for d in 4:
			_put(i + d % 2, j + y, k + d / 2, LOG, false)
	# roots
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, -1)]:
		_put(i + d.x, j, k + d.y, LOG, false)
	var blobs := [Vector3(0.5, h + 0.5, 0.5)]
	for _b in 3:
		blobs.append(Vector3(0.5 + rng.randf_range(-3.5, 3.5), h - rng.randf_range(1.0, 3.5), 0.5 + rng.randf_range(-2.5, 2.5)))
	for bl: Vector3 in blobs:
		var r := 3.6 if bl == blobs[0] else 2.6
		var ri := int(ceil(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				for dk in range(-ri, ri + 1):
					var p := Vector3(dx, dy * 1.25, dk)
					if p.length() <= r + rng.randf_range(-0.4, 0.3):
						_leaf(i + int(floorf(bl.x)) + dx, j + int(floorf(bl.y)) + dy, k + int(floorf(bl.z)) + dk, LEAVES)
		# branch to the blob
		var steps := 6
		for s in steps:
			var p := Vector3(0.5, h - 3.0, 0.5).lerp(bl, float(s) / steps)
			_put(i + int(floorf(p.x)), j + int(floorf(p.y)), k + int(floorf(p.z)), LOG, false)

# ---- islands: ruins on top, waterfalls off the front edge
func _island_features(rng: RandomNumberGenerator) -> void:
	for isl: PackedFloat32Array in _islands:
		var ci := int(isl[0] - X0)
		var ck := int(isl[2])
		if isl[7] > 0.5:
			var ox := ci + rng.randi_range(-int(isl[3] * 0.3), int(isl[3] * 0.3))
			var j := _top(ox, ck, NY - 1)
			if j > 0:
				_ruin_at(ox, j + 1, ck, rng.randi_range(0, 3), rng, 22.0)
		if isl[6] > 0.5:
			var fx := ci + rng.randi_range(-int(isl[3] * 0.35), int(isl[3] * 0.35))
			# front edge: the smallest k with island blocks at this x
			var kk := ck
			while kk > 0 and _top(fx, kk - 1, int(isl[1] - Y0) + 3) > int(isl[1] - isl[5] - Y0) - 2:
				kk -= 1
			var jt := _top(fx, kk, int(isl[1] - Y0) + 3)
			if jt < 0:
				continue
			for w in 2:
				# channel through the island top, then the falling column in front of the edge
				for dk in range(0, 4):
					_put(fx + w, jt, kk + dk, WATER, false)
				var jb := maxi(_top(fx + w, kk - 1, jt - 1), jt - FALL_MAX)
				for j in range(maxi(jb + 1, 0), jt + 1):
					_put(fx + w, j, kk - 1, WATER_MIST if j < jb + 8 and jb == jt - FALL_MAX else WATER, true)
		# a few trees on the island
		for _t in int(isl[3] * 0.4):
			var ti := ci + rng.randi_range(-int(isl[3] * 0.6), int(isl[3] * 0.6))
			var tk := ck + rng.randi_range(-int(isl[4] * 0.5), int(isl[4] * 0.5))
			var j := _top(ti, tk, int(isl[1] - Y0) + 3)
			if j < 0 or _vget(ti, j, tk) != GRASS:
				continue
			if rng.randf() < 0.5:
				_oak(ti, j + 1, tk, rng.randi_range(4, 5), rng)
			else:
				_pine(ti, j + 1, tk, rng.randi_range(6, 9), rng)

# ---- ruins scattered on flat ground
func _ruins(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 3000:
		tries += 1
		var i := rng.randi_range(4, NX - 5)
		var k := rng.randi_range(26, NZ - 6)
		var ci := k * NX + i
		if _AMP[ci] > 0.5:
			continue
		var h := _H[ci]
		var flat := true
		for o: Vector2i in [Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -3), Vector2i(0, 3)]:
			if absf(_H[(k + o.y) * NX + i + o.x] - h) > 1.6:
				flat = false
		if not flat or h <= WATER_Y + 1:
			continue
		var j := _col_top(i, k)
		if j < 0 or _vget(i, j, k) != GRASS:
			continue
		if _ruin_at(i, j + 1, k, rng.randi_range(0, 3), rng, _feat_max(i, k) - (Y0 + j + 1.0)):
			placed += 1

## type 0 = pillar group, 1 = arch, 2 = broken wall, 3 = shrine plinth with columns. Returns false if no room.
func _ruin_at(i: int, j: int, k: int, kind: int, rng: RandomNumberGenerator, room: float) -> bool:
	if room < 6.0:
		return false
	var hmax := int(minf(room - 1.0, 12.0))
	match kind:
		0:
			for p in rng.randi_range(1, 3):
				var pi := i + rng.randi_range(-4, 4)
				var pk := k + rng.randi_range(-2, 2)
				var pj := _top(pi, pk, j + 3) + 1
				var ph := rng.randi_range(3, hmax)
				for y in ph:
					_put(pi, pj + y, pk, RUIN, false)
				_put(pi, pj + ph, pk, RUIN_MOSS if rng.randf() < 0.6 else RUIN, false)
				# plinth
				for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					if rng.randf() < 0.7:
						_put(pi + d.x, pj, pk + d.y, RUIN, false)
				# fallen drum
				if rng.randf() < 0.5:
					_put(pi + rng.randi_range(2, 3), pj, pk + rng.randi_range(-1, 1), RUIN_MOSS, false)
		1:
			var span := rng.randi_range(3, 5)
			var ph := clampi(rng.randi_range(5, 8), 4, hmax - 1)
			var broken := rng.randf() < 0.5
			for side: int in [-1, 1]:
				var px := i + side * (span / 2 + 1)
				var pj := _top(px, k, j + 3) + 1
				var top := j + ph
				for y in range(pj, top):
					_put(px, y, k, RUIN, false)
					if y - pj < 2:
						_put(px, y, k + 1, RUIN, false)
			for dx in range(-(span / 2 + 1), span / 2 + 2):
				if broken and dx > span / 4:
					continue
				_put(i + dx, j + ph, k, RUIN_MOSS if rng.randf() < 0.35 else RUIN, false)
				if absi(dx) >= span / 2:
					_put(i + dx, j + ph - 1, k, RUIN, false)
		2:
			var ln := rng.randi_range(6, 12)
			var wh := clampi(rng.randi_range(3, 6), 2, hmax)
			var x0 := i - ln / 2
			for dx in ln:
				var cj := _top(x0 + dx, k, j + 3) + 1
				var ch := wh - int(absf(sin(dx * 1.7 + rng.randf() * 3.0)) * wh * 0.8)
				for y in ch:
					if y == wh / 2 and dx % 4 == 2:
						continue   # window
					_put(x0 + dx, cj + y, k, RUIN, false)
				if ch > 0:
					_put(x0 + dx, cj + ch - 1, k, RUIN_MOSS if rng.randf() < 0.5 else RUIN, false)
		3:
			for dx in range(-3, 4):
				for dk in range(-2, 3):
					_put(i + dx, j, k + dk, RUIN, false)
			var ch := clampi(rng.randi_range(4, 7), 3, hmax - 1)
			for c: Vector2i in [Vector2i(-3, -2), Vector2i(3, -2), Vector2i(-3, 2), Vector2i(3, 2)]:
				var cc: Vector2i = c
				var hh := ch - (rng.randi_range(0, ch - 1) if rng.randf() < 0.4 else 0)
				for y in range(1, hh + 1):
					_put(i + cc.x, j + y, k + cc.y, RUIN, false)
	return true

# ---- waterfalls down cliffs that face the camera
func _cliff_falls(rng: RandomNumberGenerator) -> void:
	var made := 0
	var tries := 0
	while made < 9 and tries < 4000:
		tries += 1
		var i := rng.randi_range(2, NX - 4)
		var k := rng.randi_range(34, NZ - 8)
		var ci := k * NX + i
		var h := _H[ci]
		# the ground in front (toward the camera) drops by a cliff
		var kf := k - 1
		while kf > 20 and _H[kf * NX + i] > h - 2.0:
			kf -= 1
		var drop := h - _H[kf * NX + i]
		if drop < 7.0 or drop > 30.0 or _AMP[ci] > 0.5:
			continue
		var jt := _col_top(i, k)
		if jt < 0 or _vget(i, jt, k) != GRASS:
			continue
		for w in 2:
			for dk in range(0, 6):
				var jj := _col_top(i + w, k + dk)
				if jj == jt:
					_put(i + w, jj, k + dk, WATER, false)
			for kk in range(kf + 1, k):
				# the water pours over the edge rows
				var jj := _col_top(i + w, kk)
				if jj >= jt - 1:
					_put(i + w, jt, kk, WATER, false)
			var jb := _col_top(i + w, kf)
			for j in range(jb + 1, jt + 1):
				_put(i + w, j, kf, WATER, true)
			_put(i + w, jb, kf, WATER, false)
		made += 1

# ---- tall grass, flowers, ferns, bushes
func _plants(rng: RandomNumberGenerator, nz: Noises) -> void:
	for k in range(12, PLANT_K):
		for i in NX:
			var j := _col_top(i, k)
			if j < 0 or j >= NY - 2 or _vget(i, j, k) != GRASS or _vget(i, j + 1, k) != AIR:
				continue
			var fl := nz.biome.get_noise_2d(i * 0.9, k * 0.9)
			var r := rng.randf()
			var y := Y0 + j + 1.0
			if y + 1.0 > _hmax(i, k):
				continue
			if r < 0.018 and y + 2.0 <= _feat_max(i, k):
				_put(i, j + 1, k, LEAVES, false)
				if rng.randf() < 0.3:
					_put(i + 1, j + 1, k, LEAVES, false)
			elif r < 0.06 + maxf(fl, 0.0) * 0.12:
				var c := rng.randf()
				_put(i, j + 1, k, FLOWER_R if c < 0.4 else (FLOWER_Y if c < 0.75 else FLOWER_B), false)
			elif r < 0.34:
				_put(i, j + 1, k, FERN if _FOR[k * NX + i] > 0.15 and rng.randf() < 0.5 else TALLGRASS, false)

# =================================================================== P5 meshing
func _mesh_task(c: int) -> void:
	if _abort:
		return
	var ncx := NX / CHX
	var ncy := NY / CHY
	var i0 := (c % ncx) * CHX
	var j0 := ((c / ncx) % ncy) * CHY
	var k0 := (c / (ncx * ncy)) * CHK
	var j1 := j0 + CHY
	var ob := Buf.new()
	var wb := Buf.new()
	var pb := Buf.new()
	var sy := NX
	var sk := NX * NY
	for k in range(k0, k0 + CHK):
		var zf := -float(Z0 + k)
		for i in range(i0, i0 + CHX):
			var x := float(X0 + i)
			var colb := k * sk + i
			# open vertical runs (start j, -1 = none): opaque +x, -x, +z and water +x, -x, +z
			var r0 := -1
			var r1 := -1
			var r2 := -1
			var w0 := -1
			var w1 := -1
			var w2 := -1
			for j in range(j0, j1 + 1):
				var e0 := false
				var e1 := false
				var e2 := false
				var f0 := false
				var f1 := false
				var f2 := false
				if j < j1:
					var p := colb + j * sy
					var id := vox[p]
					if id != 0:
						var npx := vox[p + 1] if i < NX - 1 else STONE
						var nnx := vox[p - 1] if i > 0 else STONE
						var nfz := vox[p - sk] if k > 0 else AIR
						var up := vox[p + sy] if j < NY - 1 else AIR
						if id < 64:
							e0 = npx == 0 or npx > 63
							e1 = nnx == 0 or nnx > 63
							e2 = nfz == 0 or nfz > 63
							if up == 0 or up > 63:
								_quad(ob, Vector3(x, Y0 + j + 1.0, zf), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
							var dn := vox[p - sy] if j > 0 else STONE
							if dn == 0 or dn > 63:
								_quad(ob, Vector3(x, float(Y0 + j), zf), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
						elif id < TALLGRASS:
							f0 = npx == 0 or npx >= TALLGRASS
							f1 = nnx == 0 or nnx >= TALLGRASS
							f2 = nfz == 0 or nfz >= TALLGRASS
							if up == 0 or up >= TALLGRASS:
								_quad(wb, Vector3(x, Y0 + j + 0.88, zf), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
						elif k < PLANT_K:
							_plant(pb, x, float(Y0 + j), zf, id, (i * 73856093) ^ (k * 19349663))
				if e0 != (r0 >= 0):
					if e0: r0 = j
					else:
						_side(ob, 0, r0, j, x, zf); r0 = -1
				if e1 != (r1 >= 0):
					if e1: r1 = j
					else:
						_side(ob, 1, r1, j, x, zf); r1 = -1
				if e2 != (r2 >= 0):
					if e2: r2 = j
					else:
						_side(ob, 2, r2, j, x, zf); r2 = -1
				if f0 != (w0 >= 0):
					if f0: w0 = j
					else:
						_side(wb, 0, w0, j, x, zf); w0 = -1
				if f1 != (w1 >= 0):
					if f1: w1 = j
					else:
						_side(wb, 1, w1, j, x, zf); w1 = -1
				if f2 != (w2 >= 0):
					if f2: w2 = j
					else:
						_side(wb, 2, w2, j, x, zf); w2 = -1
	_chunks[c] = [ob, wb, pb]

## A vertical run of side faces from row ja (inclusive) to jb (exclusive). d: 0 = +x, 1 = -x, 2 = +z.
func _side(b: Buf, d: int, ja: int, jb: int, x: float, zf: float) -> void:
	var y0 := float(Y0 + ja)
	var hh := float(jb - ja)
	if d == 0:
		_quad(b, Vector3(x + 1.0, y0, zf), Vector3(0, hh, 0), Vector3(0, 0, -1), Vector3(1, 0, 0))
	elif d == 1:
		_quad(b, Vector3(x, y0, zf), Vector3(0, hh, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
	else:
		_quad(b, Vector3(x, y0, zf), Vector3(1, 0, 0), Vector3(0, hh, 0), Vector3(0, 0, 1))

func _quad(b: Buf, o: Vector3, du: Vector3, dv: Vector3, n: Vector3) -> void:
	var base := b.v.size()
	b.v.append(o)
	b.v.append(o + du)
	b.v.append(o + du + dv)
	b.v.append(o + dv)
	b.n.append(n)
	b.n.append(n)
	b.n.append(n)
	b.n.append(n)
	var fl := du.cross(dv).dot(n) > 0.0
	b.idx.append(base)
	b.idx.append(base + (2 if fl else 1))
	b.idx.append(base + (1 if fl else 2))
	b.idx.append(base)
	b.idx.append(base + (3 if fl else 2))
	b.idx.append(base + (2 if fl else 3))

## Two crossed quads (double-sided in the shader). UV2 = (plant id, random 0..1).
func _plant(b: Buf, x: float, y: float, zf: float, id: int, seed_v: int) -> void:
	var rnd := float(absi(seed_v) % 1000) / 1000.0
	var hgt := 0.9 if id == TALLGRASS else (1.0 if id == FERN else 0.8)
	hgt *= 0.8 + 0.4 * rnd
	var ins := 0.12
	var diag := [[Vector3(x + ins, y, zf - ins), Vector3(x + 1.0 - ins, y, zf - 1.0 + ins)],
		[Vector3(x + 1.0 - ins, y, zf - ins), Vector3(x + ins, y, zf - 1.0 + ins)]]
	for dg: Array in diag:
		var a: Vector3 = dg[0]
		var e: Vector3 = dg[1]
		var base := b.v.size()
		b.v.append_array([a, e, e + Vector3(0, hgt, 0), a + Vector3(0, hgt, 0)])
		for _q in 4:
			b.n.append(Vector3(0, 1, 0))
			b.uv2.append(Vector2(float(id), rnd))
		b.uv.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		b.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

# =================================================================== main thread: upload + fade
func _on_generated() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	var t0 := Time.get_ticks_msec()
	if fore:
		fore.upload(sun_dir)
	timings["voxel_materials_main"] = Time.get_ticks_msec() - t0
	_upload_i = 0
	_uploading = true
	set_process(true)

func _make_materials() -> void:
	material = ShaderMaterial.new()
	material.shader = _sh_block
	WorldPbr.bind(material, false, 1.0)
	# same detail textures as the level's blocks (world's depth volume), and an empty canopy mask
	if _terrain_mat:
		for k in ["detail_nrm2", "detail_hgt"]:
			material.set_shader_parameter(k, _terrain_mat.get_shader_parameter(k))
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	material.set_shader_parameter("pbr_canopy_tex", ImageTexture.create_from_image(blank))
	material.set_shader_parameter("pbr_level_size", Vector2(1, 1))
	water_material = ShaderMaterial.new()
	water_material.shader = _sh_water
	plant_material = ShaderMaterial.new()
	plant_material.shader = _sh_plant
	var cols := PackedVector3Array()
	cols.resize(N_SOLID)
	for id in N_SOLID:
		cols[id] = Vector3(_lin_cols[id].r, _lin_cols[id].g, _lin_cols[id].b)
	var g2 := _grass_b if _grass_b.r >= 0.0 else _pal(19, Color8(67, 131, 16)).srgb_to_linear()
	var wa := _pal(54, Color8(126, 153, 246)).srgb_to_linear()
	var wd := _pal(10, Color8(53, 82, 168)).srgb_to_linear()
	var htex: ImageTexture = null
	if _hollow_img and not _hollow_img.is_empty():
		htex = ImageTexture.create_from_image(_hollow_img)
	for m: ShaderMaterial in [material, water_material, plant_material]:
		if htex:
			m.set_shader_parameter("forest_tex", htex)
			m.set_shader_parameter("has_forest", 1.0)
			m.set_shader_parameter("forest_size", Vector2(_hollow_img.get_width(), _hollow_img.get_height()))
		m.set_shader_parameter("vol", vol_tex)
		m.set_shader_parameter("vol_origin", Vector3(X0, Y0, Z0))
		m.set_shader_parameter("vol_size", Vector3i(NX, NY, NZ))
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("fade", 0.0)
	material.set_shader_parameter("blk_col", cols)
	material.set_shader_parameter("grass_b", Vector3(g2.r, g2.g, g2.b))
	water_material.set_shader_parameter("water_a", Vector3(wa.r, wa.g, wa.b))
	water_material.set_shader_parameter("water_d", Vector3(wd.r, wd.g, wd.b))
	plant_material.set_shader_parameter("grass_col", cols[GRASS])
	plant_material.set_shader_parameter("grass_b", Vector3(g2.r, g2.g, g2.b))

## Block colours = what the level's own blocks use: the average painted (fgcol) colour of the level's tiles
## per material class (grass tops, earth, ruin stone, foliage, wood, sand), linear. Falls back to the palette.
func _level_colors(terrain: WorldTerrain) -> void:
	var img := terrain.fgcol_img
	if img == null:
		return
	var sums := {}
	var W2 := terrain.W
	for y in terrain.H:
		for x in W2:
			var i := y * W2 + x
			if not terrain.solid[i]:
				continue
			var m: int = terrain.mat_ids[i]
			var key := m
			if m == WorldPalette.M_GRASS and (y == 0 or terrain.solid[i - W2]):
				continue   # only lawn TOPS count as grass
			var c := img.get_pixel(x, y).srgb_to_linear()
			if not sums.has(key):
				sums[key] = [Color(0, 0, 0, 0), 0]
			var e: Array = sums[key]
			e[0] = (e[0] as Color) + c
			e[1] = int(e[1]) + 1
	var avg := func(m: int) -> Color:
		if not sums.has(m) or int(sums[m][1]) < 20:
			return Color(-1, 0, 0)
		var e: Array = sums[m]
		var c: Color = e[0]
		var nn := float(e[1])
		return Color(c.r / nn, c.g / nn, c.b / nn)
	var g: Color = avg.call(WorldPalette.M_GRASS)
	var ea: Color = avg.call(WorldPalette.M_EARTH)
	var ru: Color = avg.call(WorldPalette.M_RUIN)
	var fo: Color = avg.call(WorldPalette.M_FOLIAGE)
	var wo: Color = avg.call(WorldPalette.M_WOOD)
	var sa: Color = avg.call(WorldPalette.M_SAND)
	if g.r >= 0.0:
		_lin_cols[GRASS] = g
		_grass_b = g * Color(0.8, 1.05, 0.7)
	if ea.r >= 0.0:
		_lin_cols[DIRT] = ea
		_lin_cols[DIRT_L] = ea * 1.15
		_lin_cols[CLAY] = ea * Color(1.05, 0.9, 0.8)
	if ru.r >= 0.0:
		_lin_cols[RUIN] = ru
		_lin_cols[RUIN_MOSS] = ru
		_lin_cols[STONE] = ru
		_lin_cols[STONE_W] = ru * Color(1.0, 0.97, 0.9)
		_lin_cols[STONE_L] = ru * 1.15
		_lin_cols[GRAVEL] = ru * 0.9
	if fo.r >= 0.0:
		_lin_cols[LEAVES] = fo.lerp(_pal(14, Color8(66, 168, 54)).srgb_to_linear(), 0.1)
		_lin_cols[PINE] = fo * Color(0.6, 0.75, 0.7)
	if wo.r >= 0.0:
		_lin_cols[LOG] = wo
		_lin_cols[PINE_LOG] = wo * 0.8
	if sa.r >= 0.0:
		_lin_cols[SAND] = sa
	print("WorldVoxel level colours: grass %s earth %s ruin %s foliage %s wood %s" % [g, ea, ru, fo, wo])

## Block colours (sRGB) from the level palette.
func _color_table() -> Dictionary:
	return {
		GRASS: _pal(35, Color8(69, 99, 19)), DIRT: _pal(45, Color8(114, 97, 75)), DIRT_L: _pal(47, Color8(142, 115, 79)),
		CLAY: _pal(48, Color8(127, 79, 43)).lerp(_pal(45, Color8(114, 97, 75)), 0.45), STONE: _pal(9, Color8(110, 110, 110)), STONE_W: _pal(46, Color8(110, 107, 96)),
		STONE_L: _pal(86, Color8(134, 134, 134)), SAND: _pal(88, Color8(108, 79, 44)).lerp(Color8(196, 170, 120), 0.45),
		SNOW: Color8(236, 242, 250), SNOW_GRASS: Color8(228, 236, 246), LOG: Color8(78, 56, 38),
		LEAVES: _pal(14, Color8(66, 168, 54)), PINE: _pal(19, Color8(67, 131, 16)).lerp(Color8(24, 60, 30), 0.5),
		RUIN: _pal(42, Color8(153, 153, 153)).lerp(_pal(9, Color8(110, 110, 110)), 0.5), RUIN_MOSS: Color8(96, 118, 62),
		GRAVEL: _pal(46, Color8(110, 107, 96)), PINE_LOG: _pal(48, Color8(127, 79, 43)).lerp(Color8(62, 44, 30), 0.7),
	}

func _process(delta: float) -> void:
	if _uploading:
		var t0 := Time.get_ticks_usec()
		var n := 0
		while _upload_i < _chunks.size() and n < UPLOADS_PER_FRAME:
			_upload_chunk(_upload_i)
			_upload_i += 1
			n += 1
		timings["voxel_upload_us"] = int(timings.get("voxel_upload_us", 0)) + Time.get_ticks_usec() - t0
		if _upload_i >= _chunks.size():
			_uploading = false
			_chunks.clear()
			_fade_t = 0.0
			is_ready = true
			print("WorldVoxel ready: %d faces, %d islands %s" % [face_count, _islands.size(), str(timings)])
			finished.emit()
		return
	if _fade_t >= 0.0:
		_fade_t += delta
		var f := smoothstep(0.0, 1.0, _fade_t / FADE_TIME)
		for m: ShaderMaterial in [material, water_material, plant_material]:
			m.set_shader_parameter("fade", f)
		if fore:
			fore.set_fade(f)
		if _fade_t >= FADE_TIME:
			_fade_t = -1.0
	if fore:
		fore.fallback_from_camera(get_viewport().get_camera_3d())

## WorldView.update_focus(): the ball's interpolated world centre (keeps the foreground clear around it).
func update_focus(world_pos: Vector3, _delta: float) -> void:
	if fore:
		fore.set_ball(world_pos)

## Tests: skip the fade.
func finish_fade() -> void:
	_fade_t = FADE_TIME - 0.001

func _upload_chunk(c: int) -> void:
	var parts: Array = _chunks[c]
	if parts.is_empty():
		return
	var ncx := NX / CHX
	var ncy := NY / CHY
	var cki := c / (ncx * ncy)
	var mats: Array[ShaderMaterial] = [material, water_material, plant_material]
	for p in 3:
		var b: Buf = parts[p]
		if b.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.v
		arr[Mesh.ARRAY_NORMAL] = b.n
		if not b.uv.is_empty():
			arr[Mesh.ARRAY_TEX_UV] = b.uv
			arr[Mesh.ARRAY_TEX_UV2] = b.uv2
		arr[Mesh.ARRAY_INDEX] = b.idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mats[p]
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (p == 0 and cki * CHK < SHADOW_K) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Vox%d_%d" % [c, p]
		add_child(mi)
		if p == 0:
			face_count += b.idx.size() / 6

# =================================================================== queries (tests / other modules)
## Block id at a world position (AIR outside the volume).
func block_at(p: Vector3) -> int:
	if vox.is_empty():
		return AIR
	return _vget(int(floorf(p.x - X0)), int(floorf(p.y - Y0)), int(floorf(-p.z - Z0)))

## Surface height of the voxel terrain at world (x, z) (NAN outside the volume / before the build).
func height_at(x: float, z: float) -> float:
	var i := int(floorf(x - X0))
	var k := int(floorf(-z - Z0))
	if _H.is_empty() or i < 0 or i >= NX or k < 0 or k >= NZ:
		return NAN
	return _H[k * NX + i]
