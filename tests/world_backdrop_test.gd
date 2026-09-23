extends Node3D
## Backdrop-mode smoke test: a crop of Forgotten Veil (the keep) rebuilt as a synthetic EELevel and drawn by
## WorldTerrain.build_backdrop() far behind the plane, twice (near/far haze). Saves user://world_backdrop_test.png.
## Run: bash tools_run_test.sh res://tests/world_backdrop_test.tscn

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	WorldPalette.level_id = "forgotten_veil"
	var cfg := LevelCatalog.get_config("forgotten_veil")
	var src := EELevel.load_file(str(cfg.get("level_file", "")))
	var r := Rect2i(282, 58, 60, 54)
	var lvl := EELevel.new()
	lvl.width = r.size.x
	lvl.height = r.size.y
	lvl.fg.resize(r.size.x * r.size.y)
	lvl.bg.resize(r.size.x * r.size.y)
	for y in r.size.y:
		for x in r.size.x:
			var edge := x == 0 or y == 0 or x == r.size.x - 1 or y == r.size.y - 1
			lvl.fg[y * r.size.x + x] = 0 if edge else src.get_fg(r.position.x + x, r.position.y + y)
			lvl.bg[y * r.size.x + x] = 0 if edge else src.get_bg(r.position.x + x, r.position.y + y)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.78, 0.9)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var t0 := Time.get_ticks_msec()
	var a := WorldTerrain.build_backdrop(lvl, Vector3(-70, 40, -80), 1.8, 0.15)
	add_child(a)
	var b := WorldTerrain.build_backdrop(lvl, Vector3(40, 30, -140), 2.5, 0.45)
	add_child(b)
	print("BACKDROP built 2 instances in %d ms" % (Time.get_ticks_msec() - t0))
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(20, -10, 30)
	cam.far = 1000.0
	add_child(cam)
	cam.current = true
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world_backdrop_test.png")
	get_tree().quit()
