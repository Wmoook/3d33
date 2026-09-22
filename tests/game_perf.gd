extends Node
## Windowed perf profile of the real game (Ultra), vsync off.
## For each resolution (1920x1080 windowed, 3840x2160 fullscreen) it measures 4 gameplay locations, then at two
## locations toggles each Environment feature OFF one at a time (SDFGI, SSIL, SSR, SSAO, volumetric fog, glow,
## DOF) and hides each world part (terrain, doors, backdrop, decor, lights, atmosphere) and actors, to attribute
## the cost. Logs frame ms / fps, GPU + CPU render ms (RenderingServer viewport measure), draw calls,
## primitives and objects. Report goes to stdout and user://perf_report.txt.
## Run: $G --audio-driver Dummy --position 20000,20000 --path . res://tests/game_perf.tscn   [-- --only-4k | --only-1080]

const GameScript := preload("res://scripts/game/game.gd")
const LOCATIONS := [["surface/spawn", Vector2(65, 9)], ["inferno", Vector2(140, 104)],
	["corruption", Vector2(215, 95)], ["frozen/lake", Vector2(320, 150)]]
const ENV_FEATURES := ["sdfgi_enabled", "ssil_enabled", "ssr_enabled", "ssao_enabled", "volumetric_fog_enabled", "glow_enabled"]
const PARTS := ["terrain", "doors", "backdrop", "decor", "lights", "atmosphere"]

var game
var _lines: PackedStringArray = []
var _vp_rid: RID

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "skip_title": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 3:
		await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.sim.set_god_mode(true)
	game.hud.show_hints = false
	_log("# EX Odyssey perf  %s" % Time.get_datetime_string_from_system())
	_log("# GPU: %s | %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	_log("# modules: %s" % str(game.modules))
	_log_contention()
	var args := OS.get_cmdline_user_args()
	var res := []
	if not "--only-4k" in args:
		res.append(["1080p", Vector2i(1920, 1080), false])
	if not "--only-1080" in args:
		res.append(["4K", Vector2i(3840, 2160), true])
	for r in res:
		await _set_resolution(r[1], r[2])
		_log("\n## %s  (window %s)" % [r[0], DisplayServer.window_get_size()])
		_log("%-34s %8s %6s %8s %8s %7s %9s %7s" % ["case", "frame_ms", "fps", "gpu_ms", "cpu_ms", "draws", "prims", "objs"])
		for loc in LOCATIONS:
			await _goto(loc[1])
			await _measure("base @ " + loc[0])
		for loc in [LOCATIONS[0], LOCATIONS[1]]:
			await _goto(loc[1])
			_log("-- attribution @ %s (each row = that ONE thing turned off)" % loc[0])
			var env: Environment = game.world.get_environment()
			for feat in ENV_FEATURES:
				if env == null or not env.get(feat):
					_log("%-34s (not enabled by world)" % ("-" + feat))
					continue
				env.set(feat, false)
				await _measure("-" + feat.trim_suffix("_enabled"))
				env.set(feat, true)
			var attrs := _dof_attrs()
			if attrs and attrs.dof_blur_far_enabled:
				attrs.dof_blur_far_enabled = false
				await _measure("-dof")
				attrs.dof_blur_far_enabled = true
			else:
				_log("%-34s (not enabled)" % "-dof")
			for part in PARTS:
				var n = game.world.get(part) if part in game.world else null
				if n == null or not (n is Node3D):
					_log("%-34s (no such node)" % ("-" + part))
					continue
				n.visible = false
				await _measure("-" + part + " (hidden)")
				n.visible = true
			game.actors.visible = false
			await _measure("-actors (hidden)")
			game.actors.visible = true
			if env:
				var saved := {}
				for feat in ENV_FEATURES:
					saved[feat] = env.get(feat)
					env.set(feat, false)
				await _measure("ALL env effects off")
				for feat in ENV_FEATURES:
					env.set(feat, saved[feat])
	_log_contention()
	var f := FileAccess.open("user://perf_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	print("[perf] wrote user://perf_report.txt")
	get_tree().quit()

func _dof_attrs() -> CameraAttributesPractical:
	var we := game._find_world_env_node() as WorldEnvironment
	if we and we.camera_attributes is CameraAttributesPractical:
		return we.camera_attributes
	if game.rig.cam.attributes is CameraAttributesPractical:
		return game.rig.cam.attributes
	return null

func _set_resolution(sz: Vector2i, fullscreen: bool) -> void:
	# Off-screen windowed at the exact size (test rule: never visible, never focused); `fullscreen` ignored.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _frames(5)
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(Vector2i(20000, 20000))
	await _frames(30)

func _goto(tile: Vector2) -> void:
	game.sim.px = tile.x * 16.0
	game.sim.py = tile.y * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))
	await _secs(1.5)

func _measure(label: String) -> void:
	await _secs(0.6)
	var n := 0
	var ft := 0.0
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0.0
	var prims := 0.0
	var objs := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < 2000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft += (now - last) / 1000.0
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
	n = maxi(n, 1)
	_log("%-34s %8.2f %6.0f %8.2f %8.2f %7.0f %9.0f %7.0f" % [label, ft / n, 1000.0 * n / ft, gpu / n, cpu / n, draws / n, prims / n, objs / n])

func _log_contention() -> void:
	var out := []
	OS.execute("tasklist", ["/FI", "IMAGENAME eq Godot*", "/FO", "CSV", "/NH"], out)
	var others := 0
	for line in str(out[0] if out.size() > 0 else "").split("\n", false):
		if line.contains("Godot"):
			others += 1
	_log("# godot processes running (incl. this one + console wrapper): %d" % others)
	for line in str(out[0] if out.size() > 0 else "").split("\n", false):
		if line.contains("Godot"):
			_log("#   " + line.strip_edges())

func _log(s: String) -> void:
	print(s)
	_lines.append(s)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
