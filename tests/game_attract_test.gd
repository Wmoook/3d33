extends Node
## Title flyover along physics' route (with portal cuts) + attract mode (recorded descent after idle).
## Run via tools_run_test.sh. Output: user://attract_flyover_*.png, user://attract_demo_*.png
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 1:
		await get_tree().process_frame
	print("[attract] cinematic keys: %d, cuts: %d" % [game.rig._cine_keys.size(), game.rig._cine_keys.filter(func(k): return k.get("cut", false)).size()])
	var cuts := [0]
	game.rig.cinematic_cut.connect(func(): cuts[0] += 1)
	await _secs(6.0)
	_shot("attract_flyover_0")
	# fast-forward the flyover to check it moves along the route
	game.rig._cine_s += 6.0
	await _secs(1.0)
	_shot("attract_flyover_1")
	game._title_idle = game.ATTRACT_IDLE + 1.0
	await _secs(0.5)
	print("[attract] attract started=%s" % game._attract)
	var t0: int = game._attract_rep.cursor if game._attract_rep else 0
	await _secs(6.0)
	_shot("attract_demo_0")
	await _secs(8.0)
	_shot("attract_demo_1")
	print("[attract] replay cursor %d -> %d / %d, ball at %s, cuts seen %d" % [t0, game._attract_rep.cursor, game._attract_rep.tick_count(), Vector2(game.sim.px, game.sim.py) / 16.0, cuts[0]])
	game.press_start()
	await _secs(3.0)
	print("[attract] after start: state=%s ball=%s attract=%s" % [game.state, Vector2(game.sim.px, game.sim.py) / 16.0, game._attract])
	get_tree().quit()
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
