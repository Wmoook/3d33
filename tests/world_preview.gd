extends Node3D
## World art preview: builds the WorldView, flies a perspective camera to showcase spots and saves
## user://world_<name>.png for each. Run in a window (not headless):
##   godot --path . res://tests/world_preview.tscn [-- only=skull,ice grid dist=60 settle=40]
## "grid" overlays the true collision grid (red = solid, green = air, yellow tile lines).

const SPOTS := {
	"spawn": Vector2(65, 11),
	"surface_tree": Vector2(150, 8),
	"sign": Vector2(40, 45),
	"logo": Vector2(108, 47),
	"upper_lake": Vector2(222, 50),
	"skull": Vector2(135, 102),
	"purple": Vector2(205, 92),
	"tornado": Vector2(22, 110),
	"bones": Vector2(150, 175),
	"ice": Vector2(322, 138),
	"demon": Vector2(315, 165),
	"torches": Vector2(345, 92),
	"lake": Vector2(335, 184),
	"demon_close": Vector2(302, 152),
	"demon_wide": Vector2(318, 162),
	"door": Vector2(80, 10),
	"edge_left": Vector2(4, 40),
	"edge_right": Vector2(395, 110),
	"overview": Vector2(200, 97),
	"door2": Vector2(262, 40),
	"tunnel": Vector2(40, 30),
	"rootworks": Vector2(228, 130),
	"forge": Vector2(160, 185),
	"tree_back": Vector2(80, 5),
	"flame_skull": Vector2(172, 105),
	"slow1": Vector2(119, 45),
	"tunnel_game": Vector2(145, 50),
	"slow2": Vector2(135, 122),
	"walk1": Vector2(100, 11),
	"walk2": Vector2(115, 11),
	"walk3": Vector2(130, 11),
	"surface_mid": Vector2(140, 10),
	"house": Vector2(14, 8),
	"tunnel2": Vector2(150, 55),
}

const FV_SPOTS := {
	"overview": Vector2(200, 97),
	"spawn": Vector2(14, 52),
	"grove": Vector2(40, 36),
	"halls": Vector2(55, 100),
	"falls": Vector2(142, 150),
	"spire_top": Vector2(197, 42),
	"skybar": Vector2(195, 25),
	"keepsky": Vector2(302, 80),
	"edge_right": Vector2(392, 100),
	"edge_bottom": Vector2(200, 192),
	"birds": Vector2(20, 8),
	"spire_mid": Vector2(197, 115),
	"gardens": Vector2(224, 100),
	"twin_spire": Vector2(252, 92),
	"keep": Vector2(322, 95),
	"scroll": Vector2(372, 35),
	"shrine": Vector2(392, 76),
	"great_hall": Vector2(350, 95),
	"eastern_wood": Vector2(385, 98),
	"logo": Vector2(328, 28),
	"sanctum": Vector2(330, 152),
	"aqueducts": Vector2(262, 188),
	"vaults": Vector2(60, 182),
	"trial1": Vector2(-1, 1),
	"trial2": Vector2(-1, 2),
	"trial3": Vector2(-1, 3),
	"trial4": Vector2(-1, 4),
	"trial5": Vector2(-1, 5),
	"trial6": Vector2(-1, 6),
	"trial7": Vector2(-1, 7),
	"trial8": Vector2(-1, 8),
	"trial9": Vector2(-1, 9),
	"trial10": Vector2(-1, 10),
	"trial11": Vector2(-1, 11),
	"trial12": Vector2(-1, 12),
	"trial13": Vector2(-1, 13),
	"trial14": Vector2(-1, 14),
	"trial15": Vector2(-1, 15),
	"trial16": Vector2(-1, 16),
}

var level_id := "odyssey"
var world: WorldView
var cam: Camera3D
var _names: Array = []
var _settle := 45
var _dist := 36.0
var _grid := false
var _yaw := 0.0
var _fps_samples := []
var _perf := false
var _spots := {}
var _mode := 0
var _suffix := ""
var _redkey := false
var _nomoon := false
var _nokey := false
var _nodoors := false
var _hide := ""
var _novfog := false
var _noglow := false
var sim: EESim

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			level_id = a.substr(6)
		elif a.begins_with("only="):
			only = a.substr(5).split(",")
		elif a == "perf":
			_perf = true
		elif a == "grid":
			_grid = true
			_mode = 1; _suffix = "_grid"
		elif a == "zones":
			_mode = 2; _suffix = "_zones"
		elif a == "nomoonshadow":
			_nomoon = true; _suffix += "_nomoon"
		elif a == "novfog":
			_novfog = true; _suffix += "_novfog"
		elif a == "noglow":
			_noglow = true; _suffix += "_noglow"
		elif a.begins_with("hide="):
			_hide = a.substr(5); _suffix += "_no" + _hide
		elif a == "nodoors":
			_nodoors = true; _suffix += "_nodoors"
		elif a == "nokey":
			_nokey = true; _suffix += "_nokey"
		elif a == "redkey":
			_redkey = true; _suffix += "_open"
		elif a.begins_with("dist="):
			_dist = float(a.substr(5))
		elif a.begins_with("yaw="):
			_yaw = float(a.substr(4))
		elif a.begins_with("settle="):
			_settle = int(a.substr(7))
	var spots: Dictionary = SPOTS if level_id == "odyssey" else FV_SPOTS
	_spots = spots
	for k in spots:
		if only.is_empty() or k in only:
			_names.append(k)
	cam = Camera3D.new()
	cam.fov = 36.0
	cam.near = 0.5
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	var cfg := LevelCatalog.get_config(level_id)
	var lvl := EELevel.load_file(str(cfg.get("level_file", "res://levels/ex_crew_odyssey.eelvl")))
	world = WorldView.new()
	add_child(world)
	world.set_level_config(cfg)
	world.build(lvl)
	sim = EESim.new(lvl)
	world.set_sim(sim)
	if _redkey:
		sim._set_key(&"red", true)
	world.set_debug_mode(_mode)
	if _nomoon:
		world.lights.moon.shadow_enabled = false
	if _novfog:
		world.get_environment().volumetric_fog_enabled = false
	if _noglow:
		world.get_environment().glow_enabled = false
		world.atmosphere.post_layer.visible = false
	if _hide != "":
		var n := world.find_child(_hide, true, false)
		if n: n.visible = false
		else: print("HIDE: no node ", _hide)
	if _nodoors:
		world.doors.visible = false
	if _nokey:
		world.lights.key_light.visible = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	if world.trials:
		var sizes := []
		for k in world.trial_count():
			var c := 0
			for v in world.trials.trial_map:
				if v == k + 1: c += 1
			sizes.append([world.trials.coins[k], c])
		print("TRIALS ", world.trial_count(), " ", sizes)
	print("NEAR SILHOUETTES %d" % world.decor.near_silhouette_count)
	print("CAVE PROPS %d, inside sky mask: %d %s" % [world.decor.cave_prop_count, world.decor.cave_props_in_sky,
		"OK" if world.decor.cave_props_in_sky == 0 else "FAIL"])
	world.zone_changed.connect(func(z): print("ZONE ", z, " ", world.get_zone_info(z).get("title")))
	_run()

func _place(tile: Vector2) -> Vector3:
	var focus := Vector3(tile.x + 0.5, -tile.y - 0.5, 0.0)
	cam.position = focus + Vector3(sin(deg_to_rad(_yaw)) * _dist, 2.5, cos(deg_to_rad(_yaw)) * _dist)
	cam.look_at(focus + Vector3(0, 0.5, 0), Vector3.UP)
	return focus

func _measure(focus: Vector3, frames: int) -> float:
	for f in 20:
		world.update_focus(focus, 1.0 / 60.0)
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for f in frames:
		world.update_focus(focus, 1.0 / 60.0)
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / frames / 1000.0

## Frame time per feature toggle at one spot (vsync off).
func _run_perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var focus := _place(_spots[_names[0]])
	var env := world.get_environment()
	print("viewport ", get_viewport().get_visible_rect().size)
	var base_ms: float = await _measure(focus, 120)
	print("PERF base %.2f ms, %.1fM primitives/frame, gpu %.2f ms" % [base_ms,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	world.doors.visible = false
	print("PERF -doors %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	world.decor.visible = false
	print("PERF -decor %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	env.volumetric_fog_enabled = false
	print("PERF -fog %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	env.ssr_enabled = false
	print("PERF -ssr %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	env.ssil_enabled = false
	print("PERF -ssil %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	env.ssao_enabled = false
	print("PERF -ssao %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	world.lights.key_light.shadow_enabled = false
	print("PERF -keyshadow %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	world.lights.moon.shadow_enabled = false
	print("PERF -moonshadow %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	for l in world.lights.cluster_lights:
		l.shadow_enabled = false

	print("PERF -omnishadows %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	world.terrain.visible = false
	print("PERF -terrain %.2f ms gpu %.2f" % [await _measure(focus, 120), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())])
	get_tree().quit()

## Readability check (day levels): behind every sky-connected air tile in view, the backdrop must stay
## >= 60% of the local sky luminance (max over a 21x21-tile window of sky tiles), so open air never reads
## as a dark wall.
func _sky_luma_check(img: Image, nm: String) -> void:
	var t := world.terrain
	var vs := Vector2(img.get_width(), img.get_height())
	var vp := get_viewport().get_visible_rect().size
	var samples := {}
	for ty in t.H:
		for tx in t.W:
			var i := ty * t.W + tx
			if not t.sky[i] or t.solid[i]:
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
		# local sky value = 80th percentile of sky-tile luminance in a 21x21 window (ignores sun/snow peaks)
		var vals := []
		for dy in range(-10, 11, 2):
			for dx in range(-10, 11, 2):
				if samples.has(k + Vector2i(dx, dy)):
					vals.append(samples[k + Vector2i(dx, dy)])
		vals.sort()
		var mx: float = vals[int(vals.size() * 0.8)] if vals.size() > 0 else 0.0
		if samples[k] < mx * 0.6:
			bad += 1
			var w2 := Vector3(k.x + 0.5, -k.y - 0.5, 0.0)
			var sp2 := Vector2i(cam.unproject_position(w2) / vp * vs)
			for oy in range(-6, 7):
				for ox in range(-6, 7):
					if absi(ox) == 6 or absi(oy) == 6:
						img.set_pixelv((sp2 + Vector2i(ox, oy)).clamp(Vector2i.ZERO, Vector2i(vs) - Vector2i.ONE), Color.RED)
	img.save_png("user://world_fv_%s_skyluma.png" % nm)
	print("SKY LUMA %s: %d / %d sky tiles below 60%% of local sky %s" % [nm, bad, samples.size(), "OK" if bad * 100 <= samples.size() else "CHECK"])

func _run() -> void:
	if _perf:
		await _run_perf()
		return
	for nm in _names:
		var spot: Vector2 = _spots[nm]
		if spot.x < 0 and world.trials and world.trial_count() >= int(spot.y):
			spot = Vector2(world.trials.coins[int(spot.y) - 1])
		var focus := _place(spot)
		world.update_focus(focus, 10.0)   # snap the atmosphere blend to this spot
		var t0 := Time.get_ticks_usec()
		for f in _settle:
			world.update_focus(focus, 1.0 / 60.0)
			await get_tree().process_frame
		var frame_us := float(Time.get_ticks_usec() - t0) / _settle
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "user://world_%s%s%s.png" % ["" if level_id == "odyssey" else "fv_", nm, _suffix]
		img.save_png(path)
		print("SHOT %s -> %s  (%.2f ms/frame, %.0f fps)" % [nm, ProjectSettings.globalize_path(path), frame_us / 1000.0, 1e6 / frame_us])
		if level_id != "odyssey":
			_sky_luma_check(img, nm)
	get_tree().quit()
