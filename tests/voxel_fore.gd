extends Node
## WorldVoxel phase 2 (foreground band) safety + look test, in game (FV, god mode, EE camera).
## For each spot: a normal shot, an F3 (collision overlay) shot, and a SAFETY DIFF: the frame with the
## foreground visible vs hidden is compared at every non-coverable tile (air, gameplay blocks, doors, mass
## edges; 3x3 samples inset 0.15) and around the ball; any visible change there = the foreground covered
## something it must not. Then the ball is moved along a short path next to foreground pieces and re-checked.
##   bash tools_run_test.sh res://tests/voxel_fore.tscn [-- only=spawn,keep]
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := {"spawn": Vector2i(2, 56), "grove": Vector2i(40, 40), "falls": Vector2i(150, 165),
	"keep": Vector2i(300, 70), "sanctum": Vector2i(330, 152), "halls": Vector2i(55, 100), "spire_mid": Vector2i(197, 115)}
var game
var wv: WorldView
var vx: WorldVoxel
var total_bad := 0

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = Array(a.substr(5).split(","))
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	wv = game.world as WorldView
	vx = wv.voxel
	while not vx.is_ready:
		await get_tree().process_frame
	vx.finish_fade()
	await _wait(2.0)
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	print("FORE pieces %d, voxels %d" % [vx.fore.piece_count, vx.fore.voxel_count])
	for n in SPOTS:
		if not only.is_empty() and not only.has(n):
			continue
		var t: Vector2i = SPOTS[n]
		await _place(Vector2(t))
		await _wait(2.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://voxel_fore_%s.png" % n)
		await _check(n)
		wv.set_debug_grid(true)
		await _wait(0.4)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://voxel_fore_%s_f3.png" % n)
		wv.set_debug_grid(false)
		# moving: the ball walks 6 tiles right in steps, checked at each step
		for s in 3:
			await _place(Vector2(t) + Vector2(2.0 * (s + 1), 0.0))
			await _wait(0.5)
			await _check("%s_move%d" % [n, s])
	print("FORE SAFETY TOTAL: %d bad samples %s" % [total_bad, "OK" if total_bad == 0 else "FAIL"])
	get_tree().quit()

func _place(t: Vector2) -> void:
	for i in 12:
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		game.sim.speed_x = 0.0; game.sim.speed_y = 0.0
		await get_tree().physics_frame

func _ball() -> Vector3:
	return Vector3(game.sim.px / 16.0 + 0.5, -game.sim.py / 16.0 - 0.5, 0.0)

func _check(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var on := get_viewport().get_texture().get_image()
	vx.fore.visible = false
	await _wait(0.35)   # let TAA / temporal effects settle
	await RenderingServer.frame_post_draw
	var off := get_viewport().get_texture().get_image()
	vx.fore.visible = true
	var cam := get_viewport().get_camera_3d()
	var vs := Vector2(on.get_width(), on.get_height())
	var vp := get_viewport().get_visible_rect().size
	var fm := vx.fore
	var ball := _ball()
	var bad := 0
	var n := 0
	var changed := 0
	for ty in fm.H:
		for tx in fm.W:
			var cover := fm.mask[ty * fm.W + tx] > 0
			var near_ball := Vector2(tx + 0.5 - ball.x, -ty - 0.5 - ball.y).length() < WorldVoxelFore.BALL_R - 0.3
			if cover and not near_ball:
				continue
			for sy in 3:
				for sx in 3:
					var w := Vector3(tx + 0.15 + 0.35 * sx, -ty - 0.15 - 0.35 * sy, 0.0)
					if cam.is_position_behind(w):
						continue
					var sp := cam.unproject_position(w) / vp * vs
					if sp.x < 1 or sp.y < 1 or sp.x >= vs.x - 1 or sp.y >= vs.y - 1:
						continue
					n += 1
					var a := on.get_pixelv(Vector2i(sp))
					var b := off.get_pixelv(Vector2i(sp))
					var dd := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
					if dd > 0.12:
						bad += 1
						if bad <= 5:
							print("   %s: tile (%d,%d) changed by %.3f" % [nm, tx, ty, dd])
	# how much of the frame the foreground actually draws (anywhere)
	for py in range(0, int(vs.y), 16):
		for px in range(0, int(vs.x), 16):
			var a := on.get_pixel(px, py)
			var b := off.get_pixel(px, py)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				changed += 1
	total_bad += bad
	print("FORE SAFETY %s: %d / %d protected samples changed %s; foreground covers %.1f%% of the frame" % [nm, bad, n,
		"OK" if bad == 0 else "FAIL", 100.0 * changed / ((vs.x / 16.0) * (vs.y / 16.0))])

func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		vx.update_focus(_ball(), 0.016)
		await get_tree().process_frame
