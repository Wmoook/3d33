class_name WorldVista
extends Node3D
## Day levels: a physically consistent, WORLD-ANCHORED 3D vista behind the level (z < -25), so perspective
## parallax happens naturally and the scenery is where it logically must be:
## - the level's own ground profile (derived from the sky mask: the valley floor the spires stand on, the
##   left massif, the right plateau) continues into the distance as a smooth heightfield: forested hills,
##   meadows and the waterfall's river winding away across the valley floor (y = FLOOR_Y);
## - a few distant hazy ruin spires of the same architecture standing on that ground;
## - a raymarched CLOUD SEA filling the valleys beyond (the high ruins, the scroll and the logo float above
##   it), plus puffy cumulus at world heights (some above the spire tops);
## - snowy mountain ranges rising out of the cloud sea far behind (z -380 .. -835);
## - the sky dome (day_sky.gdshader) and all vista materials share one sky/haze model (vista_common), so
##   aerial perspective melts every far layer into the sky. Unshaded, no shadows, one draw per layer.
## Usage (WorldView, day levels only): vista.build(level, sun_dir, sky_mat); each frame
## vista.update(camera_world_pos).

const FLOOR_Y := -172.0          # the valley floor / pool level under the spires and the falls (world y)
const NEAR_Z := -26.0            # first row of the landscape, just behind the level's deepest layers
const MID_Z := -250.0            # home island mesh / far range seam
const FAR_Z := -835.0            # camera.far is 900 and the camera sits at z <= +60
const UNDER_Y := -420.0         # island undersides / the world far below, hidden under the cloud sea
const PEAK_FLOOR_Y := -330.0     # base of the far ranges (under the clouds)
const CLOUD_BASE := -236.0       # cloud sea below the level's lower edge (level spans y -200..0)
const CLOUD_NEAR_Z := -12.0

var sun_dir := Vector3(-0.30, 0.67, 0.68)
var noise_tex: ImageTexture
var timings := {}
var ground := PackedFloat32Array()   # level ground profile: world y per level column (smoothed envelope)
var _W := 400
var _mats: Array[ShaderMaterial] = []
var _fn_hill := FastNoiseLite.new()
var _fn_forest := FastNoiseLite.new()
var _fn_ridge := FastNoiseLite.new()
var _fn_big := FastNoiseLite.new()
var _fn_mass := FastNoiseLite.new()
var _land_near: MeshInstance3D
var _land_far: MeshInstance3D
var _clouds: MeshInstance3D
var _pines: Array[Transform3D] = []
var _pine_c: Array[Color] = []
var _broad: Array[Transform3D] = []
var _broad_c: Array[Color] = []
var _seam_h := PackedFloat32Array()   # world's depth continuation back edge (WorldDepth.depth_seam)
var _seam_c := PackedColorArray()
var _seam_z := -26.0
## Foreground handoff: when another layer (the voxel landscape) owns the space in front, set this BEFORE
## build() to its back depth (e.g. -90): the vista then starts behind it (no home-island top, midground
## islands or low cloud banks in front of it, no depth seam) and only keeps its far layers.
var near_limit := NEAR_Z
## false: skip the home island's keel/roots/falls under the level (a foreground layer brings its own).
var keel_enabled := true
var _vcount := {}                   # SurfaceTool instance id -> vertices added (indexed islands)
var _ruin_sites: Array = []          # [x, ground_y, z, height, width] ruins standing on island tops

## sky_ids: background ids that paint the open sky in this level (FV: 531 pastel sky, 540 clouds/snow).
func build(lvl: EELevel, sun: Vector3 = Vector3.ZERO, sky_mat: ShaderMaterial = null, sky_ids: Array = [531, 540]) -> void:
	var t := Time.get_ticks_msec()
	if sun.length() > 0.01:
		sun_dir = sun.normalized()
	_W = lvl.width
	_setup_noise()
	_make_profile(lvl, sky_ids)
	timings["vista_profile"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	if near_limit < NEAR_Z - 1.0:
		_seam_h = PackedFloat32Array()
	_land_near = _land_mesh("VistaLandNear", -150.0, 560.0, 2.0, near_limit, MID_Z, 1.4, 0.012, true)
	_land_far = _land_mesh("VistaLandFar", -560.0, 960.0, 4.0, MID_Z + 6.0, FAR_Z, 4.0, 0.0, false)
	timings["vista_land"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	_make_islands()
	_make_block_pieces()
	if keel_enabled:
		_make_home_keel()
	_make_trees()
	_make_ruins()
	_make_cumulus()
	_make_cloud_sea()
	timings["vista_props"] = Time.get_ticks_msec() - t
	if sky_mat:
		sky_mat.set_shader_parameter("sun_dir", sun_dir)
		sky_mat.set_shader_parameter("noise_tex", noise_tex)
		sky_mat.set_shader_parameter("has_noise", 1.0)
		sky_mat.set_shader_parameter("cloud_base", CLOUD_BASE)
	print("WorldVista built %s" % str(timings))
	_build_pieces_deferred()

## Per frame (camera world position). The vista is world-anchored, so nothing moves; this only hides it
## when no sky can be visible (sky_visibility 0 = deep underground), which also skips the cloud march.
func update(_camera_pos: Vector3, sky_visibility: float = 1.0) -> void:
	visible = sky_visibility > 0.001

## World's depth continuation (WorldDepth.depth_seam()): {z, height (world y per column, NAN = none),
## color (sRGB)}. Call BEFORE build(): the vista's front row then continues those hillsides exactly.
func set_depth_seam(seam: Dictionary) -> void:
	_seam_z = float(seam.get("z", -26.0))
	_seam_h = seam.get("height", PackedFloat32Array())
	_seam_c = seam.get("color", PackedColorArray())

## Seam height at column x (averaged over valid neighbours) or NAN, and its colour.
func _seam_at(x: float) -> Array:
	if _seam_h.is_empty():
		return [NAN, Color()]
	var xi := int(floor(x))
	var sh := 0.0
	var sw := 0.0
	var sc := Color(0, 0, 0)
	for dx in range(-2, 3):
		var j := xi + dx
		if j < 0 or j >= _seam_h.size() or is_nan(_seam_h[j]):
			continue
		var wgt := 1.0 / (1.0 + absf(x - (j + 0.5)))
		sh += _seam_h[j] * wgt
		sc += _seam_c[j] * wgt
		sw += wgt
	if sw < 0.3:
		return [NAN, Color()]
	return [sh / sw, sc / sw]

func set_sun_dir(d: Vector3) -> void:
	sun_dir = d.normalized()
	for m in _mats:
		m.set_shader_parameter("sun_dir", sun_dir)

# ------------------------------------------------------------------ noise
func _setup_noise() -> void:
	_fn_hill.seed = 11
	_fn_hill.frequency = 0.011
	_fn_hill.fractal_octaves = 4
	_fn_forest.seed = 23
	_fn_forest.frequency = 0.02
	_fn_forest.fractal_octaves = 3
	_fn_ridge.seed = 37
	_fn_ridge.frequency = 0.0034
	_fn_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_fn_ridge.fractal_octaves = 4
	_fn_ridge.fractal_gain = 0.5
	_fn_big.seed = 41
	_fn_big.frequency = 0.0022
	_fn_big.fractal_octaves = 2
	_fn_mass.seed = 53
	_fn_mass.frequency = 0.0028
	_fn_mass.fractal_octaves = 3
	# RGB tileable fbm texture shared by every vista shader (and the sky's cirrus)
	var chans := []
	for k in 3:
		var fn := FastNoiseLite.new()
		fn.seed = 101 + k * 17
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = [0.012, 0.02, 0.03][k]
		fn.fractal_octaves = 5
		var img := fn.get_seamless_image(256, 256, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var buf := PackedByteArray()
	buf.resize(256 * 256 * 3)
	var r: PackedByteArray = chans[0]
	var g: PackedByteArray = chans[1]
	var b: PackedByteArray = chans[2]
	for i in 256 * 256:
		buf[i * 3] = r[i]
		buf[i * 3 + 1] = g[i]
		buf[i * 3 + 2] = b[i]
	var im := Image.create_from_data(256, 256, false, Image.FORMAT_RGB8, buf)
	im.generate_mipmaps()
	noise_tex = ImageTexture.create_from_image(im)

# ------------------------------------------------------------------ level ground profile
## For every column: the deepest tile of open painted sky (sky bg ids with no foreground) = where the
## ground under the open sky is. A max-envelope over +-R columns ignores narrow structures standing on the
## floor (the spires), then it is smoothed.
func _make_profile(lvl: EELevel, sky_ids: Array) -> void:
	var W := lvl.width
	var H := lvl.height
	var deep := PackedFloat32Array()
	deep.resize(W)
	for x in W:
		var d := 0
		for y in range(1, H):
			var i := y * W + x
			if lvl.fg[i] == 0 and lvl.bg[i] in sky_ids:
				d = y
		deep[x] = d + 1
	var env := PackedFloat32Array()
	env.resize(W)
	var R := 22
	for x in W:
		var m := 0.0
		for dx in range(-R, R + 1):
			m = maxf(m, deep[clampi(x + dx, 0, W - 1)])
		env[x] = m
	for _p in 3:
		var sm := PackedFloat32Array()
		sm.resize(W)
		for x in W:
			var s := 0.0
			for dx in range(-7, 8):
				s += env[clampi(x + dx, 0, W - 1)]
			sm[x] = s / 15.0
		env = sm
	ground.resize(W)
	for x in W:
		ground[x] = maxf(-env[x], FLOOR_Y)
	var dbg := []
	for x in range(0, W, 20):
		dbg.append(int(ground[x]))
	print("WorldVista ground profile (every 20 cols): ", dbg)

func _ground_at(x: float) -> float:
	var W := ground.size()
	if x < 0.0:
		return lerpf(ground[0], -78.0, clampf(-x / 160.0, 0.0, 1.0))
	if x > W - 1:
		return lerpf(ground[W - 1], -104.0, clampf((x - W + 1) / 160.0, 0.0, 1.0))
	var i := int(x)
	var f := x - i
	return lerpf(ground[i], ground[mini(i + 1, W - 1)], f)

## The river leaving the falls' pool (x ~148 at the level) and winding away across the valley floor.
func river_x(dz: float) -> float:
	return 148.0 + 30.0 * sin(dz * 0.0125) + 13.0 * (sin(dz * 0.031 + 1.1) - sin(1.1))

## How far (in z) the home island reaches behind the level at column x before its cliff edge.
func island_edge(x: float) -> float:
	return 150.0 + 45.0 * _fn_big.get_noise_1d(x * 4.0 + 900.0) + 20.0 * _fn_hill.get_noise_1d(x * 0.9 + 300.0)

## Height + attributes of the vista landscape at world (x, z): Vector4(y, water, forest, mountain).
## The HOME ISLAND carries the level: its top continues the level's own ground profile back to a cliff
## edge that plunges into the cloud sea. Far behind, snowy peaks rise out of the clouds.
func sample(x: float, z: float) -> Vector4:
	var dz := -z
	var away := smoothstep(30.0, 200.0, dz)
	var rx := river_x(dz)
	var g := _ground_at(x - (rx - 148.0) * 0.85 * away)
	var above := clampf((g - FLOOR_Y) / 50.0, 0.0, 1.0)
	var hn := _fn_hill.get_noise_2d(x, z)
	var h := g + hn * lerpf(3.0, 22.0, above) * (0.35 + 0.65 * away) + _fn_big.get_noise_2d(x, z) * 16.0 * away * above
	# right behind the level the highlands sit a little below the level's own skyline (never edge-on at it)
	var seam: Array = _seam_at(x)
	var seam_w := 0.0
	if not is_nan(seam[0]):
		# continue world's extruded hillsides exactly at their back edge, melting into the profile
		seam_w = 1.0 - smoothstep(-_seam_z, -_seam_z + 70.0, dz)
		h = lerpf(h, seam[0] - (dz + _seam_z) * 0.12, seam_w)
	else:
		h -= 16.0 * above * (1.0 - smoothstep(20.0, 110.0, dz))
	# the island top rounds down toward its rim
	var inside := minf(island_edge(x) - dz, minf(x + 70.0 + 25.0 * _fn_hill.get_noise_1d(dz * 1.3), 470.0 - x + 25.0 * _fn_hill.get_noise_1d(dz * 1.3 + 77.0)))
	h -= (1.0 - smoothstep(0.0, 45.0, inside)) * 14.0
	# valley floor: meadows along the river, the river itself sunk a little
	var rd := absf(x - rx)
	var rw := lerpf(5.5, 3.8, smoothstep(40.0, 200.0, dz))
	var water := 0.0
	if h < FLOOR_Y + 30.0 or rd < 40.0:
		var bank := FLOOR_Y + 0.4 + smoothstep(rw, rw + 45.0, rd) * 60.0
		h = minf(h, bank) if rd < rw + 45.0 else h
		if rd < rw and inside > 2.0:
			h = FLOOR_Y - 0.8
			water = 1.0 - smoothstep(rw * 0.7, rw, rd)
	h = maxf(h, FLOOR_Y - 0.8 - 14.0)
	# the cliff: beyond the rim the island's rocky underside plunges into the clouds
	var cliff := smoothstep(0.0, 16.0, -inside)
	if cliff > 0.0:
		h = lerpf(h, UNDER_Y, cliff)
	# snowy peaks poking through the cloud sea far behind
	var m := smoothstep(420.0, 560.0, dz + _fn_big.get_noise_2d(x * 0.7, 5000.0) * 70.0)
	var mtn := 0.0
	if m > 0.0:
		var mass := _fn_mass.get_noise_2d(x, z) * 0.5 + 0.5
		var r := _fn_ridge.get_noise_2d(x, z) * 0.5 + 0.5
		var shape := clampf(mass * 0.65 + r * 0.5 - 0.3, 0.0, 1.0)
		var hm := PEAK_FLOOR_Y + shape * shape * 420.0
		h = maxf(h, lerpf(UNDER_Y, hm, m))
		mtn = m
	var fo := smoothstep(-0.15, 0.25, _fn_forest.get_noise_2d(x, z)) * smoothstep(FLOOR_Y + 2.0, FLOOR_Y + 10.0, h)
	fo = maxf(fo, above * 0.85 * (1.0 - smoothstep(60.0, 140.0, dz)))
	fo *= 1.0 - seam_w * 0.8
	fo = maxf(fo * (1.0 - mtn) * (1.0 - cliff) * smoothstep(2.0, 10.0, inside), 0.0)
	return Vector4(h, water, fo, mtn)

# ------------------------------------------------------------------ landscape meshes
func _land_mesh(nm: String, x0: float, x1: float, dx: float, z0: float, z1: float, dz0: float, dz_grow: float, skirt: bool) -> MeshInstance3D:
	var zs := PackedFloat32Array()
	var z := z0
	while z > z1:
		zs.append(z)
		z -= dz0 + (-z) * dz_grow
	zs.append(z1)
	var nx := int(ceil((x1 - x0) / dx)) + 1
	var nz := zs.size()
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var cols := PackedColorArray()
	cols.resize(nx * nz)
	var cust := PackedFloat32Array()      # CUSTOM0: seam colour (sRGB) + seam weight
	cust.resize(nx * nz * 4)
	for j in nz:
		for i in nx:
			var s := sample(x0 + i * dx, zs[j])
			hs[j * nx + i] = s.x
			cols[j * nx + i] = Color(s.y, s.z, s.w, 0.0)
			var sa: Array = _seam_at(x0 + i * dx)
			if not is_nan(sa[0]):
				var sc: Color = sa[1]
				var k := (j * nx + i) * 4
				cust[k] = sc.r; cust[k + 1] = sc.g; cust[k + 2] = sc.b
				cust[k + 3] = 1.0 - smoothstep(-_seam_z, -_seam_z + 70.0, -zs[j])
	var verts := PackedVector3Array()
	verts.resize(nx * nz)
	var norms := PackedVector3Array()
	norms.resize(nx * nz)
	for j in nz:
		var ja := maxi(j - 1, 0)
		var jb := mini(j + 1, nz - 1)
		for i in nx:
			var ia := maxi(i - 1, 0)
			var ib := mini(i + 1, nx - 1)
			var ddx := (hs[j * nx + ib] - hs[j * nx + ia]) / ((ib - ia) * dx)
			var ddz := (hs[jb * nx + i] - hs[ja * nx + i]) / (zs[jb] - zs[ja])
			verts[j * nx + i] = Vector3(x0 + i * dx, hs[j * nx + i], zs[j])
			norms[j * nx + i] = Vector3(-ddx, 1.0, -ddz).normalized()
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + nx
			# rows go away from the camera (-z): wind so the upper side faces +y
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	if skirt:
		# a vertical skirt under the last row hides any seam with the far range
		var base := verts.size()
		for i in nx:
			var v := verts[(nz - 1) * nx + i]
			verts.append(v - Vector3(0, 40.0, 0))
			norms.append(norms[(nz - 1) * nx + i])
			cols.append(cols[(nz - 1) * nx + i])
			cust.append_array([0.0, 0.0, 0.0, 0.0])
		for i in nx - 1:
			var a := (nz - 1) * nx + i
			var b := base + i
			idx.append_array([a, a + 1, b, b, a + 1, b + 1])
	if skirt and near_limit < NEAR_Z - 1.0:
		# foreground handed off (voxel layer in front): close the cut front edge with a rock face
		var fb := verts.size()
		for i in nx:
			verts.append(verts[i] - Vector3(0, 300.0, 0))
			norms.append(Vector3(0, 0, 1))
			cols.append(Color(0, 0, 0, 0))
			cust.append_array([0.0, 0.0, 0.0, 0.0])
		for i in nx:
			norms[i] = (norms[i] + Vector3(0, 0, 0.6)).normalized()
		for i in nx - 1:
			idx.append_array([i, i + 1, fb + i, fb + i, i + 1, fb + i + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_CUSTOM0] = cust
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = _mat("res://shaders/world/vista_land.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi

func _mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("noise_tex", noise_tex)
	_mats.append(m)
	return m

func _setup_instance(gi: GeometryInstance3D, nm: String) -> void:
	gi.name = nm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(gi)

# ------------------------------------------------------------------ forests
func _add_tree(rng: RandomNumberGenerator, px: float, gy: float, pz: float, sc: float) -> void:
	if rng.randf() < 0.55:
		var hgt := rng.randf_range(8.0, 13.0) * sc
		var rad := hgt * rng.randf_range(0.2, 0.26)
		_pines.append(Transform3D(Basis.from_scale(Vector3(rad, hgt, rad)), Vector3(px, gy - 1.0 + hgt * 0.5, pz)))
		_pine_c.append(Color(0.08, 0.17, 0.11).lerp(Color(0.12, 0.22, 0.12), rng.randf()))
	else:
		var w := rng.randf_range(3.2, 5.0) * sc
		_broad.append(Transform3D(Basis.from_scale(Vector3(w, w * rng.randf_range(0.8, 1.05), w)), Vector3(px, gy + w * 0.55, pz)))
		_broad_c.append(Color(0.14, 0.27, 0.11).lerp(Color(0.24, 0.36, 0.13), rng.randf()))

## Forests of the home island (+ the trees the floating islands queued), as two MultiMeshes.
func _make_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pines := _pines
	var pine_c := _pine_c
	var broad := _broad
	var broad_c := _broad_c
	var step := 4.2
	var z := near_limit - 12.0
	while z > MID_Z:
		var x := -150.0
		while x < 560.0:
			var px := x + rng.randf_range(-1.8, 1.8)
			var pz := z + rng.randf_range(-1.8, 1.8)
			var s := sample(px, pz)
			if s.z > 0.45 and rng.randf() < s.z * 0.95:
				_add_tree(rng, px, s.x, pz, rng.randf_range(0.8, 1.25) * (1.0 + (-pz) / 500.0))
			x += step * (1.0 + (-z) / 260.0)
		z -= step * (1.0 + (-z) / 260.0)
	# pines: three stacked drooping tiers (reads as a conifer, not a cone, even up close)
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 9
	for tier in 3:
		var base_y := -0.5 + tier * 0.27
		var top_y := base_y + 0.5
		var r := 1.0 - tier * 0.27
		var skirt := base_y - 0.06
		for a in seg:
			var t0 := TAU * a / seg
			var t1 := TAU * (a + 1) / seg
			var p0 := Vector3(cos(t0) * r, skirt, sin(t0) * r)
			var p1 := Vector3(cos(t1) * r, skirt, sin(t1) * r)
			var m0 := Vector3(cos(t0) * r * 0.55, base_y + 0.08, sin(t0) * r * 0.55)
			var m1 := Vector3(cos(t1) * r * 0.55, base_y + 0.08, sin(t1) * r * 0.55)
			var apex := Vector3(0, top_y, 0)
			for tri in [[p0, p1, m0], [p1, m1, m0], [m0, m1, apex]]:
				for v in tri:
					pst.add_vertex(v)
	pst.generate_normals()
	var cone := pst.commit()
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 8
	blob.rings = 4
	_tree_mm("VistaPines", cone, pines, pine_c)
	_tree_mm("VistaBroadleaf", blob, broad, broad_c)
	timings["vista_trees"] = pines.size() + broad.size()

func _tree_mm(nm: String, mesh: Mesh, xf: Array[Transform3D], cols: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := _mat("res://shaders/world/vista_prop.gdshader")
	m.set_shader_parameter("kind", 1)
	mmi.material_override = m
	_setup_instance(mmi, nm)

# ------------------------------------------------------------------ ruin spires
const STONE := Color(0.52, 0.52, 0.53, 1.0)
const STONE_CAP := Color(0.52, 0.52, 0.53, 0.0)
const VINE := Color(0.2, 0.33, 0.13, 0.0)

## Ruins on the far islands, four silhouettes of the level's architecture: a broken spire with a leaning
## upper section, an aqueduct of arches with a collapsed span, a two-storey arcade wall with a corner
## tower, and twin towers joined by a broken arch. Vines hang from ledges.
func _make_ruins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crowns: Array[Vector3] = []
	var idx := 0
	for r in _ruin_sites:
		var base := Vector3(r[0], r[1], r[2])
		var ht: float = r[3]
		var w: float = r[4]
		match idx % 4:
			0:
				crowns.append(_ruin_spire(st, rng, base, ht, w))
			1:
				crowns.append(_ruin_aqueduct(st, rng, base, ht * 0.55, w))
			2:
				crowns.append(_ruin_arcade(st, rng, base, ht * 0.7, w))
			_:
				crowns.append(_ruin_twins(st, rng, base, ht, w))
		idx += 1
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _mat("res://shaders/world/vista_prop.gdshader")
	m.set_shader_parameter("kind", 0)
	mi.material_override = m
	_setup_instance(mi, "VistaRuins")
	# a tree crowning some of the ruins, like the level's own spires
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 10
	blob.rings = 5
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for k in crowns.size():
		var tw: float = _ruin_sites[k][4] * 0.7
		xf.append(Transform3D(Basis.from_scale(Vector3(tw, tw * 0.8, tw * 0.8)), crowns[k] + Vector3(0, tw * 0.3, 0)))
		cols.append(Color(0.2, 0.34, 0.13))
	_tree_mm("VistaRuinTrees", blob, xf, cols)

## Vines hanging from a ledge edge (x0..x1 at height y, front face z).
func _vines(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, y: float, z: float, n: int) -> void:
	for i in n:
		var vl := rng.randf_range(3.0, 14.0)
		_box(st, Vector3(rng.randf_range(x0, x1), y - vl * 0.5, z + 0.3), Vector3(rng.randf_range(0.5, 1.1), vl, 0.6), VINE)

## A semicircular arch of voussoirs between two pier tops (x0, x1) springing at height y. Stops after
## skip_from stones (a collapsed arch).
func _arch(st: SurfaceTool, x0: float, x1: float, y: float, z: float, thick: float, dep: float, skip_from: int = 99) -> void:
	var r := (x1 - x0) * 0.5
	var cx := (x0 + x1) * 0.5
	var n := 9
	for i in n:
		if i >= skip_from:
			break
		var a := PI * (i + 0.5) / n
		var p := Vector3(cx - cos(a) * (r + thick * 0.5), y + sin(a) * (r + thick * 0.5), z)
		_box(st, p, Vector3(PI * r / n + 0.6, thick, dep), STONE, Basis(Vector3(0, 0, 1), a - PI * 0.5))
	if skip_from >= n:
		_box(st, Vector3(cx, y + r + thick * 0.5 + 1.0, z), Vector3(x1 - x0 + thick, 2.0, dep), STONE_CAP)

func _ruin_spire(st: SurfaceTool, rng: RandomNumberGenerator, b: Vector3, ht: float, w: float) -> Vector3:
	var dep := w * 0.8
	var y := b.y - 8.0
	var ph := ht * 0.14 + 8.0
	_box(st, Vector3(b.x, y + ph * 0.5, b.z), Vector3(w * 1.3, ph, dep * 1.25), STONE)
	y += ph
	_box(st, Vector3(b.x, y + 1.0, b.z), Vector3(w * 1.45, 2.0, dep * 1.4), STONE_CAP)
	_vines(st, rng, b.x - w * 0.7, b.x + w * 0.7, y, b.z + dep * 0.7, 6)
	y += 2.0
	var sw := w * 0.55
	var ox := 0.0
	var break_y := b.y + ht * 0.55
	while y < break_y:
		var th := minf(rng.randf_range(14.0, 22.0), break_y - y + 2.0)
		_box(st, Vector3(b.x + ox, y + th * 0.5, b.z), Vector3(sw, th, dep * 0.7), STONE)
		_box(st, Vector3(b.x + ox, y + th + 0.7, b.z), Vector3(sw + 3.0, 1.4, dep * 0.7 + 2.5), STONE_CAP)
		_vines(st, rng, b.x + ox - sw * 0.6, b.x + ox + sw * 0.6, y + th, b.z + dep * 0.35 + 1.2, 3)
		y += th + 1.4
		ox += rng.randf_range(-0.6, 0.6)
	# the upper section broke and leans on the stump
	var lean := Basis(Vector3(0, 0, 1), deg_to_rad(rng.randf_range(7.0, 12.0)) * (1.0 if rng.randf() < 0.5 else -1.0))
	var ch := ht * 0.3
	var cc := Vector3(b.x + ox + w * 0.08, y + ch * 0.5 + 1.0, b.z)
	_box(st, cc, Vector3(w * 1.05, ch, dep), STONE, lean)
	_box(st, cc + lean * Vector3(0, ch * 0.5 + 1.0, 0), Vector3(w * 1.2, 2.0, dep * 1.1), STONE_CAP, lean)
	for k in 4:
		var bw := w * rng.randf_range(0.15, 0.24)
		var bh := rng.randf_range(2.0, 9.0)
		_box(st, cc + lean * Vector3((k - 1.5) / 1.5 * (w * 0.5 - bw * 0.5), ch * 0.5 + 2.0 + bh * 0.5, 0), Vector3(bw, bh, dep * 0.7), STONE, lean)
	# fallen blocks at the foot
	for k in 3:
		_box(st, Vector3(b.x + rng.randf_range(-w, w), b.y + 1.5, b.z + rng.randf_range(-2.0, 4.0)), Vector3(rng.randf_range(3.0, 6.0), 3.0, 3.0), STONE, Basis(Vector3(0, 0, 1), rng.randf_range(-0.5, 0.5)))
	return cc + lean * Vector3(-w * 0.2, ch * 0.5 + 2.0, 0)

func _ruin_aqueduct(st: SurfaceTool, rng: RandomNumberGenerator, b: Vector3, ht: float, w: float) -> Vector3:
	var span := w * 1.3
	var n := 3
	var pw := w * 0.32
	var dep := w * 0.5
	var x0 := b.x - span * n * 0.5
	var spring := b.y + ht * 0.62
	for i in n + 1:
		var px := x0 + i * span
		var top := spring + (0.0 if i < n else -ht * 0.3)
		_box(st, Vector3(px, (b.y - 6.0 + top) * 0.5, b.z), Vector3(pw, top - b.y + 6.0, dep), STONE)
		_vines(st, rng, px - pw * 0.5, px + pw * 0.5, top, b.z + dep * 0.5, 2)
	for i in n:
		var ax0 := x0 + i * span + pw * 0.5
		var ax1 := x0 + (i + 1) * span - pw * 0.5
		# the last span collapsed: only a few voussoirs cling to the pier
		_arch(st, ax0, ax1, spring, b.z, 2.6, dep, 3 if i == n - 1 else 99)
		if i < n - 1:
			_box(st, Vector3((ax0 + ax1) * 0.5, spring + (ax1 - ax0) * 0.5 + 4.2, b.z), Vector3(span + 1.0, 2.2, dep + 1.5), STONE_CAP)
			_vines(st, rng, ax0, ax1, spring + (ax1 - ax0) * 0.5 + 3.0, b.z + dep * 0.5 + 0.8, 4)
	return Vector3(x0 + span * 0.5, spring + span * 0.5 + 5.0, b.z)

func _ruin_arcade(st: SurfaceTool, rng: RandomNumberGenerator, b: Vector3, ht: float, w: float) -> Vector3:
	var bays := 4
	var bay := w * 0.75
	var dep := w * 0.45
	var x0 := b.x - bay * bays * 0.5
	var storey := ht * 0.42
	for lvl in 2:
		var y0 := b.y - 4.0 + lvl * storey
		var nb := bays if lvl == 0 else bays - 1 - int(rng.randf() < 0.5)
		for i in nb + 1:
			_box(st, Vector3(x0 + i * bay, y0 + storey * 0.35, b.z), Vector3(bay * 0.28, storey * 0.7, dep), STONE)
		for i in nb:
			_arch(st, x0 + i * bay + bay * 0.14, x0 + (i + 1) * bay - bay * 0.14, y0 + storey * 0.7, b.z, 1.8, dep)
		_box(st, Vector3(x0 + nb * bay * 0.5, y0 + storey - 0.5, b.z), Vector3(nb * bay + bay * 0.3, 1.6, dep + 1.2), STONE_CAP)
		_vines(st, rng, x0, x0 + nb * bay, y0 + storey - 1.0, b.z + dep * 0.5 + 0.6, 5)
	# corner tower with broken crenellations
	var tx := x0 + bays * bay + bay * 0.2
	var th := ht * 1.2
	_box(st, Vector3(tx, b.y - 4.0 + th * 0.5, b.z), Vector3(bay * 0.8, th, dep * 1.3), STONE)
	for k in 3:
		var hh := rng.randf_range(1.5, 5.0)
		_box(st, Vector3(tx + (k - 1) * bay * 0.3, b.y - 4.0 + th + hh * 0.5, b.z), Vector3(bay * 0.2, hh, dep * 1.2), STONE)
	return Vector3(x0 + bay, b.y - 4.0 + storey * 2.0, b.z)

func _ruin_twins(st: SurfaceTool, rng: RandomNumberGenerator, b: Vector3, ht: float, w: float) -> Vector3:
	var gap := w * 1.4
	var dep := w * 0.6
	var tw := w * 0.5
	var h1 := ht
	var h2 := ht * rng.randf_range(0.62, 0.78)
	for side in 2:
		var tx := b.x + (side - 0.5) * gap
		var hh := h1 if side == 0 else h2
		var y := b.y - 6.0
		while y < b.y + hh - 4.0:
			var seg := minf(rng.randf_range(15.0, 24.0), b.y + hh - y)
			_box(st, Vector3(tx, y + seg * 0.5, b.z), Vector3(tw, seg, dep), STONE)
			_box(st, Vector3(tx, y + seg + 0.6, b.z), Vector3(tw + 2.4, 1.2, dep + 2.0), STONE_CAP)
			_vines(st, rng, tx - tw * 0.6, tx + tw * 0.6, y + seg, b.z + dep * 0.5 + 1.0, 2)
			y += seg + 1.2
	# a bridge arch between them, broken on the shorter tower's side
	_arch(st, b.x - gap * 0.5 + tw * 0.5, b.x + gap * 0.5 - tw * 0.5, b.y + h2 * 0.55, b.z, 2.2, dep * 0.7, 6)
	return Vector3(b.x - gap * 0.5, b.y + h1 + 1.0, b.z)

func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, b: Basis = Basis.IDENTITY) -> void:
	var h := s * 0.5
	var p := [
		c + b * Vector3(-h.x, -h.y, -h.z), c + b * Vector3(h.x, -h.y, -h.z), c + b * Vector3(h.x, h.y, -h.z), c + b * Vector3(-h.x, h.y, -h.z),
		c + b * Vector3(-h.x, -h.y, h.z), c + b * Vector3(h.x, -h.y, h.z), c + b * Vector3(h.x, h.y, h.z), c + b * Vector3(-h.x, h.y, h.z),
	]
	# faces (outward, clockwise seen from outside = Godot front face)
	var faces := [[4, 7, 6, 5], [1, 2, 3, 0], [0, 3, 7, 4], [5, 6, 2, 1], [7, 3, 2, 6], [0, 4, 5, 1]]
	for f in faces:
		var fc := col
		if f == faces[4] or f == faces[5]:
			fc.a = 0.0 if col.a < 0.5 else 0.3   # caps: no windows
		st.set_color(fc)
		st.add_vertex(p[f[0]]); st.add_vertex(p[f[1]]); st.add_vertex(p[f[2]])
		st.add_vertex(p[f[0]]); st.add_vertex(p[f[2]]); st.add_vertex(p[f[3]])

# ------------------------------------------------------------------ floating islands
## MIDGROUND islands right behind the level (x, top y, z, radius, depth, ruin fragments): real 3D masses
## near the big structures at their heights, so the level's own masses have neighbours in depth.
const MID_ISLANDS := [
	# placed (tests: see sky_vista shots) to FRAME the typical views at their edges, never crowding the
	# central band of the gameplay view: composition over quantity
	[150.0, -80.0, -36.0, 11.0, 16.5, false],
	[236.0, -128.0, -58.0, 9.0, 13.5, true],
	[266.0, -6.0, -58.0, 12.0, 18.0, true],
	[116.0, -150.0, -40.0, 9.0, 13.5, true],
	[166.0, -2.0, -56.0, 9.0, 13.5, false],
	[398.0, -122.0, -45.0, 10.0, 15.0, false],
]
## DISTANT islands (x, top y, z, radius, depth, waterfall, ruin tower height or 0).
const FAR_ISLANDS := [
	[60.0, -150.0, -140.0, 24.0, 45.6, true, 0.0],
	[335.0, -178.0, -165.0, 28.0, 53.2, true, 0.0],
	[150.0, -115.0, -240.0, 20.0, 38.0, false, 70.0],
	[470.0, -42.0, -300.0, 34.0, 64.6, false, 95.0],
	[140.0, -12.0, -390.0, 44.0, 83.6, true, 120.0],
	[385.0, -122.0, -420.0, 52.0, 98.8, true, 0.0],
	[-170.0, -32.0, -480.0, 58.0, 110.2, false, 110.0],
	[630.0, -84.0, -520.0, 58.0, 110.2, true, 0.0],
]

func _make_islands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var mid := SurfaceTool.new()
	mid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var far := SurfaceTool.new()
	far.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frag := SurfaceTool.new()
	frag.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.54, 0.54, 0.55, 0.0)
	var k := 0
	for d in (MID_ISLANDS if near_limit >= NEAR_Z - 1.0 else []):
		var c := Vector3(d[0], d[1], d[2])
		var R: float = d[3]
		_island(mid, c, R, d[4], k)
		_island_trees(rng, c, R, 0.55)
		if d[5]:
			# ruin fragments: a broken column pair and a fallen lintel
			var ox := rng.randf_range(-0.3, 0.3) * R
			var h1 := rng.randf_range(0.5, 0.9) * R
			var h2 := h1 * rng.randf_range(0.4, 0.8)
			_box(frag, c + Vector3(ox - R * 0.18, h1 * 0.5 - 0.5, 0.0), Vector3(1.6, h1, 1.6), stone)
			_box(frag, c + Vector3(ox + R * 0.18, h2 * 0.5 - 0.5, 0.0), Vector3(1.6, h2, 1.6), stone)
			_box(frag, c + Vector3(ox + R * 0.05, 0.4, 1.5), Vector3(R * 0.45, 1.0, 1.4), stone)
		k += 1
	var falls: Array = []
	for d in FAR_ISLANDS:
		var c := Vector3(d[0], d[1], d[2])
		var R: float = d[3]
		# never inside a foreground layer that owns the space in front of near_limit
		c.z = minf(c.z, near_limit - 4.0 - R * 0.8)
		_island(far, c, R, d[4], k)
		_island_trees(rng, c, R, 0.4 if d[6] > 0.0 else 0.8)
		if d[6] > 0.0:
			_ruin_sites.append([c.x + R * 0.15, c.y + R * 0.06, c.z - R * 0.1, d[6], clampf(R * 0.4, 12.0, 24.0)])
		if d[5]:
			falls.append([c + Vector3(R * rng.randf_range(-0.35, 0.35), -R * 0.04, R * 0.93), clampf(R * 0.12, 2.5, 7.0)])
		k += 1
	for pair in [[mid, "VistaMidIslands", 0.2], [far, "VistaFarIslands", 0.12]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := _mat("res://shaders/world/vista_prop.gdshader")
		m.set_shader_parameter("kind", 2)
		m.set_shader_parameter("fog_near", pair[2])
		mi.material_override = m
		_setup_instance(mi, pair[1])
	frag.generate_normals()
	var fm := MeshInstance3D.new()
	fm.mesh = frag.commit()
	var fmat := _mat("res://shaders/world/vista_prop.gdshader")
	fmat.set_shader_parameter("kind", 0)
	fmat.set_shader_parameter("fog_near", 0.3)
	fm.material_override = fmat
	_setup_instance(fm, "VistaMidRuins")
	_make_falls(falls)

## A floating island: domed grassy top with a noisy rim, a rocky underside tapering to a keel tip.
func _island(st: SurfaceTool, c: Vector3, R: float, depth: float, seed_i: int) -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 300 + seed_i
	fn.frequency = 0.9
	fn.fractal_octaves = 3
	var NA := 44
	var NT := 4          # top rings (centre..rim)
	var NU := 12         # underside rings (rim..tip)
	var base: int = _vcount.get(st.get_instance_id(), 0)
	var rows := NT + NU + 1
	_vcount[st.get_instance_id()] = base + rows * NA
	var lean := Vector2(fn.get_noise_1d(50.0), fn.get_noise_1d(90.0)) * R * 0.5
	for row in rows:
		for a in NA:
			var th := TAU * a / NA
			var rim := 1.0 + 0.24 * fn.get_noise_2d(cos(th) * 1.3, sin(th) * 1.3) + 0.08 * fn.get_noise_2d(cos(th) * 4.0 + 9.0, sin(th) * 4.0)
			var p: Vector3
			var col: Color
			if row <= NT:
				var r := float(row) / NT
				var y := c.y + (1.0 - r * r) * R * 0.07 + fn.get_noise_2d(cos(th) * r * 2.0 + 20.0, sin(th) * r * 2.0) * R * 0.04
				if row == NT:
					y -= R * 0.05
				p = Vector3(c.x + cos(th) * R * rim * r, y, c.z + sin(th) * R * rim * r * 0.8)
				col = Color(0.33, 0.50, 0.19, 1.0) if row < NT else Color(0.36, 0.40, 0.2, 1.0)
			else:
				var t := float(row - NT) / NU
				# rugged keel: vertical rock ribs (angular noise that persists down the keel), lumpy
				# ledges, and a few hanging spurs that reach deeper than the rest
				var rib := fn.get_noise_3d(cos(th) * 3.2, sin(th) * 3.2, t * 0.8)
				var lump := fn.get_noise_3d(cos(th) * 1.4 + 7.0, sin(th) * 1.4, t * 3.5)
				var f := pow(1.0 - t, 0.62) * (1.0 + 0.32 * rib + 0.22 * lump)
				f *= 1.0 - 0.25 * smoothstep(0.12, 0.2, t) * (1.0 - smoothstep(0.2, 0.3, t))   # undercut lip
				var spur := maxf(fn.get_noise_2d(cos(th) * 1.8 + 30.0, sin(th) * 1.8), 0.0)
				var y := c.y - R * 0.12 - depth * pow(t, 1.1) * (0.8 + 0.9 * spur * t)
				p = Vector3(c.x + cos(th) * R * rim * f + lean.x * t * t, y, c.z + sin(th) * R * rim * f * 0.8 + lean.y * t * t * 0.5)
				col = Color(0.42, 0.33, 0.25, 0.0).lerp(Color(0.33, 0.31, 0.32, 0.0), smoothstep(0.1, 0.5, t)).darkened(0.2 * t)
			st.set_color(col)
			st.add_vertex(p)
	for row in rows - 1:
		for a in NA:
			var i0 := base + row * NA + a
			var i1 := base + row * NA + (a + 1) % NA
			var j0 := i0 + NA
			var j1 := i1 + NA
			st.add_index(i0); st.add_index(j0); st.add_index(i1)
			st.add_index(i1); st.add_index(j0); st.add_index(j1)

func _island_trees(rng: RandomNumberGenerator, c: Vector3, R: float, density: float) -> void:
	var n := int(R * R * 0.05 * density) + 1
	for i in n:
		var th := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.75
		var px := c.x + cos(th) * R * r
		var pz := c.z + sin(th) * R * r * 0.8
		_add_tree(rng, px, c.y + (1.0 - r * r) * R * 0.07 - 0.3, pz, clampf(R / 30.0, 0.45, 1.3))

## Waterfalls pouring off island rims down into the cloud sea: world quads facing +z.
func _make_falls(falls: Array) -> void:
	var sh := load("res://shaders/world/vista_falls.gdshader")
	var k := 0
	for f in falls:
		var top: Vector3 = f[0]
		var w: float = f[1]
		var h := top.y - (CLOUD_BASE + 4.0)
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = top + Vector3(0, -h * 0.5, 0.6)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("noise_tex", noise_tex)
		m.set_shader_parameter("seed", float(k) * 3.1)
		m.set_shader_parameter("height", h)
		m.render_priority = -95
		_mats.append(m)
		mi.material_override = m
		_setup_instance(mi, "VistaFalls%d" % get_child_count())
		k += 1

# ------------------------------------------------------------------ the home island's underside
## Below the level's bottom edge (y -200) the home island's rocky keel falls away into the cloud sea:
## a ribbed rock face just behind the level, receding and tapering as it descends, roots at its lip and
## the level's water spilling off it as waterfalls.
func _make_home_keel() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 717
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -80.0
	var x1 := 480.0
	var dx := 3.0
	var NX := int((x1 - x0) / dx) + 1
	var NT := 26
	for j in NT + 1:
		var t := float(j) / NT
		for i in NX:
			var x := x0 + i * dx
			var u := (x - 200.0) / 280.0
			var depth := 190.0 * pow(maxf(1.0 - pow(absf(u), 1.8), 0.0), 0.7) * (0.8 + 0.4 * (fn.get_noise_1d(x * 0.3) * 0.5 + 0.5)) + 8.0
			var rib := fn.get_noise_2d(x * 1.6, t * 18.0)
			var y := -196.0 - depth * pow(t, 1.15) * (1.0 + 0.15 * fn.get_noise_2d(x * 0.8, 300.0 + t * 6.0))
			# the keel recedes steeply back under the island (about 1.5 units back per unit of drop), so
			# the frame bottom shows its shadowed face falling away and then the cloud sea beyond it
			var z := -4.0 - pow(t, 0.8) * 300.0 - rib * 7.0 * sqrt(t) - absf(u) * t * 40.0
			var col := Color(0.34, 0.28, 0.22, 0.0).lerp(Color(0.27, 0.26, 0.28, 0.0), smoothstep(0.03, 0.3, t)).darkened(0.25 * t)
			st.set_color(col)
			st.add_vertex(Vector3(x, y, z))
	for j in NT:
		for i in NX - 1:
			var a := j * NX + i
			var b := a + NX
			# rows go downward, the face looks toward +z
			st.add_index(a); st.add_index(a + 1); st.add_index(b)
			st.add_index(b); st.add_index(a + 1); st.add_index(b + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _mat("res://shaders/world/vista_prop.gdshader")
	m.set_shader_parameter("kind", 2)
	m.set_shader_parameter("fog_near", 0.1)
	mi.material_override = m
	_setup_instance(mi, "VistaHomeKeel")
	# the level's water spilling off the underside (hanging roots removed: detached from world's lip,
	# they read as floating poles)
	_make_falls([[Vector3(150.0, -197.0, -4.0), 6.0], [Vector3(358.0, -197.0, -4.0), 4.0], [Vector3(8.0, -197.0, -4.0), 3.5]])

# ------------------------------------------------------------------ block-built scenery
## Distant pieces painted with the level's own blocks (WorldVistaBlocks): kind, map top-left world x/y, z,
## world units per tile. Composed to frame the typical views: strong silhouettes on the sides.
const BLOCK_PIECES := [
	# out beyond the level's sides so they only ever frame the view edges (never behind gameplay)
	[0, -150.0, 12.0, -120.0, 2.2],    # ruin island, west beyond the grove
	[1, 445.0, 45.0, -170.0, 2.0],     # the second great spire, east beyond the scroll and the shrine
	[2, -335.0, -95.0, -260.0, 2.4],   # aqueduct isle with its waterfall, far west
	[3, 485.0, -10.0, -290.0, 3.0],    # a far keep, far east
]
var ref_dir := "res://assets/ee_ref_fv"
## true: block pieces render through WorldTerrain.build_backdrop (world); false: vista_blocks stand-in.
var use_world_terrain := true

const PIECE_HAZE_COLOR := Color(0.58, 0.72, 0.94)
const PIECE_DELAY := 2.0          # seconds after the vista is built before the first piece starts
const PIECE_FADE := 1.5           # fade-in time per piece
var _deferred_pieces: Array = []  # [EELevel, origin, scale, index]

func _build_pieces_deferred() -> void:
	if _deferred_pieces.is_empty() or not is_inside_tree():
		return
	await get_tree().create_timer(PIECE_DELAY).timeout
	for pc in _deferred_pieces:
		if not is_inside_tree():
			return
		var holder := [null]
		var lvl: EELevel = pc[0]
		var origin: Vector3 = pc[1]
		var sc: float = pc[2]
		var task := WorkerThreadPool.add_task(func() -> void:
			holder[0] = WorldTerrain.build_backdrop(lvl, origin, sc, 1.0, PIECE_HAZE_COLOR, 3, ref_dir))
		while not WorkerThreadPool.is_task_completed(task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var t: WorldTerrain = holder[0]
		if t == null or not is_inside_tree():
			continue
		t.name = "VistaBlocks%d" % pc[3]
		add_child(t)
		# fade in from full haze (invisible against the sky) to its distance haze
		var target := clampf(0.3 + 0.45 * (1.0 - exp(-(25.0 - origin.z) * 0.0035)), 0.0, 0.85)
		var tw := create_tween()
		tw.tween_method(func(h: float) -> void: t.set_haze(h, PIECE_HAZE_COLOR), 1.0, target, PIECE_FADE)
		await get_tree().process_frame
	_deferred_pieces.clear()

func _make_block_pieces() -> void:
	var colors := WorldVistaBlocks.load_colors(ref_dir)
	var sh := load("res://shaders/world/vista_blocks.gdshader")
	var k := 0
	for pc in BLOCK_PIECES:
		var art := WorldVistaBlocks.make(pc[0], 3 + k)
		var sc: float = pc[4]
		var z: float = minf(pc[3], near_limit - 10.0)
		if use_world_terrain:
			# world's own terrain pipeline in backdrop mode: the pieces look exactly like the level's art.
			# Built DEFERRED (after the level is playable, on a worker thread, one at a time) and faded in,
			# so loading doesn't grow. make_level() adds a 1-tile border: origin moves up-left one tile.
			_deferred_pieces.append([art.make_level(), Vector3(pc[1] - sc, pc[2] + sc, z), sc, k])
			k += 1
			continue
		var tex := art.textures(colors)
		var q := QuadMesh.new()
		q.size = Vector2(art.w * sc, art.h * sc)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = Vector3(pc[1] + art.w * sc * 0.5, pc[2] - art.h * sc * 0.5, z)
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("noise_tex", noise_tex)
		var ci: Image = tex[0]
		m.set_shader_parameter("col_tex", ImageTexture.create_from_image(ci))
		m.set_shader_parameter("col_smooth", ImageTexture.create_from_image(ci.duplicate()))
		m.set_shader_parameter("mask_tex", ImageTexture.create_from_image(tex[1]))
		m.set_shader_parameter("map_size", Vector2(art.w, art.h))
		_mats.append(m)
		mi.material_override = m
		_setup_instance(mi, "VistaBlocks%d" % k)
		k += 1

# ------------------------------------------------------------------ clouds
## (x, y_base, z, width, height, flat_base): world-placed cumulus.
const CUMULUS := [
	# high fair-weather cumulus above the spire tops
	[70.0, 6.0, -230.0, 120.0, 44.0, 0.6],
	[250.0, 16.0, -300.0, 150.0, 52.0, 0.5],
	[420.0, 2.0, -260.0, 120.0, 42.0, 0.6],
	[-60.0, 22.0, -380.0, 170.0, 58.0, 0.5],
	[560.0, 26.0, -420.0, 170.0, 58.0, 0.5],
	[170.0, 48.0, -520.0, 210.0, 66.0, 0.4],
	# mid-height puffs drifting between the level's towers
	[120.0, -56.0, -150.0, 56.0, 20.0, 0.7],
	[296.0, -64.0, -140.0, 60.0, 21.0, 0.7],
	[-20.0, -50.0, -170.0, 70.0, 24.0, 0.7],
	# a low bank below the Winners' Scroll and the logo (they float above it)
	[362.0, -84.0, -80.0, 46.0, 14.0, 0.8],
	[322.0, -88.0, -100.0, 56.0, 16.0, 0.8],
	[404.0, -82.0, -118.0, 64.0, 18.0, 0.8],
	# towers rising out of the cloud sea
	[205.0, -238.0, -300.0, 90.0, 52.0, 0.9],
	[60.0, -238.0, -370.0, 100.0, 58.0, 0.9],
	[390.0, -238.0, -340.0, 95.0, 55.0, 0.9],
	[-120.0, -238.0, -240.0, 90.0, 46.0, 0.9],
	[520.0, -238.0, -260.0, 90.0, 46.0, 0.9],
]

func _make_cumulus() -> void:
	var sh := load("res://shaders/world/vista_cumulus.gdshader")
	var k := 0
	for c in CUMULUS:
		if c[2] > near_limit - 5.0 and near_limit < NEAR_Z - 1.0:
			c = c.duplicate()
			c[2] = near_limit - 8.0 - absf(c[2] - NEAR_Z) * 0.3   # push the low banks behind the handoff
		var q := QuadMesh.new()
		q.size = Vector2(c[3], c[4])
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = Vector3(c[0], c[1] + c[4] * 0.5, c[2])
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("noise_tex", noise_tex)
		m.set_shader_parameter("seed", float(k) * 1.37 + 0.5)
		m.set_shader_parameter("flat_base", c[5])
		m.render_priority = -90
		_mats.append(m)
		mi.material_override = m
		_setup_instance(mi, "VistaCumulus%d" % k)
		k += 1

func _make_cloud_sea() -> void:
	var bmin := Vector3(-560.0, CLOUD_BASE - 8.0, FAR_Z)
	var cnz := CLOUD_NEAR_Z   # always right behind the level: a foreground layer's solids occlude it by depth
	var bmax := Vector3(960.0, CLOUD_BASE + 20.0, cnz)
	var box := BoxMesh.new()
	box.size = bmax - bmin
	_clouds = MeshInstance3D.new()
	_clouds.mesh = box
	_clouds.position = (bmin + bmax) * 0.5
	var m := _mat("res://shaders/world/vista_clouds.gdshader")
	m.set_shader_parameter("box_min", bmin)
	m.set_shader_parameter("box_max", bmax)
	m.set_shader_parameter("base_y", CLOUD_BASE)
	m.set_shader_parameter("near_z", cnz)
	m.render_priority = -100
	_clouds.material_override = m
	_setup_instance(_clouds, "VistaCloudSea")
