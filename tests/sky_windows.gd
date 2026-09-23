extends Node
## Tower windows: prints the window list, then shoots user://win_<spot>[_<variant>].png.
## Args: spots (twin, gspire, hall) + "diag" (glass off / voxel off / depth off variants) + "move" (3-frame pan).
const GameScript := preload("res://scripts/game/game.gd")
var SPOTS := {"twin": Vector2(252, 86), "gspire": Vector2(213, 80), "hall": Vector2(350, 84)}
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	var wv = game.world
	var depth = wv.get("depth")
	if depth:
		for w in depth.windows:
			print("WIN rect=", w["rect"], " r=", w["r"], " stained=", w["stained"], " frost=", w["frost"])
	await _wait(6.0)   # deferred voxel / backdrop pieces
	var args := OS.get_cmdline_user_args()
	for n in SPOTS:
		if not args.is_empty() and not args.has(n) and not args.has("all"):
			continue
		var p: Vector2 = SPOTS[n]
		await _put(p)
		await _shot(n)
		if args.has("diag"):
			var glass: Node3D = depth.get_node_or_null("WindowGlass") if depth else null
			if glass:
				glass.visible = false
				await _shot(n + "_noglass")
				glass.visible = true
			var vox = wv.get("voxel")
			if vox and args.has("novoxel"):
				for c in vox.get_children():
					if c is GeometryInstance3D:
						(c as GeometryInstance3D).visible = false
				await _shot(n + "_novoxel")
		if args.has("move"):
			for k in 3:
				await _put(p + Vector2(-6 + k * 6, 0))
				await _shot("%s_move%d" % [n, k])
	get_tree().quit()
func _put(t: Vector2) -> void:
	for i in 30:
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		await get_tree().physics_frame
	await _wait(1.0)
func _shot(n: String) -> void:
	await _wait(0.4)
	await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	im.resize(im.get_width() / 2, im.get_height() / 2)
	im.save_png("user://win_%s.png" % n)
	print("saved win_", n)
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
