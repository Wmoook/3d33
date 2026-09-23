extends Node
const GameScript := preload("res://scripts/game/game.gd")
var game
const SPOTS := {"spiregap": Vector2i(222, 70), "falls": Vector2i(150, 140), "keep": Vector2i(300, 70), "grove_top": Vector2i(40, 30), "logo": Vector2i(320, 45)}
func _ready() -> void:
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	for n in SPOTS:
		var t: Vector2i = SPOTS[n]
		for i in 20:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			game.sim.speed_x = 0.0; game.sim.speed_y = 0.0
			await get_tree().physics_frame
		await _wait(2.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://lead_sky_%s.png" % n)
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
