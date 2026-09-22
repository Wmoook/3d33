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
	# ---- 1) long fall: numeric pass (no screenshots: a 4K readback stalls ~0.5 s and distorts smoothing)
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	_teleport(Vector2(355, 129))
	var tn: int = game._play_ticks
	var marks := [20, 35, 50, 65, 80]
	var mi := 0
	while mi < marks.size():
		await get_tree().process_frame
		if game._play_ticks - tn >= marks[mi]:
			var rr = game.rig
			print("[cam] fall(numeric) t=%d speed=%.1f tiles/s  ball is %.2f tiles %s screen center (half-height %.1f)" % [game._play_ticks - tn,
				(game.sim.py - game.sim.prev_py) * 100.0 / 16.0, absf(game._render_pos.y - rr.focus.y),
				"above" if game._render_pos.y > rr.focus.y else "below", rr.half_extents().y])
			mi += 1
	await _secs(1.5)
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
	# ---- 2) arrow field: numeric pass (no screenshots), then a 4-frame visual strip
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	for pass_i in 2:
		var shoot := pass_i == 1
		_teleport(Vector2(54, 86))
		await _secs(0.3)
		var flips := 0
		var last_g: Vector2i = game.sim.gravity_dir
		var cam_hist := []
		var ball_hist := []
		var max_cam := 0.0
		var max_ball := 0.0
		var max_rot := 0.0
		var prev_rot: Vector3 = game.rig.cam.global_rotation
		var frames := 0
		var strip := 0
		var t_hist := []
		var max_trauma := 0.0
		var acc_cam: Array[float] = []
		var acc_ball: Array[float] = []
		while frames < 240:
			await get_tree().process_frame
			frames += 1
			if game.sim.gravity_dir != last_g:
				flips += 1
				last_g = game.sim.gravity_dir
			cam_hist.append(game.rig.focus)
			ball_hist.append(game._render_pos)
			t_hist.append((t_hist[-1] if t_hist.size() > 0 else 0.0) + get_process_delta_time())
			max_trauma = maxf(max_trauma, game.rig.trauma)
			var rot: Vector3 = game.rig.cam.global_rotation
			max_rot = maxf(max_rot, rad_to_deg((rot - prev_rot).length()))
			prev_rot = rot
			var n := cam_hist.size()
			if n >= 3 and not shoot:
				var d1: float = 1.0 / 60.0  # fixed step: frame-time noise would dominate a true derivative
				var d2: float = d1
				acc_cam.append((((cam_hist[n - 1] - cam_hist[n - 2]) / d2) - ((cam_hist[n - 2] - cam_hist[n - 3]) / d1)).length() / ((d1 + d2) * 0.5))
				acc_ball.append((((ball_hist[n - 1] - ball_hist[n - 2]) / d2) - ((ball_hist[n - 2] - ball_hist[n - 3]) / d1)).length() / ((d1 + d2) * 0.5))
				max_cam = maxf(max_cam, (cam_hist[n - 1] - 2.0 * cam_hist[n - 2] + cam_hist[n - 3]).length())
				max_ball = maxf(max_ball, (ball_hist[n - 1] - 2.0 * ball_hist[n - 2] + ball_hist[n - 3]).length())
			if shoot and strip < 4 and frames == 60 + strip * 6:
				_shot("cam_arrow_%d" % strip)
				strip += 1
		if not shoot:
			acc_cam.sort()
			acc_ball.sort()
			var p95 := func(a: Array[float]) -> float: return a[int(a.size() * 0.95)] if a.size() > 0 else 0.0
			var med := func(a: Array[float]) -> float: return a[a.size() / 2] if a.size() > 0 else 0.0
			print("[cam] arrow field 2nd-difference x 3600 (tiles/s^2 @60fps): camera focus median %.1f p95 %.1f | ball median %.1f p95 %.1f | max shake trauma %.2f" % [med.call(acc_cam), p95.call(acc_cam), med.call(acc_ball), p95.call(acc_ball), max_trauma])
			print("[cam] arrow field (numeric): gravity flips=%d in %d frames; max 2nd-diff camera=%.4f ball=%.4f tiles/frame^2; max camera rotation step=%.3f deg/frame" % [flips, frames, max_cam, max_ball, max_rot])
	# ---- 3) ghost visual: record a run walking right, make it the best, then replay while standing still
	var g = game.ghost
	g.best_path = "user://test_ghost_vis.eerp"
	g.best_ticks = -1
	g.best = null
	game.input_provider = func(t: int) -> Dictionary:
		return {"right": t > 20, "jump": t > 90 and t < 100}
	game.restart_run()
	while game._play_ticks < 160:
		await get_tree().process_frame
	g.on_complete(game._play_ticks)
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.restart_run()
	while game._play_ticks < 110:
		await get_tree().process_frame
	_shot("cam_ghost")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.best_path))
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
