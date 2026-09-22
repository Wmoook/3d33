extends Node
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.booted
	await _wait(0.5)
	game.press_start()
	await game.ready_to_play
	# walk left from spawn toward the arrows/portal area, jumping periodically
	game.input_provider = func(t: int) -> Dictionary:
		return {"right": t > 30 and t < 900, "jump": (t % 120) > 95}
	for i in 6:
		await _wait(1.3)
		_shot("play%d" % i)
		print("t=", game.sim.ticks(), " pos=", game.sim.px / 16.0, ",", game.sim.py / 16.0, " fps=", Engine.get_frames_per_second())
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://lead_%s.png" % n)
