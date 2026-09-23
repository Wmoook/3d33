extends Node
## FV interaction juice shots in the real game: intro materialize, coin-door unseal (#16 grand gate),
## purple switch rune pulse, boost launch streak, portal ripple. Saves user://fx_juice_<name>.png.
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	await _real(0.3)
	_shot("intro_0.3s")
	await _real(2.0)
	game.sim.set_god_mode(true)
	# grand coin door #16 next to the spawn grove
	_tp(Vector2(47, 53)); await _real(2.0)
	game.sim.coins = 16
	await _real(0.25)
	_shot("coindoor16")
	# purple switch #1 at (199,42) -> its doors at y 88-89
	_tp(Vector2(196, 60)); game.rig.set("target_zoom", 60.0); await _real(2.5)
	game.sim._switches[1] = true
	game.sim.sim_event.emit(&"switch", {"kind": &"purple", "id": 1, "on": true})
	await _real(0.7)
	_shot("switch_pulse")
	game.rig.set("target_zoom", 30.0)
	# boost row (287-332, 133)
	_tp(Vector2(296, 132)); await _real(2.0)
	_tp(Vector2(300, 133)); await _real(0.12)
	_shot("boost_launch")
	# portal pair
	_tp(Vector2(245, 80)); await _real(2.0)
	game.sim.sim_event.emit(&"portal", {"from": Vector2i(246, 80), "to": Vector2i(254, 80)})
	await _real(0.15)
	_shot("portal_ripple")
	get_tree().quit()
func _tp(t: Vector2) -> void:
	game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
	game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://fx_juice_%s.png" % n)
	print("saved fx_juice_", n)
func _real(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().process_frame
