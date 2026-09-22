extends RefCounted
## PLACEHOLDER for EESim (scripts/physics/ee_sim.gd) so the shell runs before physics lands.
## Implements the contract surface with rough EE-like movement. NOT the real EE physics.

signal sim_event(kind: StringName, data: Dictionary)

const SOLID := [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23, 24, 25, 29, 30, 31, 35, 37, 38, 39, 40,
	41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 87]

var level
var px := 0.0
var py := 0.0
var prev_px := 0.0
var prev_py := 0.0
var speed_x := 0.0
var speed_y := 0.0
var gravity_dir := Vector2i(0, 1)
var on_ground := false
var is_dead := false
var in_god_mode := false
var coins := 0
var blue_coins := 0
var has_crown := false
var _ticks := 0
var _collected := {}
var _solid := {}
var _prev_jump := false

func _init(lvl) -> void:
	level = lvl
	for id in SOLID:
		_solid[id] = true
	reset()

func reset() -> void:
	var sp: Array = level.find_all(255)
	var s: Vector2i = sp[0] if sp.size() > 0 else Vector2i(1, 1)
	px = s.x * 16.0
	py = s.y * 16.0
	prev_px = px
	prev_py = py
	speed_x = 0.0
	speed_y = 0.0
	sim_event.emit(&"respawn", {})

func set_god_mode(on: bool) -> void:
	in_god_mode = on

func ticks() -> int:
	return _ticks

func is_key_active(_c: StringName) -> bool:
	return false

func key_time_left(_c: StringName) -> float:
	return 0.0

func is_coin_collected(tx: int, ty: int) -> bool:
	return _collected.has(Vector2i(tx, ty))

func is_tile_solid_now(tx: int, ty: int) -> bool:
	var id: int = level.get_fg(tx, ty)
	return id == -1 or _solid.has(id)

func tick(input) -> void:
	_ticks += 1
	prev_px = px
	prev_py = py
	var h := (1.0 if input.right else 0.0) - (1.0 if input.left else 0.0)
	var v := (1.0 if input.down else 0.0) - (1.0 if input.up else 0.0)
	if in_god_mode:
		speed_x = (speed_x + h * 0.6) * 0.9
		speed_y = (speed_y + v * 0.6) * 0.9
		px += speed_x
		py += speed_y
		return
	speed_x = (speed_x + h * 0.25) * 0.93
	speed_y = minf(speed_y + 0.2, 9.0)
	if input.jump and not _prev_jump and on_ground:
		speed_y = -4.3
		sim_event.emit(&"jump", {})
	_prev_jump = input.jump
	_move(speed_x, true)
	var was_ground := on_ground
	var vy := speed_y
	on_ground = false
	_move(speed_y, false)
	if on_ground and not was_ground and vy > 1.5:
		sim_event.emit(&"land", {"impact_speed": vy * 3.0})
	_pickups()

func _move(d: float, horiz: bool) -> void:
	var steps := int(ceilf(absf(d)))
	if steps == 0:
		return
	var s := d / steps
	for i in steps:
		var nx := px + (s if horiz else 0.0)
		var ny := py + (0.0 if horiz else s)
		if _box_hits(nx, ny):
			if horiz:
				speed_x = 0.0
			else:
				if s > 0:
					on_ground = true
				speed_y = 0.0
			return
		px = nx
		py = ny

func _box_hits(x: float, y: float) -> bool:
	for ty in range(int(floorf(y / 16.0)), int(floorf((y + 15.99) / 16.0)) + 1):
		for tx in range(int(floorf(x / 16.0)), int(floorf((x + 15.99) / 16.0)) + 1):
			if is_tile_solid_now(tx, ty):
				return true
	return false

func _pickups() -> void:
	var t := Vector2i(int(floorf((px + 8) / 16.0)), int(floorf((py + 8) / 16.0)))
	var id: int = level.get_fg(t.x, t.y)
	if (id == 100 or id == 101) and not _collected.has(t):
		_collected[t] = true
		if id == 100:
			coins += 1
			sim_event.emit(&"coin", {"tile": t})
		else:
			blue_coins += 1
			sim_event.emit(&"blue_coin", {"tile": t})
