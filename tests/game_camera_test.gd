extends Node
## Visual + numeric camera check (run via tools_run_test.sh):
##  1) long fall (56-tile shaft at x=355 in the Frozen Depths): 3 mid-fall shots, logs fall look-ahead
##  2) run through the Maelstrom arrow field (gravity flips): 4-frame strip, logs gravity flips vs camera jerk
## Output: user://cam_fall_*.png, user://cam_arrow_*.png + numbers on stdout.
const GameScript := preload("res://scripts/game/game.gd")
var game

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"skip_title": true, "no_save": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 3:
		await get_tree().process_frame
	game.hud.show_hints = false
	await _secs(1.0)
	# ---- 1) long fall
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	_teleport(Vector2(355, 129))
	var t0: int = game._play_ticks
	var shots := [35, 60, 85]
	var i := 0
	while i < shots.size():
		await get_tree().process_frame
		if game._play_ticks - t0 >= shots[i]:
			var r = game.rig
			var vy: float = (game.sim.py - game.sim.prev_py) * 100.0 / 16.0
			print("[cam] fall t=%d  speed=%.1f tiles/s  fall_look=%s  focus-player=%s" % [game._play_ticks - t0, vy, r._fall_look, Vector2(r.focus.x, r.focus.y) - Vector2(game._render_pos.x, game._render_pos.y)])
			_shot("cam_fall_%d" % i)
			i += 1
	await _secs(1.5)
	# ---- 2) arrow field
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	_teleport(Vector2(54, 86))
	await _secs(0.3)
	var flips := 0
	var last_g: Vector2i = game.sim.gravity_dir
	var prev_pos := []
	var max_jerk := 0.0
	var max_raw_jerk := 0.0
	var prev_ball := []
	var strip := 0
	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < 3000:
		await get_tree().process_frame
		if game.sim.gravity_dir != last_g:
			flips += 1
			last_g = game.sim.gravity_dir
		var cp: Vector3 = game.rig.cam.global_position
		prev_pos.append(cp)
		prev_ball.append(game._render_pos)
		if prev_pos.size() >= 3:
			var n := prev_pos.size()
			max_jerk = maxf(max_jerk, (prev_pos[n - 1] - 2.0 * prev_pos[n - 2] + prev_pos[n - 3]).length())
			max_raw_jerk = maxf(max_raw_jerk, (prev_ball[n - 1] - 2.0 * prev_ball[n - 2] + prev_ball[n - 3]).length())
		if strip < 4 and prev_pos.size() == 40 + strip * 8:
			_shot("cam_arrow_%d" % strip)
			strip += 1
	print("[cam] arrow field: gravity flips=%d in 3 s, max camera 2nd-diff=%.4f tiles/frame^2 vs ball %.4f" % [flips, max_jerk, max_raw_jerk])
	get_tree().quit()

func _teleport(tile: Vector2) -> void:
	game.sim.px = tile.x * 16.0
	game.sim.py = tile.y * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.sim.speed_x = 0.0
	game.sim.speed_y = 0.0
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
	print("[shot] ", n)

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
