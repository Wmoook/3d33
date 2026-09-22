extends Node
## UI legibility on bright (FV Veiled Falls sky) and dark (Odyssey caves) scenes (tools_run_test.sh):
## zone card, trial card, coin-door pill, tutorial pill, trial caption, victory. Output: user://ui_<level>_<what>.png
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for lv in [["forgotten_veil", Vector2(150, 150)], ["odyssey", Vector2(140, 104)]]:
		GameScript.boot_options = {"no_save": true, "level": lv[0], "skip_title": true}
		game = load("res://scenes/main.tscn").instantiate()
		add_child(game)
		while game.state != 3:
			await get_tree().process_frame
		game.input_provider = func(_t: int) -> Dictionary:
			return {}
		game.sim.set_god_mode(true)
		game.tutorial.done = {}
		_teleport(lv[1])
		await _secs(1.9)
		_shot("ui_%s_zone" % lv[0])
		game.tutorial.offer("keys")
		game.hud.toast("COIN DOOR", "needs 1 gold coin  -  you have 0", 5.0)
		game.hud.caption("TRIAL  VII  OF  XVI")
		await _secs(1.0)
		_shot("ui_%s_pills" % lv[0])
		game.sim.coins = 7
		game._trial_complete() if game._trials() else game.zone_card.show_zone("TRIAL VII COMPLETE", "9 trials remain")
		await _secs(1.4)
		_shot("ui_%s_trial" % lv[0])
		game.ghost.best_path = "user://ui_best.eerp"
		game.ghost.best_ticks = -1
		game._on_sim_event(&"complete", {"ticks": 4242})
		await _secs(3.0)
		_shot("ui_%s_victory" % lv[0])
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui_best.eerp"))
		game.queue_free()
		await _secs(0.5)
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
