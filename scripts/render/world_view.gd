class_name WorldView
extends Node3D
## The whole rendered world of EX Crew Odyssey: sculpted terrain, back walls, cave backdrops, props,
## lights, sky, environment/post and atmosphere zones blended from the focus (player) position.
## Usage:  var wv := WorldView.new(); add_child(wv); wv.build(lvl); ... wv.update_focus(player_pos, delta)

signal built

var level: EELevel
var sim: Object  # EESim (untyped so the world builds without the physics module)
var terrain: WorldTerrain
var lights: WorldLights
var atmosphere: WorldAtmosphere
var decor: WorldDecor
var backdrop: WorldBackdrop
var is_built := false
var build_ms := 0
var timings := {}

func build(lvl: EELevel) -> void:
	var t0 := Time.get_ticks_msec()
	level = lvl
	terrain = WorldTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(lvl)
	timings.merge(terrain.timings)
	var t := Time.get_ticks_msec()
	backdrop = WorldBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	backdrop.build(lvl, terrain)
	timings["backdrop"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	decor = WorldDecor.new()
	decor.name = "Decor"
	add_child(decor)
	decor.build(lvl, terrain)
	timings["decor"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	lights = WorldLights.new()
	lights.name = "Lights"
	add_child(lights)
	lights.build(lvl, terrain)
	timings["lights"] = Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	atmosphere = WorldAtmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.build(lvl, terrain, lights)
	timings["atmosphere"] = Time.get_ticks_msec() - t
	build_ms = Time.get_ticks_msec() - t0
	is_built = true
	print("WorldView built in %d ms %s" % [build_ms, str(timings)])
	built.emit()

func set_sim(s) -> void:
	sim = s

func update_focus(world_pos: Vector3, delta: float) -> void:
	if not is_built:
		return
	atmosphere.update_focus(world_pos, delta)
	lights.update_focus(world_pos, delta)
	decor.update_focus(world_pos, delta)
	backdrop.update_focus(world_pos, delta)

func get_environment() -> Environment:
	return atmosphere.environment if atmosphere else null

## Debug: overlay the true collision grid (green = air, red = solid, yellow tile lines).
func set_debug_grid(on: bool) -> void:
	if terrain:
		terrain.set_debug_grid(on)
