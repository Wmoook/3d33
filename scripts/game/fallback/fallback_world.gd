extends Node3D
## PLACEHOLDER for WorldView (scripts/render/world_view.gd): colored boxes per FG tile, flat BG quads,
## a moody environment. Only used until the world module exists.

var _env: Environment

func build(lvl) -> void:
	var colors := {}
	var f := FileAccess.open("res://assets/ee_ref/blocks.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				var c: Array = d[k].get("avg_rgb", [128, 128, 128])
				colors[int(k)] = Color8(int(c[0]), int(c[1]), int(c[2]))
	var fg_xf: Array[Transform3D] = []
	var fg_col: Array[Color] = []
	var bg_xf: Array[Transform3D] = []
	var bg_col: Array[Color] = []
	for y in lvl.height:
		for x in lvl.width:
			var id: int = lvl.get_fg(x, y)
			if id > 0 and (id < 100 or id == 87) and not id in [1, 2, 3, 4, 5, 6, 7, 8, 22, 26, 28]:
				fg_xf.append(Transform3D(Basis(), Vector3(x + 0.5, -y - 0.5, -0.35)))
				fg_col.append(colors.get(id, Color.GRAY))
			var b: int = lvl.get_bg(x, y)
			if b > 0:
				bg_xf.append(Transform3D(Basis(), Vector3(x + 0.5, -y - 0.5, -2.0)))
				bg_col.append(colors.get(b, Color.DIM_GRAY) * 0.55)
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1.6)
	_add_mm(box, fg_xf, fg_col, 0.7)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_add_mm(quad, bg_xf, bg_col, 0.95)

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.025, 0.05)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.45, 0.5, 0.65)
	_env.ambient_light_energy = 0.6
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.glow_enabled = true
	_env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

func _add_mm(mesh: Mesh, xf: Array[Transform3D], col: Array[Color], rough: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = rough
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)

func update_focus(_p: Vector3, _d: float) -> void:
	pass

func get_environment() -> Environment:
	return _env
