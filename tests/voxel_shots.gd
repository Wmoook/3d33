extends Node
## In-game WorldVoxel screenshots (Forgotten Veil, god mode, EE camera). Saves user://voxel_<spot>.png.
##   bash tools_run_test.sh res://tests/voxel_shots.tscn [-- only=grove,falls]
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := {"spawn": Vector2i(2, 56), "grove": Vector2i(40, 40), "falls": Vector2i(150, 165),
	"spire_top": Vector2i(200, 30), "keep": Vector2i(300, 70), "shrine": Vector2i(390, 78),
	"spiregap": Vector2i(222, 70), "valley": Vector2i(160, 120), "bottom": Vector2i(200, 192), "sky": Vector2i(120, 20),
	"grove_top": Vector2i(40, 30), "logo": Vector2i(320, 45), "west_edge": Vector2i(10, 30), "east_low": Vector2i(380, 120),
	"edge_l": Vector2i(10, 100), "under": Vector2i(200, 195), "edge_r": Vector2i(390, 100)}
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
	var hud := "nohud" in OS.get_cmdline_user_args()   # default: HUD + all actors ON (user watches)
	if hud:
		for c in game.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	var base := "base" in OS.get_cmdline_user_args()
	var perf := "perf" in OS.get_cmdline_user_args()
	var tag := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("zoom="):
			game.rig.target_zoom = float(a.substr(5)); game.rig.zoom = float(a.substr(5))
			tag = "_z" + a.substr(5)
		if a == "novox":
			vx.visible = false
			tag += "_novox"
	if perf:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
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
		if perf:
			var on := await _gpu(60)
			vx.visible = false
			var off := await _gpu(60)
			vx.visible = true
			print("PERF %s: gpu %.2f ms with voxels, %.2f without (+%.2f), cpu frame %.2f" % [n, on.x, off.x, on.x - off.x, on.y])
			continue
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://voxel_%s%s.png" % [n, tag])
		print("SHOT voxel_%s" % n)
		_sky_luma(img, n, wv)
		if base:
			vx.visible = false
			await _wait(0.3)
			await RenderingServer.frame_post_draw
			var img2 := get_viewport().get_texture().get_image()
			img2.save_png("user://voxel_%s_base.png" % n)
			_sky_luma(img2, n + "_base", wv)
			vx.visible = true
	get_tree().quit()

func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

## Same rule as world's tests/world_preview.gd: behind every sky air tile (2-tile margin from solids) the
## picture must stay >= 60% of the local sky luminance (80th percentile over a 21x21 window).
func _sky_luma(img: Image, nm: String, wv: WorldView) -> void:
	var t := wv.terrain
	var cam := get_viewport().get_camera_3d()
	var vs := Vector2(img.get_width(), img.get_height())
	var vp := get_viewport().get_visible_rect().size
	var samples := {}
	for ty in t.H:
		for tx in t.W:
			var i := ty * t.W + tx
			if not t.sky[i] or t.solid[i]:
				continue
			var near_solid := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if t.solid[clampi(ty + dy, 0, t.H - 1) * t.W + clampi(tx + dx, 0, t.W - 1)]:
						near_solid = true
			if near_solid:
				continue
			var w := Vector3(tx + 0.5, -ty - 0.5, 0.0)
			if cam.is_position_behind(w):
				continue
			var sp := cam.unproject_position(w) / vp * vs
			if sp.x < 2 or sp.y < 2 or sp.x >= vs.x - 2 or sp.y >= vs.y - 2:
				continue
			samples[Vector2i(tx, ty)] = img.get_pixelv(Vector2i(sp)).get_luminance()
	var bad := 0
	for k: Vector2i in samples:
		var vals := []
		for dy in range(-10, 11, 2):
			for dx in range(-10, 11, 2):
				if samples.has(k + Vector2i(dx, dy)):
					vals.append(samples[k + Vector2i(dx, dy)])
		vals.sort()
		var mx: float = vals[int(vals.size() * 0.8)] if vals.size() > 0 else 0.0
		if samples[k] < mx * 0.6:
			bad += 1
	print("SKY LUMA %s: %d / %d sky tiles below 60%% of local sky %s" % [nm, bad, samples.size(), "OK" if bad * 100 <= samples.size() else "CHECK"])

func _gpu(frames: int) -> Vector2:
	var rid := get_viewport().get_viewport_rid()
	for f in 10:
		await get_tree().process_frame
	var g := 0.0
	var t0 := Time.get_ticks_usec()
	for f in frames:
		await get_tree().process_frame
		g += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return Vector2(g / frames, float(Time.get_ticks_usec() - t0) / frames / 1000.0)
