extends Node
## In-game world readability shot (real shell + actors): teleports the (god-mode) player to a spot and
## saves user://world_game_<name>.png plus a _f3 variant with the collision overlay.
## Run: bash tools_run_test.sh res://tests/world_game_shot.tscn [-- at=145,50 name=tunnel]

const GameScript := preload("res://scripts/game/game.gd")
var game

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var at := Vector2i(145, 50)
	var nm := "tunnel"
	var key := ""
	var zoom := 0.0
	var hide: PackedStringArray = []
	var lvl_id := "odyssey"
	var q := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("at="):
			var v := a.substr(3).split(",")
			at = Vector2i(int(v[0]), int(v[1]))
		elif a.begins_with("level="):
			lvl_id = a.substr(6)
		elif a.begins_with("key="):
			key = a.substr(4)
		elif a.begins_with("name="):
			nm = a.substr(5)
		elif a == "nodepth":
			WorldView.depth_enabled = false
		elif a == "novoxel":
			WorldVoxel.enabled = false
		elif a.begins_with("hide="):
			hide = a.substr(5).split(",")
		elif a.begins_with("zoom="):
			zoom = float(a.substr(5))
		elif a == "noglass":
			WorldDepth.debug_no_glass = true
		elif a.begins_with("q="):
			q = int(a.substr(2))
		elif a == "skin":
			WorldView.depth_smooth_skin = true
	GameScript.boot_options = {"no_save": true, "quality": q, "level": lvl_id}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	if game.state == 0:
		await game.booted
	await _wait(2.0)
	game.press_start()
	while game.state != 3:
		await get_tree().process_frame
	game.input_provider = func(_t: int) -> Dictionary: return {}
	var sim = game.sim
	if sim.has_method(&"set_god_mode"):
		sim.set_god_mode(true)
	for i in 30:
		sim.px = at.x * 16.0; sim.py = at.y * 16.0
		sim.prev_px = sim.px; sim.prev_py = sim.py
		sim.speed_x = 0.0; sim.speed_y = 0.0
		await get_tree().physics_frame
	if key != "":
		sim._set_key(StringName(key), true)
	for nm_h in hide:
		var hn: Node = game.find_child(nm_h, true, false)
		if hn is Node3D:
			(hn as Node3D).visible = false
			print("hid ", hn.get_path())
		elif hn:
			print("hide: not a Node3D: ", nm_h)
		else:
			print("hide: no node ", nm_h)
	if zoom > 0.0:
		var rig = game.find_child("CameraRig", true, false)
		if rig == null:
			for c in game.find_children("*", "", true, false):
				if c.get("target_zoom") != null:
					rig = c
					break
		if rig:
			rig.target_zoom = zoom
			rig.zoom = zoom
	await _wait(2.0)
	var rig = game.find_child("CameraRig", true, false)
	if rig == null:
		for c in game.find_children("*", "", true, false):
			if c.get("target_zoom") != null:
				rig = c
				break
	Engine.max_fps = 144
	game.input_provider = func(_t: int) -> Dictionary: return {"right": true}
	var xs: Array[float] = []
	var last: float = rig.focus.x
	for i in 300:
		await get_tree().process_frame
		var fx: float = rig.focus.x
		xs.append(fx - last)
		last = fx
	var zeros := 0
	var moving := 0
	var jit := 0.0
	var prev := 0.0
	for i in range(60, xs.size()):
		var d: float = xs[i]
		if absf(d) > 0.0005:
			moving += 1
		elif moving > 0:
			zeros += 1
		if i > 60:
			jit += absf(d - prev)
		prev = d
	print("CAMSTEP frames=%d moving=%d zero_frames_while_moving=%d mean_abs_change_of_step=%.5f" % [xs.size() - 60, moving, zeros, jit / float(xs.size() - 61)])
	print("CAMSTEP sample ", xs.slice(120, 150))
	get_tree().quit()

func _wait(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world_game_%s.png" % n)
	print("SHOT world_game_", n)

