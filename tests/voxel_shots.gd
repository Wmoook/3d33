extends Node
## In-game WorldVoxel screenshots (Forgotten Veil, god mode, EE camera). Saves user://voxel_<spot>.png.
##   bash tools_run_test.sh res://tests/voxel_shots.tscn [-- only=grove,falls]
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := {"spawn": Vector2i(2, 56), "grove": Vector2i(40, 40), "falls": Vector2i(150, 165),
	"spire_top": Vector2i(200, 30), "keep": Vector2i(300, 70), "shrine": Vector2i(390, 78),
	"spiregap": Vector2i(222, 70), "valley": Vector2i(160, 120), "bottom": Vector2i(200, 192), "sky": Vector2i(120, 20)}
var game

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
	var wv: WorldView = game.world as WorldView
	var vx: WorldVoxel = wv.get("voxel") as WorldVoxel
	if vx == null:
		# world_view not patched yet: build it here, hide the vista's near land it replaces
		vx = WorldVoxel.new()
		vx.name = "Voxel"
		wv.add_child(vx)
		vx.setup(wv.terrain, wv.depth, wv.vista)
		vx.start()
		for c in wv.vista.get_children():
			if str(c.name) in ["VistaLandNear", "VistaMidIslands", "VistaHomeKeelTop"]:
				(c as Node3D).visible = false
	var t0 := Time.get_ticks_msec()
	while not vx.is_ready:
		await get_tree().process_frame
	print("VOXEL ready after %d ms (in game)" % (Time.get_ticks_msec() - t0))
	vx.finish_fade()
	for n in SPOTS:
		if not only.is_empty() and not only.has(n):
			continue
		var t: Vector2i = SPOTS[n]
		for i in 20:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			game.sim.speed_x = 0.0; game.sim.speed_y = 0.0
			await get_tree().physics_frame
		await _wait(2.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://voxel_%s.png" % n)
		print("SHOT voxel_%s" % n)
	get_tree().quit()

func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
