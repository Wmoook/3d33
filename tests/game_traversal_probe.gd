extends Node
## Traversal hitch probe (no screenshots; run via tools_run_test.sh):
## god-mode flies a long path through every zone at normal god speed, TWICE. Logs every frame > 25 ms with
## tile position + zone, and summarises per zone and per pass. Hitches that happen on pass 1 but not pass 2 are
## first-use costs (shader/pipeline compile, particle spin-up, uploads); ones on both passes are steady costs.
## Run: bash tools_run_test.sh res://tests/game_traversal_probe.tscn [-- --one-pass]
const GameScript := preload("res://scripts/game/game.gd")
const PATH := [Vector2(65, 9), Vector2(130, 8), Vector2(200, 8), Vector2(300, 9), Vector2(385, 10), Vector2(345, 45),
	Vector2(340, 90), Vector2(300, 95), Vector2(320, 150), Vector2(300, 185), Vector2(230, 185), Vector2(150, 185),
	Vector2(100, 150), Vector2(140, 105), Vector2(215, 95), Vector2(230, 130), Vector2(120, 140), Vector2(40, 110),
	Vector2(40, 45), Vector2(120, 45), Vector2(65, 9)]
const HITCH_MS := 25.0
var game
var _wp := 0
var _pass := 0
var _log := []

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"skip_title": true, "no_save": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 3:
		await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.hud.show_hints = false
	game.input_provider = _steer
	game.sim.set_god_mode(true)
	await _frames(30)
	var passes := 1 if "--one-pass" in OS.get_cmdline_user_args() else 2
	for p in passes:
		_pass = p
		_wp = 0
		_teleport(PATH[0])
		await _frames(10)
		var frames := 0
		var t_pass := Time.get_ticks_msec()
		var total_ms := 0.0
		var last := Time.get_ticks_usec()
		var per_zone := {}
		var last_zone := ""
		var zone_change_ms := -100000
		var world_zone := &""
		var wz_change_ms := -100000
		var near_change := 0
		var hitches_total := 0
		while _wp < PATH.size() and Time.get_ticks_msec() - t_pass < 180000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			frames += 1
			total_ms += ms
			var tile := Vector2i(int(game._render_pos.x), int(-game._render_pos.y))
			var zone: String = str(game._zone_info.name)
			if zone != last_zone:
				last_zone = zone
				zone_change_ms = Time.get_ticks_msec()
			var wz = game.world.current_zone if "current_zone" in game.world else &""
			if wz != world_zone:
				world_zone = wz
				wz_change_ms = Time.get_ticks_msec()
			var since := mini(Time.get_ticks_msec() - zone_change_ms, Time.get_ticks_msec() - wz_change_ms)
			var z: Dictionary = per_zone.get(zone, {"frames": 0, "ms": 0.0, "hitches": 0, "worst": 0.0})
			z.frames += 1
			z.ms += ms
			z.worst = maxf(z.worst, ms)
			if ms > HITCH_MS:
				z.hitches += 1
				_log.append([p, ms, tile, zone, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), since])
				hitches_total += 1
				if since < 1500:
					near_change += 1
			per_zone[zone] = z
		print("[trav] pass %d: %d frames, %.1f s, avg %.2f ms (%.0f fps)" % [p + 1, frames, total_ms / 1000.0, total_ms / maxi(frames, 1), 1000.0 * frames / maxf(total_ms, 1.0)])
		print("[trav]   hitches: %d total, %d within 1.5 s of a zone change (shell card or world atmosphere)" % [hitches_total, near_change])
		for zn in per_zone:
			var z: Dictionary = per_zone[zn]
			print("[trav]   %-22s frames %5d  avg %6.2f ms  worst %7.1f ms  hitches>25ms %d" % [zn, z.frames, z.ms / z.frames, z.worst, z.hitches])
	_log.sort_custom(func(a, b): return a[1] > b[1])
	print("[trav] worst frames (pass, ms, tile, zone, draws):")
	for e in _log.slice(0, 30):
		print("[trav]   pass %d  %7.1f ms  tile %s  %s  draws %d  %d ms after zone change" % [e[0] + 1, e[1], e[2], e[3], e[4], e[5]])
	get_tree().quit()

## God-mode steering toward the next waypoint (EE god flight, arrow keys).
func _steer(_t: int) -> Dictionary:
	if _wp >= PATH.size():
		return {}
	var here := Vector2(game.sim.px + 8.0, game.sim.py + 8.0) / 16.0
	var to: Vector2 = PATH[_wp] - here
	if to.length() < 2.0:
		_wp += 1
		return {}
	return {"left": to.x < -0.8, "right": to.x > 0.8, "up": to.y < -0.8, "down": to.y > 0.8}

func _teleport(tile: Vector2) -> void:
	game.sim.px = tile.x * 16.0
	game.sim.py = tile.y * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
