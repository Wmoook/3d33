class_name FxMockSim
extends RefCounted
## Minimal stand-in for EESim (same public API) so actors visuals can be previewed without physics.

signal sim_event(kind: StringName, data: Dictionary)

var level: EELevel
var px := 0.0
var py := 0.0
var prev_px := 0.0
var prev_py := 0.0
var speed_x := 0.0
var speed_y := 0.0
var gravity_dir := Vector2i(0, 1)
var on_ground := true
var is_dead := false
var in_god_mode := false
var coins := 0
var blue_coins := 0
var has_crown := false
var has_silver_crown := false
var keys_active := {}
var collected := {}

func _init(lvl: EELevel) -> void:
	level = lvl
	var s := lvl.find_all(255)
	if not s.is_empty():
		px = s[0].x * 16.0
		py = s[0].y * 16.0

func reset() -> void:
	pass

func is_key_active(color: StringName) -> bool:
	return keys_active.get(color, false)

func key_time_left(color: StringName) -> float:
	return 6.0 if is_key_active(color) else 0.0

func is_tile_solid_now(tx: int, ty: int) -> bool:
	var id := level.get_fg(tx, ty)
	match id:
		23: return not is_key_active(&"red")
		24: return not is_key_active(&"green")
		25: return not is_key_active(&"blue")
		26: return is_key_active(&"red")
		28: return is_key_active(&"blue")
		43: return coins < int(level.get_extra(tx, ty).get("rotation", 0))
	return false

func is_coin_collected(tx: int, ty: int) -> bool:
	return collected.has(Vector2i(tx, ty))

func ticks() -> int:
	return 0

func set_tile(tx: float, ty: float) -> void:
	px = tx * 16.0
	py = ty * 16.0
	prev_px = px
	prev_py = py

func center() -> Vector3:
	return EECoords.player_center(px, py)
