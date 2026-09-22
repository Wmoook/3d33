extends Node
## EX Odyssey game shell (main scene root).
## Flow: loading (world build with progress) -> cinematic title flyover -> swoop to player -> gameplay.
## Loop: exactly one sim.tick(input) per 100 Hz _physics_process; render interpolates prev -> cur with
## Engine.get_physics_interpolation_fraction(). Integrates EESim / WorldView / ActorsView from CONTRACTS.md,
## falling back to placeholders in scripts/game/fallback/ while those modules don't exist yet.

const LEVEL_PATH := "res://levels/ex_crew_odyssey.eelvl"
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
var victory: VictoryScreen
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
	settings.persist = not boot_options.get("no_save", false)
	if boot_options.has("quality"):
		settings.quality = int(boot_options.quality)
	if "--skip-title" in OS.get_cmdline_user_args():
		boot_options["skip_title"] = true
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
	_ui.add_child(minimap)
	title = TitleScreen.new()
	title.visible = false
	_ui.add_child(title)
	victory = VictoryScreen.new()
	_ui.add_child(victory)
	pause_menu = PauseMenu.new()
	pause_menu.settings = settings
	_ui.add_child(pause_menu)
	loading = LoadingScreen.new()
	_ui.add_child(loading)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_ui.add_child(_fade)
	hud.set_state({"visible": false})
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(func():
		_resume()
		restart_run())
	pause_menu.quit_title_requested.connect(_quit_to_title)
	pause_menu.quit_requested.connect(func():
		settings.save_settings()
		get_tree().quit())
	pause_menu.setting_changed.connect(_on_setting_changed)
	pause_menu.ui_sound.connect(func(n): audio.play(n, -6.0 if n == "ui_move" else -3.0, 0.0))

func _boot() -> void:
	loading.set_progress(0.02, "Awakening")
	await _frames(2)
	level = EELevel.load_file(LEVEL_PATH)
	if level == null:
		loading.set_progress(0.0, "Level file missing")
		return
	_coins_total = level.find_all(100).size()
	_blue_total = level.find_all(101).size()
	rig.level_size = Vector2(level.width, level.height)
	loading.set_progress(0.06, "Reading the old map")
	await _frames(1)
	sim = _instance(SIM_PATH, FB_SIM, "sim", [level])
	input = _instance(INPUT_PATH, FB_INPUT, "", [])
	if sim.has_signal(&"sim_event"):
		sim.sim_event.connect(_on_sim_event)
	loading.set_progress(0.1, "Raising the world")
	await _frames(1)
	world = _instance(WORLD_PATH, FB_WORLD, "world", [])
	world.name = "WorldView"
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
	_world_root.add_child(actors)
	actors.build(level, sim)
	loading.set_progress(0.9, "Charting the depths")
	await _frames(1)
	minimap.build(level, sim)
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
	_render_pos = _player_world_pos(1.0)
	loading.set_progress(0.96, "Lighting the torches")
	# Warm up: render a few frames at several places so pipelines compile before the reveal.
	for k in [Vector2(65, 8), Vector2(140, 100), Vector2(215, 95), Vector2(320, 150), Vector2(150, 185)]:
		rig.snap_to(Vector3(k.x, -k.y, 0))
		rig.follow(Vector3(k.x, -k.y, 0), Vector2.ZERO, 0.016)
		if world.has_method(&"update_focus"):
			world.update_focus(Vector3(k.x, -k.y, 0), 0.016)
		await _frames(2)
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
func _setup_cinematic() -> void:
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

func _enter_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	rig.begin_cinematic()
	title.restart_intro()
	hud.set_state({"visible": false})
	minimap.set_shown(false)
	audio.set_bed(&"title")
	audio.set_room(0.5)
	get_tree().create_timer(1.2).timeout.connect(func():
		if state == State.TITLE:
			audio.play("title_hit", -2.0, 0.0))

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
	ready_to_play.emit()

func _quit_to_title() -> void:
	_resume()
	restart_run()
	_enter_title()

# ======================================================================= loop
func _physics_process(_delta: float) -> void:
	if state != State.PLAYING or get_tree().paused or sim == null:
		return
	_fill_input()
	if _god_request:
		_god_request = false
		_toggle_god()
	sim.tick(input)
	_play_ticks += 1
	if "teleported" in sim:
		_snap_render = sim.teleported
	else:
		_snap_render = absf(sim.px - sim.prev_px) > 40.0 or absf(sim.py - sim.prev_py) > 40.0

func _fill_input() -> void:
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
	input.jump = Input.is_action_pressed(&"ee_jump") or _jump_latch
	_jump_latch = false

func _toggle_god() -> void:
	var on := not bool(sim.in_god_mode)
	if sim.has_method(&"set_god_mode"):
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
			rig.cinematic(delta, 0.07)
			_render_pos = _player_world_pos(1.0)
			_update_world_actors(rig.focus, delta)
		State.INTRO, State.PLAYING:
			if not paused:
				var f := 1.0 if _snap_render else Engine.get_physics_interpolation_fraction()
				if state == State.INTRO:
					f = 1.0
				_render_pos = _player_world_pos(f)
				var vel := Vector2(sim.px - sim.prev_px, -(sim.py - sim.prev_py)) * (100.0 / 16.0)
				rig.follow(_render_pos, vel, delta)
				_update_world_actors(_render_pos, delta)
			if state == State.INTRO:
				_intro_t += delta
				if _intro_t > 2.3:
					_go_live()
			if state == State.PLAYING:
				_update_zone(delta)
			_update_hud()

## Run timer: the sim's EE run timer (Me.ticks) when available, else shell ticks.
func _run_time() -> float:
	if "run_ticks" in sim:
		return int(sim.run_ticks) * 0.01
	return _play_ticks * 0.01

func _update_world_actors(focus: Vector3, delta: float) -> void:
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
	if z != _zone_candidate:
		_zone_candidate = z
		_zone_candidate_t = 0.0
	_zone_candidate_t += delta
	var first: bool = _zone is int and _zone == -2
	if z != _zone and (_zone_candidate_t > 0.35 or first):
		_zone = z
		_zone_info = _zone_info_for(z)
		audio.set_bed(_zone_info.bed, false)
		audio.set_room(_zone_info.reverb)
		minimap.zone_name = _zone_info.name
		if _zone_info.name != "":
			zone_card.show_zone(_zone_info.name, _zone_info.sub)
			audio.play("zone", -9.0, 0.0)

## Zone identity: WorldView is the source of truth (get_zone_at / get_zone_info, CONTRACTS "Zones");
## the shell's own rectangles (zones.gd) are only a fallback while WorldView lacks them.
func _zone_key_at(tile: Vector2i) -> Variant:
	if world and world.has_method(&"get_zone_at"):
		return world.get_zone_at(tile)
	return Zones.index_at(tile)

func _zone_info_for(z: Variant) -> Dictionary:
	if z is StringName or z is String:
		var d: Dictionary = world.get_zone_info(z) if world.has_method(&"get_zone_info") else {}
		var mood := str(d.get("music_mood", z)).to_lower()
		var fb := Zones.get_zone(Zones.index_at(EECoords.world_to_tile(_render_pos)))
		var title := str(d.get("title", fb.name))
		return {"name": title.to_upper(), "sub": str(d.get("subtitle", "")), "bed": _bed_for_mood(mood, fb.bed),
			"reverb": float(d.get("reverb", _reverb_for_mood(mood)))}
	var info := Zones.get_zone(int(z))
	return {"name": info.name, "sub": info.sub, "bed": info.bed, "reverb": info.reverb}

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
	hud.set_state({"coins": int(sim.coins), "coins_total": _coins_total, "blue": int(sim.blue_coins),
		"blue_total": _blue_total, "keys": keys, "time": _run_time(), "god": bool(sim.in_god_mode),
		"crown": bool(sim.has_crown), "zone": z.name})
	var he := rig.half_extents()
	var ptile := Vector2(_render_pos.x, -_render_pos.y)
	var cf := Vector2(rig.focus.x, -rig.focus.y)
	minimap.set_player(ptile, Rect2(cf - he, he * 2.0))

# ======================================================================= events
func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"coin", &"blue_coin":
			var now := Time.get_ticks_msec()
			_coin_combo = mini(_coin_combo + 1, 8) if now - _coin_last_ms < 1400 else 0
			_coin_last_ms = now
			var semis: int = [0, 2, 4, 5, 7, 9, 11, 12, 14][_coin_combo]
			audio.play(String(kind), -5.0, 0.0, pow(2.0, semis / 12.0))
			if data.has("tile"):
				minimap.erase_tile(data.tile)
		&"door_state", &"god_mode":
			minimap.refresh_doors()
		&"key":
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
			audio.play("jump", -13.0, 0.08)
		&"land":
			var imp := float(data.get("impact_speed", 0.0))
			if imp > 2.0:
				audio.play("land", lerpf(-20.0, -4.0, clampf(imp / 16.0, 0.0, 1.0)), 0.08)
			rig.add_trauma(clampf((imp - 7.0) / 10.0, 0.0, 1.0) * 0.45)
		&"gravity_changed":
			audio.play("gravity", -14.0, 0.1)
		&"checkpoint":
			audio.play("ui_select", -6.0, 0.0)
		&"secret":
			audio.play("blue_coin", -12.0, 0.0, 0.5)
		&"complete":
			audio.play("crown", 0.0, 0.0)
			hud.flash(UITheme.GOLD, 0.8)
			victory.show_stats({"time": _run_time(), "coins": int(sim.coins), "coins_total": _coins_total,
				"blue": int(sim.blue_coins), "blue_total": _blue_total, "deaths": int(sim.deaths) if "deaths" in sim else 0})

# ======================================================================= input / menus
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ee_fullscreen"):
		_on_setting_changed("fullscreen", not settings.fullscreen)
		return
	match state:
		State.TITLE:
			if title.accept_input and _is_any_press(event):
				get_viewport().set_input_as_handled()
				audio.play("ui_select", -2.0, 0.0)
				title.dismiss()
				_start_play(true)
		State.PLAYING:
			if pause_menu.is_open() or minimap.is_full():
				return
			if victory.is_open():
				if _is_any_press(event):
					get_viewport().set_input_as_handled()
					victory.dismiss()
				return
			if event.is_action_pressed(&"ee_pause"):
				get_viewport().set_input_as_handled()
				_pause()
			elif event.is_action_pressed(&"ee_jump"):
				_jump_latch = true
			elif event.is_action_pressed(&"ee_god"):
				_god_request = true
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

func _is_any_press(e: InputEvent) -> bool:
	if e is InputEventKey:
		return e.pressed and not e.echo and e.keycode != KEY_F11
	return (e is InputEventJoypadButton and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index <= MOUSE_BUTTON_RIGHT)

func _zoom(steps: float) -> void:
	rig.add_zoom_steps(steps)
	settings.zoom = rig.target_zoom

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
	settings.save_settings()

func _apply_audio_settings() -> void:
	audio.apply_volumes(settings.master, settings.music, settings.sfx)

func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
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
			ca.dof_blur_far_transition = 14.0
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
		title.dismiss()
		_start_play(true)
