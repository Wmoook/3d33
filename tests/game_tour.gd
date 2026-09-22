extends Node
## UX tour (run via tools_run_test.sh): title screen, then one gameplay shot per world zone (zone card
## visible), the first-run tutorial pill, and the victory screen.
## Output: user://tour_title.png, user://tour_zone_<name>.png, user://tour_tutorial.png, user://tour_victory.png
const GameScript := preload("res://scripts/game/game.gd")
var game

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 1:  # TITLE
		await get_tree().process_frame
	await _secs(6.5)
	_shot("tour_title")
	game.tutorial.done = {}
	game.press_start()
	while game.state != 3:
		await get_tree().process_frame
	await _secs(1.2)
	_shot("tour_tutorial")
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.sim.set_god_mode(true)
	game.hud.show_hints = false
	# one representative open tile per world zone: the non-solid tile nearest the zone's centroid
	var sums := {}
	var lvl = game.level
	for y in range(0, lvl.height, 2):
		for x in range(0, lvl.width, 2):
			var z = game.world.get_zone_at(Vector2i(x, y))
			var e: Array = sums.get(z, [Vector2.ZERO, 0, []])
			e[0] += Vector2(x, y)
			e[1] += 1
			if not game.sim.is_tile_solid_now(x, y) and not game.sim.is_tile_solid_now(x, y + 1):
				e[2].append(Vector2(x, y))
			sums[z] = e
	for z in sums:
		var e: Array = sums[z]
		if e[2].is_empty():
			continue
		var c: Vector2 = e[0] / float(e[1])
		var best: Vector2 = e[2][0]
		for p in e[2]:
			if p.distance_squared_to(c) < best.distance_squared_to(c):
				best = p
		_teleport(best)
		await _secs(1.9)
		print("[tour] zone %s at %s -> card '%s'" % [z, best, game._zone_info.name])
		_shot("tour_zone_%s" % str(z))
	# victory
	game.ghost.best_path = "user://tour_best.eerp"
	game.ghost.best_ticks = -1
	game._on_sim_event(&"complete", {"ticks": 12345})
	await _secs(3.2)
	_shot("tour_victory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tour_best.eerp"))
	get_tree().quit()

func _teleport(tile: Vector2) -> void:
	game.sim.px = tile.x * 16.0
	game.sim.py = tile.y * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
	print("[shot] ", n)

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
