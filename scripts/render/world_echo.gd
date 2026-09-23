class_name WorldEcho
extends Node3D
## Day levels: ECHO LAYERS - the level's own silhouettes rendered again behind the gameplay plane (z -4 and
## z -10, offset up/sideways and slightly scaled) with every mass extruded DOWN into foundations, so each
## block visibly continues into depth and stands on structure instead of hanging in the painted sky.
## Only drawn where the gameplay plane shows open sky (see echo.gdshader).

const LAYERS := [
	# z, offset (world x, y), scale, darken, haze
	[-4.0, Vector2(-0.6, 0.9), 1.02, 0.62, 0.22],
	[-10.0, Vector2(1.4, 2.4), 1.06, 0.5, 0.48],
]
const CHUNK := 32
const VPT := 4

var mats: Array[ShaderMaterial] = []

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var mask := PackedByteArray()
	mask.resize(W * H)
	var col := PackedByteArray()
	col.resize(W * H * 4)
	var fg := terrain.fgcol_img.get_data()
	var scroll := WorldPalette.FV_RECT_SCROLL
	for x in W:
		var carry := -1   # colour source index while extruding down
		for y in H:
			var i := y * W + x
			var real := terrain.solid[i] == 1 and terrain.speck[i] == 0 and lvl.fg[i] != 87 and not scroll.has_point(Vector2i(x, y))
			if real:
				carry = i
				mask[i] = 1
				for k in 3:
					col[i * 4 + k] = fg[i * 4 + k]
			elif carry >= 0:
				# foundation below: inherits the mass above (stone stays stone, earth -> rock, canopy -> trunk)
				mask[i] = 1
				var m: int = terrain.mat_ids[carry]
				var c := Color8(fg[carry * 4], fg[carry * 4 + 1], fg[carry * 4 + 2])
				if m == WorldPalette.M_FOLIAGE or m == WorldPalette.M_GRASS:
					c = Color8(92, 64, 40)
				elif m == WorldPalette.M_WATER:
					c = Color8(70, 76, 80)
				c = c.darkened(clampf(float(y - carry / W) * 0.012, 0.0, 0.45))
				col[i * 4] = c.r8; col[i * 4 + 1] = c.g8; col[i * 4 + 2] = c.b8
			col[i * 4 + 3] = 255
	for i in W * H:
		mask[i] = 1 if mask[i] else 0
	# SDF of the echo mask (bit0), soft corners
	var sdf := WorldSdfBaker.bake(mask, W, H)
	if sdf == null:
		return
	var sdf_tex := ImageTexture.create_from_image(sdf)
	var col_tex := ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, col))
	var sky := PackedByteArray()
	sky.resize(W * H)
	for i in W * H:
		sky[i] = 255 if terrain.sky[i] else 0
	var sky_img := Image.create_from_data(W, H, false, Image.FORMAT_L8, sky)
	var sky_tex := ImageTexture.create_from_image(sky_img)
	var mesh := _grid()
	for L in LAYERS:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/world/echo.gdshader")
		m.set_shader_parameter("echo_sdf", sdf_tex)
		m.set_shader_parameter("echo_col", col_tex)
		m.set_shader_parameter("sky_field", sky_tex)
		m.set_shader_parameter("detail_nrm", terrain.material.get_shader_parameter("detail_nrm"))
		m.set_shader_parameter("level_size", Vector2(W, H))
		m.set_shader_parameter("layer_z", L[0])
		m.set_shader_parameter("layer_offset", L[1])
		m.set_shader_parameter("layer_scale", L[2])
		m.set_shader_parameter("darken", L[3])
		m.set_shader_parameter("haze_amt", L[4])
		mats.append(m)
		var x0 := -8
		while x0 < W + 8:
			var y0 := -8
			while y0 < H + 16:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = m
				mi.position = Vector3(x0, -y0, L[0])
				mi.custom_aabb = AABB(Vector3(0, -CHUNK, -2.0), Vector3(CHUNK, CHUNK, 3.0))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				add_child(mi)
				y0 += CHUNK
			x0 += CHUNK

func _grid() -> ArrayMesh:
	var n := CHUNK * VPT
	var verts := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	var k := 0
	for j in n + 1:
		for i in n + 1:
			verts[k] = Vector3(float(i) / VPT, -float(j) / VPT, 0.0)
			k += 1
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	k = 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var c := a + n + 1
			idx[k] = a; idx[k + 1] = a + 1; idx[k + 2] = c + 1
			idx[k + 3] = a; idx[k + 4] = c + 1; idx[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
