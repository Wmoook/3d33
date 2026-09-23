extends Node
## Mean luminance of the frame at a few FV interior spots (zoom 30): regression check for lighting changes.
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [Vector2(52, 122), Vector2(90, 180), Vector2(300, 150), Vector2(200, 130)]
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
	for t in SPOTS:
		for i in 30:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			await get_tree().physics_frame
		await _wait(1.5)
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		im.resize(320, 171)
		var s := 0.0
		for y in im.get_height():
			for x in im.get_width():
				s += im.get_pixel(x, y).get_luminance()
		print("LUM %s %.4f" % [str(t), s / (320.0 * 171.0)])
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
