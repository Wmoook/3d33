extends Node
## FV "trials" framing check (tools_run_test.sh): title tagline, HUD "TRIALS 0/16", trial-complete card, victory.
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "level": "forgotten_veil"}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 1:
		await get_tree().process_frame
	await _secs(6.0)
	_shot("tr_title")
	game.press_start()
	while game.state != 3:
		await get_tree().process_frame
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.tutorial.done = {"move": true, "keys": true, "arrows": true, "god": true}
	await _secs(4.0)
	game.sim.coins = 4
	game._on_sim_event(&"coin", {"tile": Vector2i(0, 0)})
	await _secs(1.6)
	_shot("tr_trial_complete")
	game.sim.coins = 16
	game.ghost.best_path = "user://tr_best.eerp"
	game.ghost.best_ticks = -1
	game._on_sim_event(&"complete", {"ticks": 54321})
	await _secs(3.2)
	_shot("tr_victory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tr_best.eerp"))
	print("[tr] roman 4=%s 9=%s 14=%s 16=%s, world trials api: %s" % [game.roman(4), game.roman(9), game.roman(14), game.roman(16), game.world.has_method(&"get_trial_at")])
	get_tree().quit()
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
