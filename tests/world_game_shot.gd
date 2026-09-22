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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("at="):
			var v := a.substr(3).split(",")
			at = Vector2i(int(v[0]), int(v[1]))
		elif a.begins_with("name="):
			nm = a.substr(5)
	GameScript.boot_options = {"no_save": true, "quality": 3}
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
	await _wait(2.5)
	var ov: Node3D = game.collision_overlay
	var parent := ov.get_parent()
	parent.remove_child(ov)
	await _wait(0.3)
	print("overlay in tree: ", ov.is_inside_tree(), " others: ", _find_mm(get_tree().root))
	_shot(nm)
	parent.add_child(ov)
	game.collision_overlay.visible = true
	game.collision_overlay.mark_dirty()
	await _wait(0.3)
	_shot(nm + "_f3")
	get_tree().quit()

func _wait(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://world_game_%s.png" % n)
	print("SHOT world_game_", n)

func _find_mm(n: Node) -> Array:
	var out := []
	if n is MultiMeshInstance3D and n.visible and n.is_visible_in_tree() and n.multimesh and n.multimesh.instance_count > 1000:
		out.append(str(n.get_path()) + ":" + str(n.multimesh.instance_count))
	for c in n.get_children():
		out.append_array(_find_mm(c))
	return out
