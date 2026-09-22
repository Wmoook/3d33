extends Node
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	pass
	GameScript.boot_options = {"no_save": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.booted
	await _wait(1.0)
	game.press_start()
	await game.ready_to_play
	var l: EELevel = game.sim.level
	var best := []
	for id in [1, 2, 3, 4]:
		var bd := 1e9; var bt := Vector2i()
		for t in l.find_all(id):
			var d: float = (Vector2(t) - Vector2(65, 11)).length()
			if d < bd: bd = d; bt = t
		best.append(bt)
		print("nearest id ", id, " at ", bt, " dist ", bd)
	game.input_provider = func(_t: int) -> Dictionary: return {}
	await _wait(1.5)
	_shot("spawn")
	game.sim.set_god_mode(true)
	for i in best.size():
		var t: Vector2i = best[i]
		game.sim.px = t.x * 16.0 + 48.0; game.sim.py = t.y * 16.0 - 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		await _wait(2.0)
		_shot("id%d" % (i + 1))
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://lead_%s.png" % n)
