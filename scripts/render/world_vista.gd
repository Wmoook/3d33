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
const CLOUD_NEAR_Z := -30.0

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
	_land_near = _land_mesh("VistaLandNear", -150.0, 560.0, 2.0, NEAR_Z, MID_Z, 1.4, 0.012, true)
	_land_far = _land_mesh("VistaLandFar", -560.0, 960.0, 4.0, MID_Z + 6.0, FAR_Z, 4.0, 0.0, false)
	timings["vista_land"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	_make_islands()
	_make_trees()
	_make_ruins()
	_make_cumulus()
	_make_cloud_sea()
	timings["vista_props"] = Time.get_ticks_msec() - t
	if sky_mat:
		sky_mat.set_shader_parameter("sun_dir", sun_dir)
		sky_mat.set_shader_parameter("noise_tex", noise_tex)
		sky_mat.set_shader_parameter("has_noise", 1.0)
	print("WorldVista built %s" % str(timings))

## Per frame (camera world position). The vista is world-anchored, so nothing moves; this only hides it
## when no sky can be visible (sky_visibility 0 = deep underground), which also skips the cloud march.
func update(_camera_pos: Vector3, sky_visibility: float = 1.0) -> void:
	visible = sky_visibility > 0.001

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
	for j in nz:
		for i in nx:
			var s := sample(x0 + i * dx, zs[j])
			hs[j * nx + i] = s.x
			cols[j * nx + i] = Color(s.y, s.z, s.w, 0.0)
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
		for i in nx - 1:
			var a := (nz - 1) * nx + i
			var b := base + i
			idx.append_array([a, a + 1, b, b, a + 1, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
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
	var z := NEAR_Z - 12.0
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
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	cone.cap_bottom = false
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
func _make_ruins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.52, 0.52, 0.53, 1.0)
	var cap := Color(0.52, 0.52, 0.53, 0.0)
	var crowns: Array[Vector3] = []
	for r in _ruin_sites:
		var x: float = r[0]
		var gy: float = r[1]
		var z: float = r[2]
		var ht: float = r[3]
		var w: float = r[4]
		var dep := w * 0.8
		# plinth
		var y := gy - 10.0
		var ph := ht * 0.16 + 10.0
		_box(st, Vector3(x, y + ph * 0.5, z), Vector3(w * 1.35, ph, dep * 1.3), stone)
		y += ph
		_box(st, Vector3(x, y + 1.0, z), Vector3(w * 1.5, 2.0, dep * 1.45), cap)
		y += 2.0
		# shaft with ledges
		var crown_y := gy + ht * 0.72
		var sw := w * 0.5
		while y < crown_y - 6.0:
			var th := minf(rng.randf_range(16.0, 26.0), crown_y - y)
			_box(st, Vector3(x, y + th * 0.5, z), Vector3(sw, th, dep * 0.7), stone)
			_box(st, Vector3(x, y + th + 0.8, z), Vector3(sw + 3.5, 1.6, dep * 0.7 + 3.0), cap)
			y += th + 1.6
		# bulky crown block with a jutting balcony and a broken, jagged top
		var ch := gy + ht - y
		_box(st, Vector3(x, y + 1.2, z), Vector3(w * 1.15, 2.4, dep * 1.1), cap)
		# corbels widening the shaft into the crown, then the crown with a collapsed corner
		_box(st, Vector3(x, y - 3.0, z), Vector3(w * 0.8, 4.0, dep * 0.85), stone)
		_box(st, Vector3(x - w * 0.12, y + 2.4 + ch * 0.4, z), Vector3(w * 1.0, ch * 0.8, dep), stone)
		_box(st, Vector3(x + w * 0.5, y + 2.4 + ch * 0.22, z), Vector3(w * 0.3, ch * 0.44, dep * 0.9), stone)
		_box(st, Vector3(x - w * 0.72, y + ch * 0.35, z), Vector3(w * 0.34, 2.0, dep * 0.8), cap)
		var top := y + 2.4 + ch * 0.8
		for k in 5:
			var bw := w * rng.randf_range(0.14, 0.24)
			var bh := rng.randf_range(2.0, 12.0) * (0.4 if k == 2 else 1.0)
			var ox := (k - 2.0) / 2.0 * (w * 0.5 - bw * 0.5)
			_box(st, Vector3(x + ox, top + bh * 0.5, z), Vector3(bw, bh, dep * rng.randf_range(0.5, 0.9)), stone)
		crowns.append(Vector3(x + w * 0.1, top + 1.0, z))
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
	for k in range(0, _ruin_sites.size(), 2):
		var tw: float = _ruin_sites[k][4] * 0.85
		xf.append(Transform3D(Basis.from_scale(Vector3(tw, tw * 0.8, tw * 0.8)), crowns[k] + Vector3(0, tw * 0.3, 0)))
		cols.append(Color(0.2, 0.34, 0.13))
	_tree_mm("VistaRuinTrees", blob, xf, cols)

func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
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
	[205.0, -126.0, -300.0, 90.0, 52.0, 0.9],
	[60.0, -126.0, -370.0, 100.0, 58.0, 0.9],
	[390.0, -126.0, -340.0, 95.0, 55.0, 0.9],
]

func _make_cumulus() -> void:
	var sh := load("res://shaders/world/vista_cumulus.gdshader")
	var k := 0
	for c in CUMULUS:
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
	var bmax := Vector3(960.0, CLOUD_BASE + 20.0, CLOUD_NEAR_Z)
	var box := BoxMesh.new()
	box.size = bmax - bmin
	_clouds = MeshInstance3D.new()
	_clouds.mesh = box
	_clouds.position = (bmin + bmax) * 0.5
	var m := _mat("res://shaders/world/vista_clouds.gdshader")
	m.set_shader_parameter("box_min", bmin)
	m.set_shader_parameter("box_max", bmax)
	m.set_shader_parameter("base_y", CLOUD_BASE)
	m.set_shader_parameter("near_z", CLOUD_NEAR_Z)
	m.render_priority = -100
	_clouds.material_override = m
	_setup_instance(_clouds, "VistaCloudSea")
