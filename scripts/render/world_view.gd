class_name WorldView
extends Node3D
## The whole rendered world of EX Crew Odyssey: sculpted terrain, dynamic key doors/gates, back walls,
## cave backdrops, props, lights, sky, environment/post, and named zones with atmosphere crossfades
## driven by the focus position.
## Usage: add_child(wv); wv.build(lvl) (or `await wv.build_progressive(lvl, progress)`); wv.set_sim(sim);
##        every frame wv.update_focus(player_or_camera_world_pos, delta).

signal built
## Emitted from update_focus() when the focus settles in another named zone (0.4 s hysteresis).
signal zone_changed(zone: StringName)

const ZONE_HYSTERESIS := 0.4

var level: EELevel
var sim: Object  # EESim (untyped so the world builds without the physics module)
var terrain: WorldTerrain
var doors: WorldDoors
var lights: WorldLights
var atmosphere: WorldAtmosphere
var decor: WorldDecor
var backdrop: WorldBackdrop
var zones: WorldZones
var trials: WorldTrials
var grass: WorldGrass
var foliage: WorldFoliage
var is_built := false
var build_ms := 0
var timings := {}
## Level config (LevelCatalog, levels/config/<id>.json). Defaults = EX Crew Odyssey.
var config := {"id": "odyssey", "ref_dir": "res://assets/ee_ref", "time_of_day": "night"}
var current_zone: StringName = &""
var _cand_zone: StringName = &""
var _cand_time := 0.0

## Call BEFORE build(): selects the level's reference art, zones, atmosphere and special tuning.
func set_level_config(cfg: Dictionary) -> void:
	config.merge(cfg, true)

func is_day() -> bool:
	return str(config.get("time_of_day", "night")) == "day"

func build(lvl: EELevel) -> void:
	for step in _steps(lvl):
		step[1].call()
	_finish()

## Same as build(), yielding a frame between stages and reporting progress.call(frac, label).
func build_progressive(lvl: EELevel, progress: Callable) -> void:
	var st := _steps(lvl)
	for k in st.size():
		if progress.is_valid():
			progress.call(float(k) / st.size(), st[k][0])
		await get_tree().process_frame
		st[k][1].call()
	_finish()
	if progress.is_valid():
		progress.call(1.0, "World ready")

func _steps(lvl: EELevel) -> Array:
	level = lvl
	WorldPalette.level_id = str(config.get("id", "odyssey"))
	build_ms = Time.get_ticks_msec()
	return [
		["Sculpting stone and earth", _step_terrain],
		["Forging the key doors", _step_doors],
		["Charting the depths", _step_zones],
		["Marking the trial chambers", _step_trials],
		["Raising the far hills", _step_backdrop],
		["Growing grass and roots", _step_decor],
		["Lighting the fires", _step_lights],
		["Breathing in the air", _step_atmosphere],
	]

func _step_terrain() -> void:
	terrain = WorldTerrain.new()
	terrain.ref_dir = str(config.get("ref_dir", "res://assets/ee_ref"))
	terrain.day = is_day()
	_add(terrain, "Terrain")
	terrain.build(level)
	timings.merge(terrain.timings)

func _step_doors() -> void:
	var t := Time.get_ticks_msec()
	doors = _add(WorldDoors.new(), "Doors")
	doors.build(level, terrain)
	timings["doors"] = Time.get_ticks_msec() - t

func _step_zones() -> void:
	var t := Time.get_ticks_msec()
	zones = WorldZones.new()
	zones.build(terrain)
	terrain.set_zone_map(zones.tile_zone)
	terrain.set_visual_map(zones.visual)
	timings["zones"] = Time.get_ticks_msec() - t

func _step_trials() -> void:
	if WorldPalette.is_odyssey():
		return
	var t := Time.get_ticks_msec()
	trials = WorldTrials.new()
	_add(trials, "Trials")
	trials.build(level, terrain)
	timings["trials"] = Time.get_ticks_msec() - t

func _step_backdrop() -> void:
	var t := Time.get_ticks_msec()
	backdrop = _add(WorldBackdrop.new(), "Backdrop")
	backdrop.build(level, terrain)
	timings["backdrop"] = Time.get_ticks_msec() - t

func _step_decor() -> void:
	var t := Time.get_ticks_msec()
	decor = _add(WorldDecor.new(), "Decor")
	decor.build(level, terrain)
	if is_day():   # Odyssey keeps its approved grass / leaf clusters
		grass = _add(WorldGrass.new(), "Grass")
		grass.build(level, terrain)
		foliage = _add(WorldFoliage.new(), "Foliage")
		foliage.build(level, terrain)
	timings["decor"] = Time.get_ticks_msec() - t

func _step_lights() -> void:
	var t := Time.get_ticks_msec()
	lights = WorldLights.new()
	lights.day = is_day()
	_add(lights, "Lights")
	lights.build(level, terrain)
	timings["lights"] = Time.get_ticks_msec() - t

func _step_atmosphere() -> void:
	var t := Time.get_ticks_msec()
	atmosphere = WorldAtmosphere.new()
	atmosphere.day = is_day()
	_add(atmosphere, "Atmosphere")
	atmosphere.build(level, terrain, lights, zones)
	timings["atmosphere"] = Time.get_ticks_msec() - t

func _add(n: Node, nm: String) -> Node:
	n.name = nm
	add_child(n)
	return n

func _finish() -> void:
	build_ms = Time.get_ticks_msec() - build_ms
	is_built = true
	if sim:
		doors.sim = sim
		if trials:
			trials.sim = sim
	print("WorldView built in %d ms %s" % [build_ms, str(timings)])
	built.emit()

func set_sim(s) -> void:
	sim = s
	if doors:
		doors.sim = s
	if trials:
		trials.sim = s

func update_focus(world_pos: Vector3, delta: float) -> void:
	if not is_built:
		return
	atmosphere.update_focus(world_pos, delta)
	lights.update_focus(world_pos, delta)
	decor.update_focus(world_pos, delta)
	if grass:
		grass.update_focus(world_pos, delta)
	if foliage:
		foliage.update_focus(world_pos, delta)
	backdrop.update_focus(world_pos, delta)
	var z := get_zone_at(EECoords.world_to_tile(world_pos))
	if current_zone == &"":
		current_zone = z
		zone_changed.emit(z)
	elif z != current_zone:
		if z != _cand_zone:
			_cand_zone = z
			_cand_time = 0.0
		_cand_time += delta
		if _cand_time >= ZONE_HYSTERESIS:
			current_zone = z
			_cand_zone = &""
			zone_changed.emit(z)
	else:
		_cand_zone = &""

func get_environment() -> Environment:
	return atmosphere.environment if atmosphere else null

## Named zone at a tile (EE tile coords, y down). O(1).
func get_zone_at(tile: Vector2i) -> StringName:
	return zones.zone_at(tile) if zones else &"underworld"

## Trial chambers (Forgotten Veil's challenge rooms): 1..trial_count() for a tile inside a room, else 0.
func get_trial_at(tile: Vector2i) -> int:
	return trials.get_trial_at(tile) if trials else 0

func trial_count() -> int:
	return trials.trial_count() if trials else 0

## {name, title, subtitle, music_mood, reverb, visual}
func get_zone_info(zone: StringName) -> Dictionary:
	return zones.info(zone) if zones else {}

## Debug: 1 = true collision grid overlay (red solid / green air / yellow tile lines), 2 = zone map.
func set_debug_grid(on: bool) -> void:
	if terrain:
		terrain.set_debug_mode(1 if on else 0)

func set_debug_mode(mode: int) -> void:
	if terrain:
		terrain.set_debug_mode(mode)
