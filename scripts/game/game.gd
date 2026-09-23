extends Node
## EX Odyssey game shell (main scene root).
## Flow: loading (world build with progress) -> cinematic title flyover -> swoop to player -> gameplay.
## Loop: exactly one sim.tick(input) per 100 Hz _physics_process; render interpolates prev -> cur with
## Engine.get_physics_interpolation_fraction(). Integrates EESim / WorldView / ActorsView from CONTRACTS.md,
## falling back to placeholders in scripts/game/fallback/ while those modules don't exist yet.

## Fallback config if LevelCatalog is unavailable (Odyssey, exactly as shipped).
const ODYSSEY_CFG := {"id": "odyssey", "title": "EX ODYSSEY", "eyebrow": "A REIMAGINING OF EX CREW ODYSSEY",
	"subtitle": "The Devil hath taken thy Soul...  Go, and Return!", "credit": "Based on  \"EX Crew Odyssey\"  -  Everybody Edits",
	"level_file": "res://levels/ex_crew_odyssey.eelvl", "ref_dir": "res://assets/ee_ref", "time_of_day": "night",
	"route_waypoints": "res://scripts/physics/route_waypoints.json", "attract_replay": "res://scripts/physics/route_descent.eerp",
	"best_run_file": "user://best.eerp"}
## Per-level shell texts (cfg keys of the same name override): victory eyebrow/title, map captions.
const LEVEL_TEXT := {
	"odyssey": {"victory_eyebrow": "THE  SOUL  RETURNS", "victory_title": "ODYSSEY COMPLETE", "map_title": "EX CREW ODYSSEY",
		"map_caption": "the map of the odyssey", "quote": "\"The Devil hath taken thy Soul...  Go, and Return!\""},
	"forgotten_veil": {"victory_eyebrow": "CROWNED", "victory_title": "THE VEIL IS LIFTED", "victory_sfx": "crowned", "map_title": "FORGOTTEN VEIL",
		"map_caption": "the map of the forgotten veil", "quote": "\"Sixteen trials. Only the worthy return.\"",
		"tagline": "Sixteen trials.  Only the worthy return.", "trials": "1",
		# sunlit exteriors to open the title flyover on (tile space): twin spires + vine bridges, falls, grove canopy
		"intro_keys": [[130, 140, 44.0], [200, 35, 46.0], [345, 35, 48.0], [390, 78, 42.0]],
		# the finish trophy on the east peak: victory camera rises and widens to frame its light pillar
		"victory_frame": [394, 74], "shrine_rect": [385, 68, 16, 18]},
}
var cfg: Dictionary = ODYSSEY_CFG
const SIM_PATH := "res://scripts/physics/ee_sim.gd"
const INPUT_PATH := "res://scripts/physics/ee_input.gd"
const WORLD_PATH := "res://scripts/render/world_view.gd"
const ACTORS_PATH := "res://scripts/fx/actors_view.gd"
const FB_SIM := "res://scripts/game/fallback/fallback_sim.gd"
const FB_INPUT := "res://scripts/game/fallback/fallback_input.gd"
const FB_WORLD := "res://scripts/game/fallback/fallback_world.gd"
const FB_ACTORS := "res://scripts/game/fallback/fallback_actors.gd"

enum State { BOOT, TITLE, INTRO, PLAYING }

## Test hooks: set before the scene enters the tree.
static var boot_options := {}   # {"skip_title": bool, "quality": int}

signal ready_to_play            # emitted when gameplay input goes live
signal booted                   # emitted after loading finished (title or gameplay next)

var state := State.BOOT
var level: EELevel
var sim                          # EESim (or fallback)
var input                        # EEInput (or fallback)
var world: Node3D                # WorldView (or fallback)
var actors: Node3D               # ActorsView (or fallback)
var rig: CameraRig
var audio: AudioDirector
var settings := GameSettings.new()
var modules := {"sim": "", "world": "", "actors": ""}   # which implementation is live ("real"/"fallback")
## Optional scripted input for tests: func(tick: int) -> Dictionary {left,right,up,down,jump}
var input_provider: Callable

var _world_root: Node3D
var _ui: CanvasLayer
var hud: GameHUD
var zone_card: ZoneCard
var minimap: Minimap
var title: TitleScreen
var loading: LoadingScreen
var pause_menu: PauseMenu
var victory: Control   # victory_screen.gd
var collision_overlay: Node3D   # CollisionOverlay (preloaded so a stale class cache can't break boot)
const CollisionOverlayScript := preload("res://scripts/game/collision_overlay.gd")
const GhostRunsScript := preload("res://scripts/game/ghost_runs.gd")
const TutorialScript := preload("res://scripts/ui/tutorial_hints.gd")
const VictoryScript := preload("res://scripts/ui/victory_screen.gd")
var tutorial: Control   # tutorial_hints.gd
var _tut_moved := false
var _tut_jumped := false
var _victory_zoom := -1.0
var _victory_delay := 0.0   # seconds before the victory card appears (shrine framing on FV)
var _victory_pending := false
var _tut_spawn := Vector2.ZERO
var ghost: Node   # ghost_runs.gd: run recording + best-run ghost
var _fade: ColorRect

var _play_ticks := 0
var _jump_latch := false
var _god_request := false
var _snap_render := false
var _zone: Variant = -2
var _zone_candidate: Variant = -2
var _zone_info := {"name": "", "sub": "", "bed": &"cave", "reverb": 0.5}
var _zone_candidate_t := 0.0
var _key_dur := {}
var _key_last := {}
var _coin_combo := 0
var _coin_last_ms := 0
var _coins_total := 0
var _blue_total := 0
var _authored_env := {}
var _intro_t := 0.0
var _render_pos := Vector3.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.ensure_actions()
	settings.load_settings()
	if boot_options.has("quality"):
		settings.quality = int(boot_options.quality)
	if "--skip-title" in OS.get_cmdline_user_args():
		boot_options["skip_title"] = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			boot_options["level"] = arg.trim_prefix("--level=")
	# Packaged-build self test: `EX_Odyssey.exe --headless --audio-driver Dummy -- --smoke-test`
	if "--smoke-test" in OS.get_cmdline_user_args():
		boot_options["skip_title"] = true
		boot_options["no_save"] = true
		get_tree().create_timer(90.0).timeout.connect(func():
			print("[smoke-test] FAIL: timeout in state ", State.keys()[state])
			get_tree().quit(1))
		ready_to_play.connect(func():
			input_provider = func(t: int) -> Dictionary: return {"right": t < 150, "jump": t > 60 and t < 70}
			while _play_ticks < 200:
				await get_tree().physics_frame
			print("[smoke-test] OK modules=%s ticks=%d pos=(%.1f,%.1f) zone=%s" % [modules, _play_ticks, sim.px, sim.py, _zone_info.name])
			get_tree().quit(0), CONNECT_ONE_SHOT)
	settings.persist = not boot_options.get("no_save", false)
	_select_level_config()
	Engine.max_physics_steps_per_frame = maxi(Engine.max_physics_steps_per_frame, 24)
	_world_root = Node3D.new()
	_world_root.name = "World"
	_world_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world_root)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	_world_root.add_child(rig)
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	_build_ui()
	_apply_audio_settings()
	_apply_fullscreen()
	_boot()

# ======================================================================= boot
func _select_level_config() -> void:
	var want: String = str(boot_options.get("level", settings.level_id))
	var c: Dictionary = {}
	if ResourceLoader.exists("res://scripts/core/level_catalog.gd"):
		LevelCatalog.current_id = want
		c = LevelCatalog.current()
		if c.is_empty():
			LevelCatalog.current_id = "odyssey"
			c = LevelCatalog.current()
	cfg = c if not c.is_empty() else ODYSSEY_CFG
	print("[game] level: %s" % cfg.get("id", "?"))

func _level_text(key: String, fallback: String) -> String:
	if cfg.has(key):
		return str(cfg[key])
	var t: Dictionary = LEVEL_TEXT.get(str(cfg.get("id", "")), {})
	return str(t.get(key, fallback))

## Levels framed as a gauntlet of challenge rooms (FV: every gold coin is a trial).
func _trials() -> bool:
	return _level_text("trials", "") != ""

static func roman(n: int) -> String:
	var vals := [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"],
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
	var out := ""
	for v in vals:
		while n >= v[0]:
			out += v[1]
			n -= v[0]
	return out

func _is_day() -> bool:
	return str(cfg.get("time_of_day", "night")) == "day"

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_ui.layer = 10
	add_child(_ui)
	hud = GameHUD.new()
	hud.show_hints = settings.show_hints
	_ui.add_child(hud)
	zone_card = ZoneCard.new()
	_ui.add_child(zone_card)
	minimap = Minimap.new()
	minimap.ref_dir = str(cfg.get("ref_dir", "res://assets/ee_ref"))
	minimap.level_title = _level_text("map_title", str(cfg.get("title", "")))
	_ui.add_child(minimap)
	title = TitleScreen.new()
	title.visible = false
	_ui.add_child(title)
	var cfgs: Array = LevelCatalog.all() if ResourceLoader.exists("res://scripts/core/level_catalog.gd") else [cfg]
	for c in cfgs:   # per-level taglines when a config has no subtitle (FV: "Sixteen trials...")
		var lt: Dictionary = LEVEL_TEXT.get(str(c.get("id", "")), {})
		if str(c.get("subtitle", "")) == "" and lt.has("tagline"):
			c["subtitle"] = lt.tagline
	title.set_levels(cfgs, str(cfg.id))
	victory = VictoryScript.new()
	victory.title_text = _level_text("victory_title", str(cfg.get("title", "")) + " COMPLETE")
	victory.eyebrow_text = _level_text("victory_eyebrow", "THE  END")
	if _trials():
		victory.stat_keys = ["time", "deaths"]
	tutorial = TutorialScript.new()
	tutorial.done = settings.tutorial.duplicate()
	tutorial.completed.connect(func(id: String):
		settings.tutorial[id] = true
		settings.save_settings())
	_ui.add_child(tutorial)
	_ui.add_child(victory)
	pause_menu = PauseMenu.new()
	pause_menu.settings = settings
	_ui.add_child(pause_menu)
	loading = LoadingScreen.new()
	loading.ref_dir = str(cfg.get("ref_dir", "res://assets/ee_ref"))
	loading.level_title = str(cfg.get("title", ""))
	loading.map_caption = _level_text("map_caption", "the map")
	loading.quote = _level_text("quote", str(cfg.get("credit", "")))
	_ui.add_child(loading)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_ui.add_child(_fade)
	hud.set_state({"visible": false})
	pause_menu.resume_requested.connect(_resume)
	victory.closed.connect(func():
		audio.set_bed(_zone_info.bed)
		hud.set_state({"visible": state == State.PLAYING})
		rig.override_on = false
		if _victory_zoom > 0.0:
			rig.target_zoom = _victory_zoom
			_victory_zoom = -1.0)
	pause_menu.restart_requested.connect(func():
		_resume()
		restart_run())
	pause_menu.quit_title_requested.connect(_quit_to_title)
	pause_menu.change_level_requested.connect(func():
		_quit_to_title()
		title.selected_index = (title.current_index + 1) % maxi(title.levels.size(), 1))
	pause_menu.quit_requested.connect(func():
		settings.save_settings()
		get_tree().quit())
	pause_menu.setting_changed.connect(_on_setting_changed)
	pause_menu.ui_sound.connect(func(n): audio.play(n, -6.0 if n == "ui_move" else -3.0, 0.0))

func _boot() -> void:
	loading.set_progress(0.02, "Awakening")
	await _frames(2)
	level = EELevel.load_file(str(cfg.get("level_file", ODYSSEY_CFG.level_file)))
	if level == null:
		loading.set_progress(0.0, "Level file missing")
		return
	_coins_total = level.find_all(100).size()
	for id in ([] if str(cfg.get("id", "")) == "odyssey" else [43, 165]):   # FV: the finish needs all coins
		for t in level.find_all(id):
			_coin_doors.append([t, int(level.get_extra(t.x, t.y).get("rotation", 0))])
	_blue_total = level.find_all(101).size()
	rig.level_size = Vector2(level.width, level.height)
	loading.set_progress(0.06, "Reading the old map")
	await _frames(1)
	sim = _instance(SIM_PATH, FB_SIM, "sim", [level])
	input = _instance(INPUT_PATH, FB_INPUT, "", [])
	if sim.has_method(&"set_level_config"):
		sim.set_level_config(cfg)
	if sim.has_signal(&"sim_event"):
		sim.sim_event.connect(_on_sim_event)
	loading.set_progress(0.1, "Raising the world")
	await _frames(1)
	world = _instance(WORLD_PATH, FB_WORLD, "world", [])
	world.name = "WorldView"
	if world.has_method(&"set_level_config"):
		world.set_level_config(cfg)
	_world_root.add_child(world)
	var t0 := Time.get_ticks_msec()
	if world.has_method(&"build_progressive"):
		await world.build_progressive(level, func(f: float, label: String):
			loading.set_progress(0.1 + 0.7 * clampf(f, 0.0, 1.0), label))
	else:
		loading.set_progress(0.35, "Sculpting stone and fire")
		await _frames(2)
		world.build(level)
	print("[game] world built in %d ms (%s)" % [Time.get_ticks_msec() - t0, modules.world])
	if world.has_method(&"set_sim"):
		world.set_sim(sim)
	loading.set_progress(0.82, "Summoning the living")
	await _frames(1)
	actors = _instance(ACTORS_PATH, FB_ACTORS, "actors", [])
	actors.name = "ActorsView"
	if actors.has_method(&"set_level_config"):
		actors.set_level_config(cfg)
	_world_root.add_child(actors)
	actors.build(level, sim)
	loading.set_progress(0.9, "Charting the depths")
	await _frames(1)
	minimap.build(level, sim)
	ghost = GhostRunsScript.new()
	ghost.name = "GhostRuns"
	add_child(ghost)
	ghost.best_changed.connect(func(t: int): hud.set_state({"best": t * 0.01 if t >= 0 else -1.0}))
	ghost.best_path = str(cfg.get("best_run_file", "user://best_%s.eerp" % cfg.get("id", "level")))
	ghost.setup(level, sim, actors, _world_root)
	collision_overlay = CollisionOverlayScript.new()
	collision_overlay.name = "CollisionOverlay"
	_world_root.add_child(collision_overlay)
	collision_overlay.setup(level, sim)
	collision_overlay.visible = settings.show_collision
	_apply_camera_style()
	_apply_high_contrast()
	minimap.full_opened.connect(func():
		get_tree().paused = true
		hud.set_state({"visible": false})
		audio.set_muffled(true))
	minimap.full_closed.connect(func():
		if not pause_menu.is_open():
			get_tree().paused = false
			hud.set_state({"visible": state == State.PLAYING})
			audio.set_muffled(false))
	_capture_authored_env()
	_apply_quality()
	_setup_cinematic()
	rig.cinematic_cut.connect(func(): _fade_flash(0.6))
	_render_pos = _player_world_pos(1.0)
	loading.set_progress(0.96, "Lighting the torches")
	minimap.warmup(6)
	pause_menu.warmup(6)
	victory.show_stats({"time": 0.0, "coins": 0, "coins_total": 0, "blue": 0, "blue_total": 0, "deaths": 0})
	# Warm up: render a few frames at several places so pipelines compile before the reveal.
	# (every zone, so first-visit pipeline compiles / uploads happen behind the loading screen)
	for k in [Vector2(65, 8), Vector2(190, 7), Vector2(310, 10), Vector2(384, 14), Vector2(110, 28), Vector2(338, 55),
			Vector2(340, 90), Vector2(320, 150), Vector2(290, 175), Vector2(230, 185), Vector2(150, 185),
			Vector2(100, 150), Vector2(140, 100), Vector2(215, 95), Vector2(200, 140), Vector2(40, 110), Vector2(40, 45)]:
		rig.snap_to(Vector3(k.x, -k.y, 0))
		rig.follow(Vector3(k.x, -k.y, 0), Vector2.ZERO, 0.016)
		if world.has_method(&"update_focus"):
			world.update_focus(Vector3(k.x, -k.y, 0), 0.016)
		if actors.has_method(&"update_camera"):
			actors.update_camera(rig.cam.global_position)
		await _frames(3)
	victory.visible = false
	loading.set_progress(1.0, "Ready")
	await _frames(8)
	# let the map-of-the-odyssey finish painting itself in (max ~4 s)
	var t_wait := Time.get_ticks_msec()
	while loading.reveal_progress() < 0.97 and Time.get_ticks_msec() - t_wait < 4000 and not boot_options.get("skip_title", false):
		await get_tree().process_frame
	print("[game] modules: ", modules)
	booted.emit()
	if boot_options.get("skip_title", false):
		loading.visible = false
		_start_play(false)
	else:
		_enter_title()
		loading.fade_out(1.6)

func _instance(path: String, fallback: String, key: String, args: Array) -> Object:
	var used := "real"
	var scr: Script = null
	if ResourceLoader.exists(path):
		scr = load(path) as Script
	if scr == null or not scr.can_instantiate():
		if ResourceLoader.exists(path):
			push_warning("[game] %s exists but can't be instantiated; using fallback" % path)
		scr = load(fallback) as Script
		used = "fallback"
	if key != "":
		modules[key] = used
	var o: Object = scr.callv(&"new", args)
	return o

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# ======================================================================= title / intro
const ATTRACT_IDLE := 20.0
var _attract := false
var _attract_rep
var _title_idle := 0.0

func _setup_cinematic() -> void:
	var route := _route_keys()
	var intro: Array = LEVEL_TEXT.get(str(cfg.get("id", "")), {}).get("intro_keys", [])
	if not intro.is_empty() and route.size() >= 4:
		var pre := []
		for k in intro:
			pre.append({"pos": Vector2(k[0], k[1]), "zoom": float(k[2]), "showcase": true, "cut": pre.size() > 0})
		route[0]["cut"] = true    # cut from the showcase into the route
		route = pre + route
	if route.size() >= 4:
		rig.set_cinematic_path(route)
		print("[game] title flyover follows %s (%d keys)" % [cfg.get("route_waypoints", ""), route.size()])
		return
	_setup_cinematic_default()

## Title flyover along the physics route (the actual path through the level), if physics provides it.
## Accepts [[x,y],...], [{x,y},...] or {"waypoints": [...]}, in tiles or EE pixels (auto-detected);
## resampled to evenly spaced keyframes (~24 tiles apart) with a gentle zoom breathing.
func _route_keys() -> Array:
	var route_path := str(cfg.get("route_waypoints", ""))
	if route_path == "" or not FileAccess.file_exists(route_path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(route_path))
	if d is Dictionary:
		for k in ["waypoints", "route", "points", "path"]:
			if d.has(k):
				d = d[k]
				break
	if not (d is Array) or d.is_empty():
		return []
	var pts: Array[Vector2] = []
	var notes: Array[bool] = []
	var max_c := 0.0
	for w in d:
		var v := Vector2.INF
		if w is Array and w.size() >= 2:
			v = Vector2(float(w[0]), float(w[1]))
		elif w is Dictionary:
			if w.has("x") and w.has("y"):
				v = Vector2(float(w.x), float(w.y))
			elif w.has("tile"):
				var t = w.tile
				v = Vector2(float(t[0]), float(t[1])) if t is Array else Vector2.INF
			elif w.has("px") and w.has("py"):
				v = Vector2(float(w.px), float(w.py)) / 16.0
		if v != Vector2.INF:
			pts.append(v)
			notes.append(w is Dictionary and str(w.get("note", "")) != "")
			max_c = maxf(max_c, maxf(v.x, v.y))
	if pts.size() < 2:
		return []
	if max_c > float(maxi(level.width, level.height)) * 1.5:  # pixels -> tiles
		for i in pts.size():
			pts[i] = pts[i] / 16.0
	# Portal jumps (physics marks each segment's first point with a note; they're also far apart) become
	# camera CUTS instead of a flight across the map.
	var keys := []
	var acc := 0.0
	for i in pts.size():
		var jump := i > 0 and pts[i].distance_to(pts[i - 1]) > 30.0 and (notes[i] or pts[i].distance_to(pts[i - 1]) > 60.0)
		if i == 0 or jump:
			if i > 0 and keys[-1].pos != pts[i - 1]:
				keys.append({"pos": pts[i - 1], "zoom": _route_zoom(keys.size())})
			keys.append({"pos": pts[i], "zoom": _route_zoom(keys.size()), "cut": i > 0})
			acc = 0.0
			continue
		acc += pts[i].distance_to(pts[i - 1])
		if acc >= 24.0 or i == pts.size() - 1:
			acc = 0.0
			keys.append({"pos": pts[i], "zoom": _route_zoom(keys.size())})
	return keys

func _route_zoom(k: int) -> float:
	return 44.0 + 10.0 * sin(k * 0.9)

func _setup_cinematic_default() -> void:
	if str(cfg.get("id", "")) != "odyssey":
		_setup_cinematic_auto()
		return
	# Tile-space keyframes (y down) touring the painting: surface -> sign -> inferno -> corruption ->
	# brimstone -> ice -> demon -> drowned forge -> bones -> maelstrom -> back.
	rig.set_cinematic_path([
		{"pos": Vector2(60, 9), "zoom": 42.0},
		{"pos": Vector2(150, 10), "zoom": 50.0},
		{"pos": Vector2(250, 12), "zoom": 56.0},
		{"pos": Vector2(330, 40), "zoom": 60.0},
		{"pos": Vector2(340, 92), "zoom": 58.0},
		{"pos": Vector2(330, 150), "zoom": 66.0},
		{"pos": Vector2(250, 180), "zoom": 58.0},
		{"pos": Vector2(215, 100), "zoom": 54.0},
		{"pos": Vector2(150, 105), "zoom": 56.0},
		{"pos": Vector2(110, 150), "zoom": 54.0},
		{"pos": Vector2(35, 110), "zoom": 56.0},
		{"pos": Vector2(60, 50), "zoom": 58.0},
	])

## Generic flyover for levels without a route file: a slow serpentine over the whole painting.
func _setup_cinematic_auto() -> void:
	var keys := []
	var W := float(level.width)
	var H := float(level.height)
	var sp: Array = level.find_all(255)
	if sp.size() > 0:
		keys.append({"pos": Vector2(sp[0]) + Vector2(8, -2), "zoom": 42.0})
	var rows := [0.3, 0.55, 0.8]
	for r in rows.size():
		var xs := [0.12, 0.37, 0.63, 0.88]
		if r % 2 == 1:
			xs.reverse()
		for x in xs:
			keys.append({"pos": Vector2(W * x, H * rows[r]), "zoom": 50.0 + 6.0 * sin(keys.size() * 0.8)})
	rig.set_cinematic_path(keys)

func _enter_title() -> void:
	state = State.TITLE
	_title_idle = 0.0
	_attract = false
	title.attract = false
	get_tree().paused = false
	rig.begin_cinematic()
	title.restart_intro()
	hud.set_state({"visible": false})
	minimap.set_shown(false)
	audio.set_bed(_title_bed())
	audio.set_room(0.5)
	get_tree().create_timer(1.2).timeout.connect(func():
		if state == State.TITLE:
			audio.play("title_hit", -2.0, 0.0))

## Attract mode: after ATTRACT_IDLE s on the title, the real ball plays physics' bit-exact recorded descent
## (scripts/physics/route_descent.eerp) with the camera following it; any key starts a fresh game.
func _start_attract() -> bool:
	if _attract_rep == null:
		var ar := str(cfg.get("attract_replay", ""))
		if ar == "" or not (ResourceLoader.exists("res://scripts/physics/ee_replay.gd") and FileAccess.file_exists(ar)):
			_title_idle = -1e9   # nothing to play; don't retry
			return false
		_attract_rep = load("res://scripts/physics/ee_replay.gd").load_file(str(cfg.attract_replay))
		if _attract_rep == null:
			_title_idle = -1e9
			return false
	_attract_rep.start(sim)     # sim.reset() + rewind
	_attract = true
	title.attract = true
	rig.begin_follow(true)
	rig.target_zoom = settings.zoom
	_fade_flash(0.7)
	return true

func _stop_attract() -> void:
	_attract = false
	_title_idle = 0.0
	title.attract = false
	sim.reset()
	if ghost:
		ghost.on_reset()
	_coin_door_seen = false
	if state == State.TITLE:
		rig.begin_cinematic()
		_fade_flash(0.7)

func _fade_flash(t: float) -> void:
	_fade.modulate.a = 1.0
	create_tween().tween_property(_fade, "modulate:a", 0.0, t)

func _in_shrine() -> bool:
	var r: Array = LEVEL_TEXT.get(str(cfg.get("id", "")), {}).get("shrine_rect", [])
	if r.is_empty():
		return false
	var t := EECoords.world_to_tile(_render_pos)
	return Rect2i(r[0], r[1], r[2], r[3]).has_point(t)

func _title_bed() -> StringName:
	return StringName(cfg.get("title_music", "veil_title" if _is_day() else "title"))

func _start_play(swoop: bool) -> void:
	state = State.INTRO if swoop else State.PLAYING
	_intro_t = 0.0
	rig.target_zoom = settings.zoom
	if swoop:
		rig.begin_follow(true)
	else:
		rig.begin_follow(false)
		rig.zoom = settings.zoom
		rig.snap_to(_player_world_pos(1.0))
		_go_live()

func _go_live() -> void:
	state = State.PLAYING
	_play_ticks = 0
	_zone = -2
	hud.set_state({"visible": true})
	hud.reset_hints()
	_tut_moved = false
	_tut_jumped = false
	_tut_spawn = Vector2(sim.px, sim.py)
	tutorial.offer("move")
	ready_to_play.emit()

func _quit_to_title() -> void:
	_resume()
	restart_run()
	_enter_title()

# ======================================================================= loop
func _physics_process(_delta: float) -> void:
	if state == State.TITLE and _attract:
		if not _attract_rep.step(sim):
			_stop_attract()
		else:
			_check_piano()
		return
	if state != State.PLAYING or get_tree().paused or sim == null or victory.visible or _victory_pending:
		return
	_fill_input()
	if _god_request:
		_god_request = false
		_toggle_god()
	ghost.record(input)
	sim.tick(input)
	ghost.tick_ghost()
	_check_piano()
	_play_ticks += 1
	if not _tut_moved and absf(sim.px - _tut_spawn.x) > 48.0:
		_tut_moved = true
		if _tut_jumped:
			tutorial.complete("move")
	if "teleported" in sim:
		_snap_render = sim.teleported
	else:
		_snap_render = absf(sim.px - sim.prev_px) > 40.0 or absf(sim.py - sim.prev_py) > 40.0

## EE piano (77): plays when the player's center enters a piano tile; note = the block's rotation value
## (EE Me.as: `if (pastx != cx || pasty != cy) ... case PIANO: playPianoSound(lookup.getInt(cx, cy))`).
var _piano_cell := Vector2i(-1, -1)
var _sim_piano_events := false
var _coin_doors: Array = []        # [Vector2i tile, int needed] of gold coin doors/gates (43/165)
var _coin_door_seen := false
var _door_toast_need := 0
var _door_toast_open := false

func _door_toast_text() -> String:
	return "needs %d gold %s  -  you have %d" % [_door_toast_need, "coin" if _door_toast_need == 1 else "coins", int(sim.coins)]
func _check_piano() -> void:
	if _sim_piano_events:
		return
	var c := Vector2i(floori((sim.px + 8.0) / 16.0), floori((sim.py + 8.0) / 16.0))
	if c == _piano_cell:
		return
	_piano_cell = c
	var id: int = sim.get_tile(c.x, c.y) if sim.has_method(&"get_tile") else level.get_fg(c.x, c.y)
	if id == 77:
		audio.play_piano(int(level.get_extra(c.x, c.y).get("rotation", 0)))

## FV: a gold coin = a completed trial room: zone-card style banner, triumphant chime, gentle camera ease-in.
func _trial_complete() -> void:
	var n := int(sim.coins)
	var left := maxi(0, _coins_total - n)
	var rem := ("1 trial remains" if left == 1 else "%d trials remain" % left) if left > 0 else "The way is open"
	zone_card.show_zone("TRIAL %s COMPLETE" % roman(n), rem)
	audio.play("trial", -3.0, 0.0)
	var z := rig.target_zoom
	rig.target_zoom = maxf(CameraRig.ZOOM_MIN, z * 0.88)
	get_tree().create_timer(1.4).timeout.connect(func():
		if _victory_zoom < 0.0:
			rig.target_zoom = z)

## "TRIAL n" caption when entering a trial room, if the world exposes trials (get_trial_at(tile) -> int, 0 = none).
var _trial_cur := 0
var _trial_cand := 0
var _trial_cand_t := 0.0
func _update_trial_caption(delta: float) -> void:
	if world == null or not world.has_method(&"get_trial_at"):
		return
	var t: int = int(world.get_trial_at(EECoords.world_to_tile(_render_pos)))
	if t != _trial_cand:
		_trial_cand = t
		_trial_cand_t = 0.0
	_trial_cand_t += delta
	if t != _trial_cur and _trial_cand_t > 0.4:
		_trial_cur = t
		if t > 0:
			var total: int = int(world.trial_count()) if world.has_method(&"trial_count") else _coins_total
			hud.caption("TRIAL %s  OF  %s" % [roman(t), roman(total)])

func _fill_input() -> void:
	if "god_toggle" in input:
		input.god_toggle = false
	if "jump_pressed" in input:
		input.jump_pressed = false
	if input_provider.is_valid():
		var d: Dictionary = input_provider.call(_play_ticks)
		input.left = d.get("left", false)
		input.right = d.get("right", false)
		input.up = d.get("up", false)
		input.down = d.get("down", false)
		input.jump = d.get("jump", false)
		if d.get("god", false):
			_toggle_god()
		return
	input.left = Input.is_action_pressed(&"ee_left")
	input.right = Input.is_action_pressed(&"ee_right")
	input.up = Input.is_action_pressed(&"ee_up")
	input.down = Input.is_action_pressed(&"ee_down")
	# Space tapped and released between two ticks still registers for one tick.
	if "jump_pressed" in input:
		input.jump = Input.is_action_pressed(&"ee_jump")
		input.jump_pressed = _jump_latch    # EEInput edge flag (sim clears it after use)
	else:
		input.jump = Input.is_action_pressed(&"ee_jump") or _jump_latch
	_jump_latch = false

func _toggle_god() -> void:
	var on := not bool(sim.in_god_mode)
	if "god_toggle" in input:
		input.god_toggle = true      # consumed by sim.tick, recorded in replays
	elif sim.has_method(&"set_god_mode"):
		sim.set_god_mode(on)
	else:
		sim.in_god_mode = on
	audio.play("gravity", -4.0, 0.0, 1.5 if on else 1.0)

func _process(delta: float) -> void:
	if sim == null or state == State.BOOT:
		return
	var paused := get_tree().paused
	match state:
		State.TITLE:
			tutorial.visible = false
			if _attract:
				var fa := 1.0 if ("teleported" in sim and sim.teleported) else Engine.get_physics_interpolation_fraction()
				_render_pos = _player_world_pos(fa)
				var va := Vector2(sim.px - sim.prev_px, -(sim.py - sim.prev_py)) * (100.0 / 16.0)
				var ga: Vector2i = sim.gravity_dir if "gravity_dir" in sim else Vector2i(0, 1)
				rig.follow(_render_pos, va, delta, Vector2(ga.x, -ga.y))
				_update_world_actors(_render_pos, delta)
			else:
				rig.cinematic(delta, 0.07)
				_render_pos = _player_world_pos(1.0)
				_update_world_actors(rig.focus, delta)
				_title_idle += delta
				if _title_idle > ATTRACT_IDLE and title.accept_input:
					_start_attract()
		State.INTRO, State.PLAYING:
			if not paused:
				var f := 1.0 if _snap_render else Engine.get_physics_interpolation_fraction()
				if state == State.INTRO:
					f = 1.0
				_render_pos = _player_world_pos(f)
				var vel := Vector2(sim.px - sim.prev_px, -(sim.py - sim.prev_py)) * (100.0 / 16.0)
				var gd: Vector2i = sim.gravity_dir if "gravity_dir" in sim else Vector2i(0, 1)
				rig.follow(_render_pos, vel, delta, Vector2(gd.x, -gd.y))
				_update_world_actors(_render_pos, delta)
				if ghost:
					ghost.update_visual(f, delta)
			if state == State.INTRO:
				_intro_t += delta
				if _intro_t > 2.3:
					_go_live()
			if state == State.PLAYING:
				_update_zone(delta)
			tutorial.visible = state == State.PLAYING and not victory.visible and not paused
			_update_hud()

## Run timer: the sim's EE run timer (Me.ticks) when available, else shell ticks.
func _run_time() -> float:
	if "run_ticks" in sim:
		return int(sim.run_ticks) * 0.01
	return _play_ticks * 0.01

func _update_world_actors(focus: Vector3, delta: float) -> void:
	if collision_overlay:
		collision_overlay.update_view(rig.focus, rig.half_extents(), _render_pos)
	if actors and actors.has_method(&"update_camera") and rig.cam:
		actors.update_camera(rig.cam.global_position)
	if world and world.has_method(&"update_focus"):
		world.update_focus(focus, delta)
	if actors and actors.has_method(&"update_player"):
		actors.update_player(_render_pos, sim, delta)

func _player_world_pos(f: float) -> Vector3:
	var x: float = lerpf(sim.prev_px, sim.px, f)
	var y: float = lerpf(sim.prev_py, sim.py, f)
	return EECoords.player_center(x, y)

func _update_zone(delta: float) -> void:
	var tile := EECoords.world_to_tile(_render_pos)
	var z: Variant = _zone_key_at(tile)
	if not _same(z, _zone_candidate):
		_zone_candidate = z
		_zone_candidate_t = 0.0
	_zone_candidate_t += delta
	var first: bool = _zone is int and _zone == -2
	if not _same(z, _zone) and (_zone_candidate_t > 0.35 or first):
		_zone = z
		_zone_info = _zone_info_for(z)
		audio.set_bed(_zone_info.bed, false)
		audio.set_room(_zone_info.reverb)
		minimap.zone_name = _zone_info.name
		if _zone_info.name != "":
			zone_card.show_zone(_zone_info.name, _zone_info.sub)
			audio.play("zone", -9.0, 0.0)

static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b

## Zone identity: WorldView is the source of truth (get_zone_at / get_zone_info, CONTRACTS "Zones");
## the shell's own rectangles (zones.gd) are only a fallback while WorldView lacks them.
func _zone_key_at(tile: Vector2i) -> Variant:
	if world and world.has_method(&"get_zone_at"):
		return world.get_zone_at(tile)
	return Zones.index_at(tile) if str(cfg.get("id", "")) == "odyssey" else -1

func _zone_info_for(z: Variant) -> Dictionary:
	if z is StringName or z is String:
		var d: Dictionary = world.get_zone_info(z) if world.has_method(&"get_zone_info") else {}
		var mood := str(d.get("music_mood", z)).to_lower()
		var fb: Dictionary = Zones.get_zone(Zones.index_at(EECoords.world_to_tile(_render_pos))) if str(cfg.get("id", "")) == "odyssey" \
			else {"name": "", "bed": &"day" if _is_day() else &"cave"}
		var title := str(d.get("title", fb.name))
		var bed: StringName = _day_bed_for_mood(mood) if _is_day() else _bed_for_mood(mood, fb.bed)
		if _in_shrine() or mood.contains("shrine") or str(z).contains("shrine") or str(z).contains("summit"):
			bed = _title_bed()
		return {"name": title.to_upper(), "sub": str(d.get("subtitle", "")), "bed": bed,
			"reverb": float(d.get("reverb", _reverb_for_mood(mood)))}
	if str(cfg.get("id", "")) != "odyssey":
		return {"name": "", "sub": "", "bed": &"day" if _is_day() else &"cave", "reverb": 0.3}
	var info := Zones.get_zone(int(z))
	return {"name": info.name, "sub": info.sub, "bed": info.bed, "reverb": info.reverb}

## Daytime levels (Forgotten Veil): falls / temple interiors / open day.
static func _day_bed_for_mood(mood: String) -> StringName:
	for k in ["falls", "waterfall", "pool", "water"]:
		if mood.contains(k):
			return &"falls"
	for k in ["temple", "hall", "ruin", "corridor", "channel", "cave", "underground", "tunnel", "crypt"]:
		if mood.contains(k):
			return &"temple"
	return &"day"

static func _bed_for_mood(mood: String, fallback: StringName) -> StringName:
	for pair in [["surface", &"surface"], ["night", &"surface"], ["sky", &"surface"], ["inferno", &"hell"],
			["fire", &"hell"], ["hell", &"hell"], ["lava", &"hell"], ["brimstone", &"hell"], ["corrupt", &"corruption"],
			["void", &"corruption"], ["ice", &"ice"], ["frozen", &"ice"], ["snow", &"ice"], ["lake", &"lake"],
			["water", &"lake"], ["demon", &"lake"], ["cave", &"cave"], ["tunnel", &"cave"], ["earth", &"cave"], ["bone", &"cave"]]:
		if mood.contains(pair[0]):
			return pair[1]
	return fallback

static func _reverb_for_mood(mood: String) -> float:
	if mood.contains("surface") or mood.contains("night") or mood.contains("sky"):
		return 0.15
	if mood.contains("tunnel"):
		return 0.55
	return 0.75

func _update_hud() -> void:
	var keys := {}
	for c in [&"red", &"green", &"blue"]:
		var left := 0.0
		if sim.has_method(&"is_key_active") and sim.is_key_active(c):
			left = float(sim.key_time_left(c))
		var last: float = _key_last.get(c, 0.0)
		if left > last + 0.05:
			_key_dur[c] = left
		_key_last[c] = left
		keys[c] = [left, _key_dur.get(c, maxf(left, 1.0))]
	var z := _zone_info
	if _trials():
		_update_trial_caption(get_process_delta_time())
	hud.set_state({"coin_label": "TRIALS" if _trials() else "", "coins": int(sim.coins), "coins_total": _coins_total, "blue": int(sim.blue_coins),
		"blue_total": _blue_total, "keys": keys, "time": _run_time(), "god": bool(sim.in_god_mode),
		"crown": bool(sim.has_crown), "zone": z.name})
	var he := rig.half_extents()
	if not _coin_door_seen and not _coin_doors.is_empty():
		var vr := Rect2(Vector2(rig.focus.x, -rig.focus.y) - he * 0.85, he * 1.7)
		for cd in _coin_doors:
			if vr.has_point(Vector2(cd[0]) + Vector2(0.5, 0.5)) and sim.is_tile_solid_now(cd[0].x, cd[0].y):
				_coin_door_seen = true
				_door_toast_need = int(cd[1])
				_door_toast_open = false
				hud.toast("COIN DOOR", _door_toast_text(), 5.0)
				break
	# live coin count in the coin-door pill (same source as the HUD); flips to OPEN when you have enough
	if _door_toast_need > 0 and hud.toast_active():
		if int(sim.coins) >= _door_toast_need:
			if not _door_toast_open:
				_door_toast_open = true
				hud.toast_update("COIN DOOR OPEN", "", 1.6)
		else:
			hud.toast_update("COIN DOOR", _door_toast_text())
	var ptile := Vector2(_render_pos.x, -_render_pos.y)
	var cf := Vector2(rig.focus.x, -rig.focus.y)
	minimap.set_player(ptile, Rect2(cf - he, he * 2.0))

# ======================================================================= events
func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"coin", &"blue_coin":
			if kind == &"coin" and _trials() and state == State.PLAYING:
				_trial_complete()
			var now := Time.get_ticks_msec()
			_coin_combo = mini(_coin_combo + 1, 8) if now - _coin_last_ms < 1400 else 0
			_coin_last_ms = now
			var semis: int = [0, 2, 4, 5, 7, 9, 11, 12, 14][_coin_combo]
			audio.play(String(kind), -5.0, 0.0, pow(2.0, semis / 12.0))
			if data.has("tile"):
				minimap.erase_tile(data.tile)
		&"door_state", &"god_mode":
			if kind == &"god_mode" and data.get("on", false) and state == State.PLAYING:
				tutorial.offer("god")
			minimap.refresh_doors()
			collision_overlay.mark_dirty()
		&"key":
			if state == State.PLAYING:
				tutorial.offer("keys")
			audio.play("key", -3.0, 0.0)
			hud.flash(UITheme.KEY_COLORS.get(StringName(data.get("color", &"red")), Color.WHITE), 0.35)
		&"key_expired":
			audio.play("key_expired", -6.0, 0.0)
			minimap.refresh_doors()
		&"portal":
			audio.play("portal", -5.0)
			_snap_render = true
		&"crown":
			audio.play("crown", -3.0, 0.0)
			hud.flash(UITheme.GOLD, 0.5)
		&"death":
			audio.play("death", -3.0)
			rig.add_trauma(0.55)
			hud.flash(Color(0.7, 0.02, 0.0), 0.9)
		&"respawn":
			if state == State.PLAYING:
				audio.play("respawn", -6.0, 0.0)
			_snap_render = true
		&"jump":
			if state == State.PLAYING:
				_tut_jumped = true
			if _tut_moved and _tut_jumped:
				tutorial.complete("move")
			audio.play("jump", -13.0, 0.08)
		&"land":
			var imp := float(data.get("impact_speed", 0.0))
			if imp > 2.0:
				audio.play("land", lerpf(-20.0, -4.0, clampf(imp / 16.0, 0.0, 1.0)), 0.08)
			rig.add_trauma(clampf((imp - 7.0) / 10.0, 0.0, 1.0) * 0.45)
		&"gravity_changed":
			var gdir = data.get("dir", Vector2i(0, 1))
			if gdir != Vector2i(0, 1) and not sim.in_god_mode and state == State.PLAYING:
				tutorial.offer("arrows")
			audio.play("gravity", -14.0, 0.1)
		&"checkpoint":
			audio.play("ui_select", -6.0, 0.0)
		&"piano":
			_sim_piano_events = true
			audio.play_piano(int(data.get("note", 0)))
		&"secret":
			audio.play("blue_coin", -12.0, 0.0, 0.5)
		&"complete":
			audio.play(_level_text("victory_sfx", "crown"), 0.0, 0.0)
			_victory_delay = 0.0
			hud.flash(UITheme.GOLD, 0.8)
			audio.set_bed(_title_bed())
			hud.set_state({"visible": false})
			_victory_zoom = rig.target_zoom
			rig.target_zoom = maxf(CameraRig.ZOOM_MIN, rig.target_zoom * 0.8)
			var vf: Array = LEVEL_TEXT.get(str(cfg.get("id", "")), {}).get("victory_frame", [])
			if not vf.is_empty():
				rig.override_target = EECoords.tile_center(vf[0], vf[1]) + Vector3(0.5, 4.0, 0.0)
				rig.override_on = true
				rig.begin_follow(true)
				rig.target_zoom = minf(CameraRig.ZOOM_MAX, _victory_zoom * 1.5)
				_victory_delay = 3.2   # camera frames the shrine, then actors' crowning (~1.5 s) before the card
			var new_best: bool = ghost.on_complete(int(data.get("ticks", sim.run_ticks if "run_ticks" in sim else _play_ticks)))
			if _trials():
				victory.subline = ("All %d trials conquered" % _coins_total) if int(sim.coins) >= _coins_total else ("%d of %d %s conquered" % [int(sim.coins), _coins_total, "trial" if _coins_total == 1 else "trials"])
			var vstats := {"new_best": new_best, "best": ghost.best_ticks * 0.01, "time": _run_time(), "coins": int(sim.coins), "coins_total": _coins_total,
				"blue": int(sim.blue_coins), "blue_total": _blue_total, "deaths": int(sim.deaths) if "deaths" in sim else 0}
			if _victory_delay > 0.0:
				_victory_pending = true   # freeze the run while the camera frames the shrine
				get_tree().create_timer(_victory_delay).timeout.connect(func():
					_victory_pending = false
					victory.show_stats(vstats))
			else:
				victory.show_stats(vstats)

# ======================================================================= input / menus
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ee_fullscreen"):
		_on_setting_changed("fullscreen", not settings.fullscreen)
		return
	match state:
		State.TITLE:
			if title.accept_input and title.levels.size() > 1 and not _attract and \
					(event.is_action_pressed(&"ee_left") or event.is_action_pressed(&"ee_right")):
				get_viewport().set_input_as_handled()
				_title_idle = 0.0
				if title.select_delta(-1 if event.is_action_pressed(&"ee_left") else 1):
					audio.play("ui_move", -6.0, 0.0)
				return
			if title.accept_input and _is_any_press(event) and not _is_nav_only(event):
				get_viewport().set_input_as_handled()
				audio.play("ui_select", -2.0, 0.0)
				if not _attract and title.selected_index != title.current_index:
					switch_level(str(title.selected_cfg().get("id", "odyssey")))
					return
				if _attract:
					_stop_attract()
					rig.snap_to(_player_world_pos(1.0))
				title.dismiss()
				_start_play(true)
		State.PLAYING:
			if pause_menu.is_open() or minimap.is_full():
				return
			if victory.is_open():
				if _is_any_press(event):
					get_viewport().set_input_as_handled()
					if victory.dismiss() and event is InputEventKey and event.physical_keycode == KEY_R:
						restart_run()
				return
			if event.is_action_pressed(&"ee_pause"):
				get_viewport().set_input_as_handled()
				_pause()
			elif event.is_action_pressed(&"ee_jump"):
				_jump_latch = true
			elif event.is_action_pressed(&"ee_god"):
				_god_request = true
			elif event.is_action_pressed(&"ee_overview"):
				toggle_overview()
			elif event.is_action_pressed(&"ee_ghost"):
				ghost.toggle()
				audio.play("ui_move", -8.0, 0.0)
			elif event.is_action_pressed(&"ee_collision"):
				collision_overlay.visible = not collision_overlay.visible
				settings.show_collision = collision_overlay.visible
				settings.save_settings()
				collision_overlay.mark_dirty()
				audio.play("ui_move", -8.0, 0.0)
			elif event.is_action_pressed(&"ee_minimap"):
				minimap.toggle()
				audio.play("ui_move", -8.0, 0.0)
			elif event.is_action_pressed(&"ee_retry") and event is InputEventKey and event.shift_pressed:
				restart_run()
			elif event.is_action_pressed(&"ee_zoom_in"):
				_zoom(-1.0)
			elif event.is_action_pressed(&"ee_zoom_out"):
				_zoom(1.0)
			elif event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					_zoom(-0.5)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_zoom(0.5)

## Up/down etc. shouldn't start the game from the level select; left/right navigate.
func _is_nav_only(e: InputEvent) -> bool:
	return title.levels.size() > 1 and (e.is_action_pressed(&"ee_up") or e.is_action_pressed(&"ee_down") \
		or e.is_action_pressed(&"ee_left") or e.is_action_pressed(&"ee_right"))

## Level select / pause "Change level": remember the choice and reboot the whole game scene for that level
## (the loading screen paints the new level's minimap).
func switch_level(id: String) -> void:
	settings.level_id = id
	var keep := settings.persist
	settings.persist = true if not boot_options.get("no_save", false) else keep
	settings.save_settings()
	settings.persist = keep
	boot_options["level"] = id
	boot_options.erase("skip_title")
	get_tree().paused = false
	_fade.modulate.a = 1.0
	await get_tree().process_frame
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()
	else:
		# embedded (tests): rebuild in place
		var parent := get_parent()
		var fresh: Node = load(scene_file_path).instantiate() if scene_file_path != "" else load("res://scenes/main.tscn").instantiate()
		parent.add_child(fresh)
		queue_free()

func _is_any_press(e: InputEvent) -> bool:
	if e is InputEventKey:
		return e.pressed and not e.echo and e.keycode != KEY_F11
	return (e is InputEventJoypadButton and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index <= MOUSE_BUTTON_RIGHT)

func _zoom(steps: float) -> void:
	if _overview:
		_overview = false   # wheel/+- leaves the overview and adjusts the normal zoom
		rig.target_zoom = _overview_prev
	rig.add_zoom_steps(steps)
	settings.zoom = rig.target_zoom

## C / R3: toggle a wide overview (~2.5x the visible width) around the player; the EE follow keeps running.
## Never saved as the default zoom.
const OVERVIEW_FACTOR := 2.5
const OVERVIEW_MAX := 160.0
var _overview := false
var _overview_prev := 30.0
func toggle_overview() -> void:
	_overview = not _overview
	if _overview:
		_overview_prev = rig.target_zoom
		rig.target_zoom = minf(_overview_prev * OVERVIEW_FACTOR, OVERVIEW_MAX)
	else:
		rig.target_zoom = _overview_prev
	audio.play("ui_move", -8.0, 0.0, 0.8 if _overview else 1.1)

func _pause() -> void:
	get_tree().paused = true
	pause_menu.info_zone = _zone_info.name
	var t := _run_time()
	pause_menu.info_time = "TIME  %02d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
	pause_menu.info_coins = "COINS  %d / %d" % [int(sim.coins), _coins_total]
	pause_menu.open()
	audio.set_muffled(true)
	audio.play("ui_select", -6.0, 0.0)

func _resume() -> void:
	pause_menu.close()
	get_tree().paused = false
	audio.set_muffled(false)
	settings.save_settings()

## Retry: back to spawn and reset the timer (EE Shift+R). Uses sim.restart() for a full reset if provided.
func restart_run() -> void:
	if sim.has_method(&"restart"):
		sim.restart()
	else:
		sim.reset()
	if ghost:
		ghost.on_reset()
	_coin_door_seen = false
	_play_ticks = 0
	_snap_render = true
	_key_dur.clear()
	_key_last.clear()
	rig.snap_to(_player_world_pos(1.0))
	var tw := create_tween()
	_fade.modulate.a = 0.6
	tw.tween_property(_fade, "modulate:a", 0.0, 0.6)

func _on_setting_changed(key: String, value: Variant) -> void:
	settings.set(key, value)
	match key:
		"master", "music", "sfx":
			_apply_audio_settings()
		"zoom":
			rig.target_zoom = float(value)
		"quality":
			_apply_quality()
		"fullscreen":
			_apply_fullscreen()
		"show_hints":
			hud.show_hints = bool(value)
		"show_collision":
			if collision_overlay:
				collision_overlay.visible = bool(value)
				collision_overlay.mark_dirty()
		"high_contrast":
			_apply_high_contrast()
		"cinematic_camera":
			_apply_camera_style()
	settings.save_settings()

## Day levels + "Cinematic camera": altitude-driven horizon pitch and a wider vertical fov (same visible width).
## Odyssey / night levels / setting off: the EE straight-on camera, exactly as before.
const DAY_FOV := 40.0
func _apply_camera_style() -> void:
	var on := _is_day() and settings.cinematic_camera
	rig.horizon_pitch_on = on
	rig.set_fov(DAY_FOV if on else CameraRig.FOV_V)
	if level:
		var h := float(cfg.get("horizon_tile_y", level.height * 0.5))
		rig.horizon_y = -h
		rig.horizon_top = -float(cfg.get("horizon_full_down_tile_y", 25))   # full look-down reached this high
		rig.horizon_bottom = -float(level.height)

## Accessibility: brighter/bigger gameplay glyphs (keys, arrows, dots) via ActorsView when it supports it.
func _apply_high_contrast() -> void:
	if actors and actors.has_method(&"set_glyph_boost"):
		actors.set_glyph_boost(1.5 if settings.high_contrast else 1.0)
	elif actors and actors.has_method(&"set_high_contrast"):
		actors.set_high_contrast(settings.high_contrast)

func _apply_audio_settings() -> void:
	audio.apply_volumes(settings.master, settings.music, settings.sfx)

func _apply_fullscreen() -> void:
	# Tests keep their off-screen, no-focus window untouched (CONTRACTS test rule).
	if DisplayServer.get_name() == "headless" or boot_options.get("no_save", false):
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED)

# ======================================================================= quality
func _find_world_env_node() -> WorldEnvironment:
	if world == null:
		return null
	var found := world.find_children("*", "WorldEnvironment", true, false)
	return found[0] as WorldEnvironment if found.size() > 0 else null

func _capture_authored_env() -> void:
	var env: Environment = world.get_environment() if world.has_method(&"get_environment") else null
	if env == null:
		return
	_authored_env = {"sdfgi": env.sdfgi_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled,
		"ssao": env.ssao_enabled, "vol": env.volumetric_fog_enabled, "glow": env.glow_enabled}
	var we := _find_world_env_node()
	if we and we.camera_attributes is CameraAttributesPractical:
		_authored_env["dof"] = (we.camera_attributes as CameraAttributesPractical).dof_blur_far_enabled

## Presets only switch OFF what the world authored (never enable something it didn't set up).
## ULTRA = authored look at native res; HIGH drops SDFGI/SSIL; MEDIUM also SSR + 85% res; LOW = FSR 67%.
func _apply_quality() -> void:
	var q := clampi(settings.quality, 0, 3)
	var env: Environment = world.get_environment() if world and world.has_method(&"get_environment") else null
	if env and not _authored_env.is_empty():
		env.sdfgi_enabled = _authored_env.sdfgi and q >= 3
		env.ssil_enabled = _authored_env.ssil and q >= 3
		env.ssr_enabled = _authored_env.ssr and q >= 2
		env.ssao_enabled = _authored_env.ssao and q >= 1
		env.volumetric_fog_enabled = _authored_env.vol and q >= 1
		env.glow_enabled = _authored_env.glow
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.67, 0.85, 1.0, 1.0][q]
	vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q < 3 else Viewport.SCREEN_SPACE_AA_SMAA
	# Geometry/shadow cost dominates (tests/game_perf.tscn): scale shadow atlas + mesh LOD with the preset.
	vp.positional_shadow_atlas_size = [2048, 4096, 8192, 8192][q]
	vp.mesh_lod_threshold = [4.0, 2.5, 1.5, 1.0][q]
	# Actors' ball-light shadows: HIGH/ULTRA only.
	if actors and actors.has_method(&"set_ball_shadows"):
		actors.set_ball_shadows(q >= 2)
	# World's shadowed key light (a SpotLight): shadows only at ULTRA (world's suggestion for HIGH).
	var key_light := world.get_node_or_null(^"Lights/KeyLight") as Light3D if world else null
	if key_light:
		if not _authored_env.has("key_shadow"):
			_authored_env["key_shadow"] = key_light.shadow_enabled
		key_light.shadow_enabled = _authored_env.key_shadow and q >= 3
	# Depth of field on the far background at HIGH+, only when the world didn't author camera attributes.
	var we := _find_world_env_node()
	var world_attrs: CameraAttributes = we.camera_attributes if we else null
	if world_attrs is CameraAttributesPractical:
		(world_attrs as CameraAttributesPractical).dof_blur_far_enabled = q >= 2 and _authored_env.get("dof", false)
	elif world_attrs == null and rig.cam:
		if q >= 2:
			var ca := CameraAttributesPractical.new()
			ca.dof_blur_far_enabled = true
			ca.dof_blur_far_distance = rig.distance_for_zoom(rig.zoom) + 7.0
			ca.dof_blur_far_transition = 45.0 if _is_day() else 14.0   # day: keep midground vista islands sharp
			ca.dof_blur_amount = 0.05
			rig.cam.attributes = ca
		else:
			rig.cam.attributes = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		settings.save_settings()

# ======================================================================= test helpers
func debug_state() -> Dictionary:
	if sim == null:
		return {"state": state}
	return {"state": State.keys()[state], "tick": _play_ticks, "px": sim.px, "py": sim.py, "coins": sim.coins,
		"zone": _zone_info.name, "god": sim.in_god_mode, "modules": modules}

func press_start() -> void:
	if state == State.TITLE:
		if _attract:
			_stop_attract()
			rig.snap_to(_player_world_pos(1.0))
		title.dismiss()
		_start_play(true)
