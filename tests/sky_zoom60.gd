extends Node
## Vista survey at zoom 60 (widest): a grid of spots over Forgotten Veil -> user://z60_<x>_<y>.png (half res).
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	game.rig.target_zoom = 60.0
	game.rig.zoom = 60.0
	await _wait(8.0)   # deferred voxel + backdrop pieces
	for ty in [20, 60, 100, 140, 180]:
		for tx in [30, 100, 170, 240, 310, 370]:
			for i in 20:
				game.sim.px = tx * 16.0; game.sim.py = ty * 16.0
				game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
				await get_tree().physics_frame
			await _wait(0.8)
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.resize(im.get_width() / 4, im.get_height() / 4)
			im.save_png("user://z60_%d_%d.png" % [tx, ty])
	print("z60 done")
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
