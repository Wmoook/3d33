extends Node
## Overview haze check: grove / Twin Spire / falls at zoom 30, 60, 100, 150 -> user://zoom_<spot>_<z>.png
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := {"grove": Vector2(40, 50), "twin": Vector2(248, 90), "falls": Vector2(150, 145)}
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	await _wait(8.0)
	for n in SPOTS:
		for z in [30.0, 60.0, 100.0, 150.0]:
			game.rig.target_zoom = z
			game.rig.zoom = z
			var t: Vector2 = SPOTS[n]
			for i in 25:
				game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
				game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
				await get_tree().physics_frame
			await _wait(1.0)
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.resize(im.get_width() / 4, im.get_height() / 4)
			im.save_png("user://zoom_%s_%d.png" % [n, int(z)])
	print("zooms done")
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
