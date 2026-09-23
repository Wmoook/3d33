class_name WorldBackdrop
extends Node3D
## Far scenery: layered silhouetted hills/forests behind the surface (seen through the open sky), and the
## invisible moon occluder that keeps moonlight out of everything underground.

var ground_top := PackedFloat32Array()   # per tile column: tile y of the ground surface (EE y down)
var _layers: Array[MeshInstance3D] = []
## Render layer bit (layer 20) reserved for the moon occluder; every other world light excludes it.
const OCCLUDER_LAYER := 1 << 19

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	ground_top.resize(W)
	for x in W:
		var gy := -1
		for y in 30:
			if terrain.sky[y * W + x]:
				gy = y + 1
		ground_top[x] = gy
	# columns with no sky at all (tree trunks under canopies reaching the top) take the deepest
	# ground of their neighbours, so the occluder never rises into the surface there
	var raw := ground_top.duplicate()
	for x in W:
		var g := raw[x]
		for dx in range(-8, 9):
			g = maxf(g, raw[clampi(x + dx, 0, W - 1)])
		ground_top[x] = g
	if WorldPalette.is_odyssey():
		_make_hills(W)
		_make_moon_occluder(W, H)
	else:
		_make_interior_occluder(terrain)

func _ridge_mesh(x0: float, x1: float, base_y: float, amp: float, freq: float, seed_v: int, z: float, trees: bool) -> ArrayMesh:
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = freq
	fn.fractal_octaves = 4
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var step := 0.5
	var n := int((x1 - x0) / step)
	var bottom := base_y - 60.0
	for i in n + 1:
		var x := x0 + i * step
		var h := base_y + (fn.get_noise_1d(x) * 0.5 + 0.5) * amp
		if trees:
			# rounded forest canopy along the crest (overlapping domes)
			var cell := floorf(x / 2.6)
			var fx := x / 2.6 - cell
			var rnd := fn.get_noise_1d(cell * 13.7 + 300.0) * 0.5 + 0.5
			var dome := sqrt(maxf(0.0, 1.0 - pow((fx - 0.5) * 2.0, 2.0)))
			h += dome * (0.8 + rnd * 1.8)
		verts.append(Vector3(x, h, z)); uvs.append(Vector2(0, 1))
		verts.append(Vector3(x, bottom, z)); uvs.append(Vector2(0, 0.95))
		if i > 0:
			var a := (i - 1) * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _make_hills(W: int) -> void:
	var sh := load("res://shaders/world/hills.gdshader")
	# (z, base world y, amplitude, freq, haze, rim, trees)
	var defs := [
		[-140.0, -30.0, 30.0, 0.006, 0.7, 0.2, false],
		[-90.0, -26.0, 16.0, 0.011, 0.45, 0.45, true],
		[-50.0, -24.0, 8.0, 0.02, 0.2, 0.8, true],
	]
	var k := 0
	for d in defs:
		var z: float = d[0]
		var spread := 1.0 + (-z) / 60.0
		var mi := MeshInstance3D.new()
		mi.mesh = _ridge_mesh(-400.0 * spread, W + 400.0 * spread, d[1], d[2], d[3], 101 + k, z, d[6])
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("haze", d[4])
		m.set_shader_parameter("rim", d[5])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Hills%d" % k
		add_child(mi)
		_layers.append(mi)
		k += 1

## Shadow-only vertical curtain just in front of the gameplay plane, from ~3 tiles under the ground
## surface down to the bottom: blocks the moon for every underground point (including actors), while
## the surface keeps its moonlight. Never visible to the camera.
func _make_moon_occluder(W: int, H: int) -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var zf := 1.3
	var zb := 70.0
	for x in range(-10, W + 11):
		var gx := clampi(x, 0, W - 1)
		var top := -(ground_top[gx] + 8.0)   # deep enough that its shadow edge never lands on the surface soil band
		var bottom := -(H + 20.0)
		var base := verts.size()
		verts.append(Vector3(x, top, zf))
		verts.append(Vector3(x, bottom, zf))
		verts.append(Vector3(x, top, zb))
		if x > -10:
			var a := base - 3
			# front curtain
			idx.append_array([a, base, a + 1, a + 1, base, base + 1])
			# roof strip (top edge, extending toward the moon) so grazing rays are blocked too
			idx.append_array([a, a + 2, base, base, a + 2, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "MoonOccluder"
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = OCCLUDER_LAYER   # only the moon's shadow sees it (see WorldLights shadow_caster_mask)
	add_child(mi)

## Day levels: shadow-only slabs in front of every tile deep inside the mass (more than DEPTH tiles from
## open sky), so the sun lights the outside of the ruins but the halls inside stay in cool shade; sun
## shafts leak in around the edges (and show in the volumetric fog as god rays).
const INTERIOR_DEPTH := 5

func _make_interior_occluder(terrain: WorldTerrain) -> void:
	var W := terrain.W
	var H := terrain.H
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(1 << 20)
	var q := PackedInt32Array()
	for i in W * H:
		if terrain.sky[i]:
			dist[i] = 0
			q.append(i)
	var qi := 0
	while qi < q.size():
		var i := q[qi]; qi += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if dist[j] <= dist[i] + 1:
				continue
			dist[j] = dist[i] + 1
			q.append(j)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var z := 1.3
	# the margin (world continuing past the border) shares the shade of the mirrored edge region
	var M := WorldTerrain.MARGIN
	var deep := func(xx: int, yy: int) -> bool:
		var mx := xx
		if mx < 0: mx = 2 - mx
		elif mx >= W: mx = 2 * (W - 1) - mx
		var my := yy
		if my >= H: my = 2 * (H - 1) - my
		mx = clampi(mx, 0, W - 1)
		my = clampi(my, 0, H - 1)
		return dist[my * W + mx] > INTERIOR_DEPTH
	for y in range(0, H + M):
		var x := -M
		while x < W + M:
			if not deep.call(x, y):
				x += 1
				continue
			var x0 := x
			while x < W + M and deep.call(x, y):
				x += 1
			var b := verts.size()
			verts.append_array([Vector3(x0, -y, z), Vector3(x, -y, z), Vector3(x, -y - 1, z), Vector3(x0, -y - 1, z)])
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "SunOccluder"
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = OCCLUDER_LAYER
	add_child(mi)

func update_focus(world_pos: Vector3, _delta: float) -> void:
	# slow parallax drift so the far layers feel even further away
	for i in _layers.size():
		var f: float = [0.55, 0.35, 0.15][i]
		_layers[i].position.x = world_pos.x * f
		_layers[i].position.y = (world_pos.y + 15.0) * f * 0.6
