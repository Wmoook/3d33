extends Node
## FV: new showcase title keys, Summit Shrine music, victory camera framing the shrine (tools_run_test.sh).
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "level": "forgotten_veil"}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 1:
		await get_tree().process_frame
	for i in 4:
		game.rig._cine_s = float(i) + 0.3
		await _secs(5.5 if i == 0 else 1.6)
		_shot("sh_title_%d" % i)
	game.press_start()
	while game.state != 3:
		await get_tree().process_frame
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.tutorial.done = {"move": true, "keys": true, "arrows": true, "god": true}
	game.sim.set_god_mode(true)
	await _secs(1.0)
	_teleport(Vector2(391, 73))
	await _secs(4.5)
	print("[sh] at shrine: zone=%s bed=%s" % [game._zone_info.name, game.audio._current_bed])
	game.ghost.best_path = "user://sh_best.eerp"
	game.ghost.best_ticks = -1
	game._on_sim_event(&"complete", {"ticks": 99999})
	await _secs(1.6)
	_shot("sh_victory_frame")
	await _secs(2.8)
	_shot("sh_victory_card")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://sh_best.eerp"))
	get_tree().quit()
func _teleport(tile: Vector2) -> void:
	game.sim.px = tile.x * 16.0
	game.sim.py = tile.y * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
