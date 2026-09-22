extends Node
## Run recording + best-run ghost (uses physics' deterministic EEReplay, scripts/physics/ee_replay.gd).
## - Every run is recorded tick by tick (record() right before sim.tick, from the last sim.reset()).
## - On level complete, a faster run replaces user://best.eerp (meta: ticks, coins, state hash, date).
## - During later runs a second EESim replays the best run one tick per player tick, i.e. in sync with the
##   run timer; its ball is drawn as a translucent, desaturated, unlit ghost (H toggles it).
## Preloaded by path (not class_name) so a stale class cache can't break boot.

signal best_changed(ticks: int)

const SIM_PATH := "res://scripts/physics/ee_sim.gd"
const REPLAY_PATH := "res://scripts/physics/ee_replay.gd"

var best_path := "user://best.eerp"
var level
var sim
var actors: Node3D
var available := false          # EEReplay + EESim present
var rec                          # EEReplay of the current run
var best                         # EEReplay of the best run (or null)
var best_ticks := -1
var ghost_sim                    # EESim replaying `best`
var ghost_enabled := true
var ghost_node: Node3D
var _ghost_is_actor := false
var _ghost_alpha := 0.0
var _running := false            # ghost_sim was restarted for the current run
var _Replay: Script

func setup(lvl, s, actors_view: Node3D, parent3d: Node3D) -> void:
	level = lvl
	sim = s
	actors = actors_view
	if not (ResourceLoader.exists(REPLAY_PATH) and ResourceLoader.exists(SIM_PATH)):
		return
	_Replay = load(REPLAY_PATH)
	var S: Script = load(SIM_PATH)
	if _Replay == null or S == null or not _Replay.can_instantiate() or not S.can_instantiate():
		return
	available = true
	rec = _Replay.new()
	ghost_sim = S.new(lvl)
	_make_ghost_node(parent3d)
	load_best()

func load_best() -> void:
	best = null
	best_ticks = -1
	if not available or not FileAccess.file_exists(best_path):
		best_changed.emit(best_ticks)
		return
	var r = _Replay.load_file(best_path)
	if r != null and r.tick_count() > 0:
		best = r
		best_ticks = int(r.meta.get("ticks", r.tick_count()))
	best_changed.emit(best_ticks)
	restart_ghost()

## Call whenever the player's sim is reset (new run).
func on_reset() -> void:
	if not available:
		return
	rec.clear()
	restart_ghost()

func restart_ghost() -> void:
	if not available or best == null:
		return
	best.start(ghost_sim)   # ghost_sim.reset() + cursor 0
	_ghost_alpha = 0.0
	_running = true

## Call right BEFORE sim.tick(input) every tick.
func record(input) -> void:
	if available:
		rec.record(input)

## Call right AFTER the player's tick: advances the ghost by one tick (in sync with the run timer).
func tick_ghost() -> void:
	if available and best != null and _running:
		best.step(ghost_sim)

func ghost_finished() -> bool:
	return best == null or best.is_finished()

## Level complete: keep the run if it's the best. Returns true on a new best.
func on_complete(run_ticks: int) -> bool:
	if not available or rec.tick_count() == 0:
		return false
	if best_ticks >= 0 and run_ticks >= best_ticks:
		return false
	rec.meta = {"ticks": run_ticks, "level": str(level.world_name), "coins": int(sim.coins),
		"blue_coins": int(sim.blue_coins), "hash": int(sim.state_hash()) if sim.has_method(&"state_hash") else 0,
		"date": Time.get_datetime_string_from_system()}
	var err: Error = rec.save(best_path)
	if err != OK:
		push_warning("[ghost] could not save %s (%d)" % [best_path, err])
	best = _Replay.from_bytes(rec.to_bytes())   # independent copy; the ghost for the NEXT run
	best_ticks = run_ticks
	_running = false          # new ghost starts with the next run
	best_changed.emit(best_ticks)
	return true

func toggle() -> void:
	ghost_enabled = not ghost_enabled

## Per render frame: interpolated ghost ball.
func update_visual(f: float, delta: float) -> void:
	if ghost_node == null:
		return
	var show := available and ghost_enabled and best != null and _running
	var target := 0.0
	if show and not best.is_finished():
		target = 1.0
	_ghost_alpha = move_toward(_ghost_alpha, target, delta * 2.5)
	ghost_node.visible = show and _ghost_alpha > 0.01
	if not ghost_node.visible:
		return
	var tele: bool = "teleported" in ghost_sim and ghost_sim.teleported
	var k := 1.0 if tele else f
	var pos := EECoords.player_center(lerpf(ghost_sim.prev_px, ghost_sim.px, k), lerpf(ghost_sim.prev_py, ghost_sim.py, k))
	if _ghost_is_actor:
		ghost_node.update_ghost(pos, ghost_sim, delta)
		if "modulate_alpha" in ghost_node:
			ghost_node.modulate_alpha = _ghost_alpha
	else:
		ghost_node.position = pos
		var mat := (ghost_node as MeshInstance3D).material_override as StandardMaterial3D
		mat.albedo_color.a = 0.35 * _ghost_alpha
		ghost_node.rotation.z = -(pos.x / 0.5)  # roll: angle = distance / radius

func _make_ghost_node(parent3d: Node3D) -> void:
	if actors and actors.has_method(&"create_ghost_ball"):
		ghost_node = actors.create_ghost_ball()
		_ghost_is_actor = ghost_node != null and ghost_node.has_method(&"update_ghost")
	if ghost_node == null or not _ghost_is_actor:
		# Fallback ghost: pale translucent unlit-looking sphere with a fresnel rim, no light, no shadow.
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 32
		sm.rings = 16
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.82, 0.86, 0.95, 0.35)
		m.emission_enabled = true
		m.emission = Color(0.55, 0.62, 0.8)
		m.emission_energy_multiplier = 0.35
		m.rim_enabled = true
		m.rim = 1.0
		m.rim_tint = 0.2
		m.roughness = 0.4
		m.cull_mode = BaseMaterial3D.CULL_BACK
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost_node = mi
		_ghost_is_actor = false
	ghost_node.name = "GhostBall"
	ghost_node.visible = false
	parent3d.add_child(ghost_node)
