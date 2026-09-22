extends Node
## Multi-level shell check (tools_run_test.sh): Odyssey title with the level select, switch to Forgotten Veil
## (reboot + loading reveal of its map), FV title, FV gameplay shots, piano note detection, pause menu.
## Output: user://lv_*.png
const GameScript := preload("res://scripts/game/game.gd")
var game

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "level": "odyssey"}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _state(1)
	await _secs(6.0)
	_shot("lv_odyssey_title")
	game.title.select_delta(1)
	await _secs(0.6)
	_shot("lv_odyssey_select_fv")
	game.switch_level(str(game.title.selected_cfg().id))
	await _secs(0.3)
	game = get_child(get_child_count() - 1)
	await _secs(1.6)
	_shot("lv_fv_loading")
	await _state(1)
	await _secs(6.0)
	_shot("lv_fv_title")
	game.press_start()
	await _state(3)
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.tutorial.done = {"move": true, "keys": true, "arrows": true, "god": true}
	await _secs(2.0)
	_shot("lv_fv_spawn")
	game.sim.set_god_mode(true)
	for tile in [Vector2(150, 150), Vector2(195, 90), Vector2(300, 60), Vector2(100, 185)]:
		_teleport(tile)
		await _secs(2.0)
		_shot("lv_fv_%d_%d" % [int(tile.x), int(tile.y)])
	# piano: count 77 tiles and play one through the shell path
	var pianos: Array = game.level.find_all(77)
	print("[lv] FV piano blocks: %d; zone at spawn: %s; music bed now: %s" % [pianos.size(), game._zone_info.name, game.audio._current_bed])
	if pianos.size() > 0:
		var t: Vector2i = pianos[0]
		print("[lv] piano (%d,%d) note %s" % [t.x, t.y, game.level.get_extra(t.x, t.y).get("rotation", 0)])
	game._pause()
	await _secs(0.6)
	_shot("lv_fv_pause")
	get_tree().quit()

func _teleport(tile: Vector2) -> void:
	game.sim.px = tile.x * 16.0
	game.sim.py = tile.y * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))

func _state(st: int) -> void:
	while not is_instance_valid(game) or game.state != st:
		await get_tree().process_frame

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
	print("[shot] ", n)

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
