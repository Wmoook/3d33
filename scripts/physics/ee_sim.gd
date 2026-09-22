class_name EESim
extends RefCounted
## Bit-faithful port of the ORIGINAL Everybody Edits Offline player physics and world rules
## (upstream AS3: Player.as tick(), Me.as touchBlock(), World.as overlaps()/update(),
## PlayState.as tick()/enterFrame(), Config.as, ItemId.as).
## One call to tick() == one original 10 ms physics tick. All math is double precision,
## in the same order as the AS3 source, with the same int truncations (>>0, <<8, >>4).
##
## Units: px/py = top-left of the 16x16 player box in EE pixels (y down).
## speed_x/speed_y = the internal AS3 `_speedX/_speedY` = pixels moved per tick
## (EE's public `speedX` getter is this * 7.752). The +-16 clamp applies to these.

signal sim_event(kind: StringName, data: Dictionary)

# ---------------------------------------------------------------- Config.as
const MS_PER_TICK := 10
const MULT := 7.752                                   # physics_variable_multiplyer
static var BASE_DRAG: float = pow(0.9981, 10) * 1.00016093
static var ICE_NO_MOD_DRAG: float = pow(0.9993, 10) * 1.00016093
static var ICE_DRAG: float = pow(0.9998, 10) * 1.00016093
static var NO_MOD_DRAG: float = pow(0.9900, 10) * 1.00016093
static var WATER_DRAG: float = pow(0.9950, 10) * 1.00016093
static var MUD_DRAG: float = pow(0.9750, 10) * 1.00016093
static var LAVA_DRAG: float = pow(0.9800, 10) * 1.00016093
static var TOXIC_DRAG: float = pow(0.9900, 10) * 1.00016093
const JUMP_HEIGHT := 26.0
const GRAVITY := 2.0
const BOOST := 16.0
const WATER_BUOYANCY := -0.5
const MUD_BUOYANCY := 0.4
const LAVA_BUOYANCY := 0.2
const TOXIC_BUOYANCY := -0.4
const QUEUE_LENGTH := 2
const PING := 0.2                                      # Global.ping (offline constant)
## Stand-in for `new Date().time` at sim start. Only differences matter, but the sign
## tricks in the jump timer (lastJump = -now) need a large positive clock like a real date.
const CLOCK_BASE := 1_000_000_000_000

# ---------------------------------------------------------------- ItemId.as
const COIN_GOLD := 100
const COIN_BLUE := 101
const COLLECTED_COIN := 110
const COLLECTED_BLUECOIN := 111
const CROWN := 5
const BRICK_COMPLETE := 121
const PORTAL := 242
const PORTAL_INVISIBLE := 381
const WORLD_PORTAL := 374
const SPAWNPOINT := 255
const CHECKPOINT := 360
const SPEED_LEFT := 114
const SPEED_RIGHT := 115
const SPEED_UP := 116
const SPEED_DOWN := 117
const WATER := 119
const MUD := 369
const LAVA := 416
const TOXIC_WASTE := 1585
const FIRE := 368
const ICE := 1064
const SWITCH_PURPLE := 113
const RESET_PURPLE := 1619
const DOOR_PURPLE := 184
const GATE_PURPLE := 185
const SWITCH_ORANGE := 467
const RESET_ORANGE := 1620
const DOOR_ORANGE := 1079
const GATE_ORANGE := 1080
const COINDOOR := 43
const COINGATE := 165
const BLUECOINDOOR := 213
const BLUECOINGATE := 214
const DEATH_DOOR := 1011
const DEATH_GATE := 1012
const EFFECT_JUMP := 417
const EFFECT_FLY := 418
const EFFECT_RUN := 419
const EFFECT_PROTECTION := 420
const EFFECT_CURSE := 421
const EFFECT_ZOMBIE := 422
const EFFECT_TEAM := 423
const EFFECT_LOW_GRAVITY := 453
const EFFECT_MULTIJUMP := 461
const EFFECT_GRAVITY := 1517
const EFFECT_POISON := 1584
const EFFECT_RESET := 1618
const SPIKE_IDS := [361, 1580, 1625, 1626, 1627, 1628, 1629, 1630, 1631, 1632, 1633, 1634, 1635, 1636]
const CLIMBABLE_IDS := [120, 118, 98, 99, 424, 459, 460, 472, 1534, 1146, 1563, 1602]
const JUMP_THROUGH_IDS := [61, 62, 63, 64, 89, 90, 91, 96, 97, 122, 123, 124, 125, 126, 127, 146, 154, 158,
	194, 211, 216, 1069, 1087, 1001, 1002, 1003, 1004, 1052, 1053, 1054, 1055, 1056, 1092, 1050, 1051, 1164,
	1165, 1147, 1148, 1149, 1155, 1160]
const ROT_HALF_IDS := [1001, 1002, 1003, 1004, 1052, 1053, 1054, 1055, 1056, 1092, 1155]
const HALF_IDS := [1041, 1042, 1043, 1075, 1076, 1077, 1078, 1101, 1102, 1103, 1104, 1105, 1116, 1117, 1118,
	1119, 1120, 1121, 1122, 1123, 1124, 1125, 1140, 1141]
const NONROT_HALF_IDS := [1101, 1102, 1103, 1104, 1105]
## Dynamic solids handled by the door/gate switch in World.overlaps() (+50: secret reveal).
const DOOR_IDS := [23, 24, 25, 26, 27, 28, 1005, 1006, 1007, 1008, 1009, 1010, 156, 157, 184, 185, 1079, 1080,
	200, 201, 1094, 1095, 1152, 1153, 43, 213, 1011, 165, 214, 1012, 1027, 1028, 206, 207, 50]
const KEY_COLORS := {6: &"red", 7: &"green", 8: &"blue", 408: &"cyan", 409: &"magenta", 410: &"yellow"}
const COLORS: Array[StringName] = [&"red", &"green", &"blue", &"cyan", &"magenta", &"yellow"]

const F_SOLID := 1
const F_JUMPTHRU := 2
const F_ROTHALF := 4
const F_HALF := 8
const F_DOOR := 16
const F_CLIMB := 32
const F_LIQUID := 64
const F_BOOST := 128

# ---------------------------------------------------------------- public state (CONTRACTS.md)
var level: EELevel
var px: float = 16.0
var py: float = 16.0
var prev_px: float = 16.0
var prev_py: float = 16.0
var speed_x: float = 0.0        # AS3 _speedX (px per tick)
var speed_y: float = 0.0        # AS3 _speedY (px per tick)
var gravity_dir := Vector2i(0, 1)
var on_ground := false
var is_dead := false
var in_god_mode := false
var coins := 0
var blue_coins := 0
var has_crown := false

# ---------------------------------------------------------------- extra public state
var has_silver_crown := false   # touched 121 (brick complete) = level completed
var deaths := 0
var checkpoint := Vector2i(-1, -1)
## True when the last tick moved the player discontinuously (portal / respawn): skip interpolation.
var teleported := false
var modifier_x: float = 0.0     # AS3 _modifierX
var modifier_y: float = 0.0
var current_tile := 0           # AS3 `current` (id at the player's center this tick)
var flip_gravity := 0           # EFFECT_GRAVITY rotation
var jump_count := 0
var max_jumps := 1
var jump_boost := 0
var speed_boost := 0
var low_gravity := false
var is_invulnerable := false
var is_on_fire := false
var run_ticks := 0              # Me.ticks (run timer)
var morx := 0                   # int, like AS3
var mory := 0
var mox: float = 0.0
var moy: float = 0.0

# ---------------------------------------------------------------- world state
var width := 0
var height := 0
var tiles := PackedInt32Array()    # live layer 0 (coins become 110/111 when collected)
var _lookup := PackedInt32Array()  # Lookup.getInt per tile (rotation / number)
var _flags := PackedByteArray()
var _portals := {}                 # tile index -> Vector3i(id, target, rotation)
var _portals_by_id := {}           # portal id -> Array[Vector2i] of px positions (x<<4, y<<4)
var _spawns: Array[Vector2i] = []
var _next_spawn := 0
var _secrets := PackedByteArray()
var _keys := {}                    # color -> bool
var _keys_timer := {}              # color -> float (World.offset at pickup)
var _offset: float = 0.0           # World.offset (+0.3 per tick)
var _timedoor_state := false
var _hide_timedoor_offset: float = 0.0
var _show_coin_gate := 0
var _show_blue_coin_gate := 0
var _show_death_gate := 0
var _orange_switches := {}
var _switches := {}                # per-player purple switches
var _collide_crown := false
var _collide_silver_crown := false
var _state_queue: Array[Callable] = []   # PlayState.queue
var _keys_queue: Array = []              # PlayState.keysquene
var _tile_queue: Array[Callable] = []    # Player.tilequeue
var _has_time_doors := false
var _coin_door_thresholds := PackedInt32Array()
var _blue_coin_door_thresholds := PackedInt32Array()
var _rng := RandomNumberGenerator.new()
var world_gravity_multiplier := 1.0

# ---------------------------------------------------------------- player internals
var _ticks := 0
var _queue := PackedInt32Array()
var _last_jump: float = 0.0
var _slippery: float = 0.0
var _pastx := 0
var _pasty := 0
var _ox: float = 0.0               # Player.ox/oy (position before the current sub-step)
var _oy: float = 0.0
var overlapa := -1
var overlapb := -1
var overlapc := -1
var overlapd := -1
var _last_portal_set := true       # AS3: lastPortal = new Point() (non-null) initially
var _last_portal := Vector2i.ZERO
var _dead_offset: float = 0.0
var _fire_time_start: float = 0.0
var _fire_duration: float = 0.0
var _horizontal := 0
var _vertical := 0
var _spacedown := false
var _spacejustdown := false
var _prev_jump_held := false
var _mx: float = 0.0
var _my: float = 0.0
# movement-loop locals of Player.tick() (members because GDScript lambdas can't write outer locals)
var _rem_x: float = 0.0
var _rem_y: float = 0.0
var _cur_sx: float = 0.0
var _cur_sy: float = 0.0
var _osx: float = 0.0
var _osy: float = 0.0
var _donex := false
var _doney := false
var _grounded := false
var _land_speed: float = 0.0
# for diff-based events
var _ev_keys := {}
var _ev_coins := 0
var _ev_bcoins := 0
var _ev_timedoor := false
var _ev_grav := Vector2i(0, 1)


func _init(lvl: EELevel) -> void:
	level = lvl
	_build_flags()
	reset()


# ================================================================ public API

## Fresh start, like loading the level: coins restored, keys off, timers zero, player at spawn.
func reset() -> void:
	width = level.width
	height = level.height
	world_gravity_multiplier = level.gravity if level.gravity > 0.0 else 1.0
	tiles = level.fg.duplicate()
	_lookup = PackedInt32Array(); _lookup.resize(width * height)
	_portals.clear(); _portals_by_id.clear(); _spawns.clear()
	var cd := {}
	var bcd := {}
	for i: int in level.extra:
		var ex: Dictionary = level.extra[i]
		var t := tiles[i]
		if t == PORTAL or t == PORTAL_INVISIBLE:
			var p := Vector3i(int(ex.get("id", 0)), int(ex.get("target", 0)), int(ex.get("rotation", 0)))
			_portals[i] = p
			if not _portals_by_id.has(p.x):
				_portals_by_id[p.x] = []
			(_portals_by_id[p.x] as Array).append(Vector2i((i % width) << 4, (i / width) << 4))
		elif ex.has("rotation"):
			_lookup[i] = int(ex["rotation"])
			if t == COINDOOR or t == COINGATE:
				cd[int(ex["rotation"])] = true
			elif t == BLUECOINDOOR or t == BLUECOINGATE:
				bcd[int(ex["rotation"])] = true
	_coin_door_thresholds = PackedInt32Array(cd.keys()); _coin_door_thresholds.sort()
	_blue_coin_door_thresholds = PackedInt32Array(bcd.keys()); _blue_coin_door_thresholds.sort()
	# World.deserializeFromMessage: spawnPoints[0] in data order (x-major within a block entry);
	# the loader flattened the order, so use scan order (only one spawn in EX Crew Odyssey).
	_has_time_doors = false
	for i in tiles.size():
		var t := tiles[i]
		if t == SPAWNPOINT:
			_spawns.append(Vector2i(i % width, i / width))
		elif t == 156 or t == 157:
			_has_time_doors = true
	_next_spawn = 0
	_secrets = PackedByteArray(); _secrets.resize(width * height)
	for c in COLORS:
		_keys[c] = false
		_keys_timer[c] = 0.0
	_offset = 0.0
	_timedoor_state = false
	_hide_timedoor_offset = 0.0
	_show_coin_gate = 0; _show_blue_coin_gate = 0; _show_death_gate = 0
	_orange_switches.clear(); _switches.clear()
	_state_queue.clear(); _keys_queue.clear(); _tile_queue.clear()
	_rng.seed = 0x5EED
	# Player constructor + PlayState constructor
	_ticks = 0
	_queue = PackedInt32Array(); _queue.resize(QUEUE_LENGTH)
	_last_jump = -float(_now())
	_slippery = 0.0
	_pastx = 0; _pasty = 0
	overlapa = -1; overlapb = -1; overlapc = -1; overlapd = -1
	_last_portal_set = true; _last_portal = Vector2i.ZERO
	has_crown = false; has_silver_crown = false
	_collide_crown = false; _collide_silver_crown = false
	coins = 0; blue_coins = 0; deaths = 0
	checkpoint = Vector2i(-1, -1)
	flip_gravity = 0; jump_count = 0; max_jumps = 1; jump_boost = 0; speed_boost = 0
	low_gravity = false; is_invulnerable = false; is_on_fire = false
	is_dead = false; _dead_offset = 0.0
	run_ticks = 0
	speed_x = 0.0; speed_y = 0.0; modifier_x = 0.0; modifier_y = 0.0
	morx = 0; mory = 0; mox = 0.0; moy = 0.0
	_horizontal = 0; _vertical = 0; _spacedown = false; _spacejustdown = false; _prev_jump_held = false
	on_ground = false
	gravity_dir = Vector2i(0, 1)
	px = 16.0; py = 16.0
	_place_at_spawn(false)
	_ox = px; _oy = py
	prev_px = px; prev_py = py
	teleported = true
	_ev_keys = _keys.duplicate(); _ev_coins = 0; _ev_bcoins = 0; _ev_timedoor = false; _ev_grav = gravity_dir
	sim_event.emit(&"respawn", {"pos": Vector2(px, py)})


func ticks() -> int:
	return _ticks


func is_key_active(color: StringName) -> bool:
	return _keys.get(color, false)


## Seconds until the key expires (EE keys last 5 s: (offset - timer)/30 >= 5).
func key_time_left(color: StringName) -> float:
	if not _keys.get(color, false):
		return 0.0
	return maxf(0.0, 5.0 - (_offset - float(_keys_timer[color])) / 30.0)


## Current dynamic solidity of a layer-0 tile for the local player (doors/gates/coin doors).
## One-way platforms (e.g. 62) and half blocks count as solid; out of bounds is solid.
func is_tile_solid_now(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return true
	var val := tiles[ty * width + tx]
	var fl := _flag(val)
	if fl & F_SOLID == 0:
		return false
	if fl & F_DOOR != 0:
		return not _door_passable(val, tx, ty)
	return true


## True for blocks you can jump through from below (one-way).
func is_tile_one_way(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return false
	return _flag(tiles[ty * width + tx]) & F_JUMPTHRU != 0


func is_coin_collected(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return false
	var t := tiles[ty * width + tx]
	return t == COLLECTED_COIN or t == COLLECTED_BLUECOIN


## Secret blocks (50 solid, 243 non-solid) revealed by touching them (World.overlaps -> lookup.setSecret).
func is_secret_revealed(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return false
	return _secrets[ty * width + tx] != 0


func get_tile(tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return 0
	return tiles[ty * width + tx]


## G key (PlayState.tick): toggles god mode and clears death.
func set_god_mode(on: bool) -> void:
	if on == in_god_mode:
		return
	in_god_mode = on
	is_dead = false
	sim_event.emit(&"god_mode", {"on": in_god_mode})


## Player.respawn(): back to the checkpoint (or spawn), speeds cleared.
func respawn() -> void:
	modifier_x = 0.0; modifier_y = 0.0
	speed_x = 0.0; speed_y = 0.0
	is_dead = false
	is_on_fire = false
	_tile_queue.clear()
	_place_at_spawn(true)
	teleported = true
	sim_event.emit(&"respawn", {"pos": Vector2(px, py)})


## Player.killPlayer()
func kill_player() -> void:
	if not in_god_mode and not is_dead:
		is_dead = true
		sim_event.emit(&"death", {"pos": Vector2(px, py)})


## Portal lookup for renderers: Vector3i(id, target, rotation) or null.
func get_portal(tx: int, ty: int) -> Variant:
	return _portals.get(ty * width + tx, null)


## Every piece of mutable simulation state (per-tick loop temporaries excluded).
const _SNAP_PROPS: Array[StringName] = [&"px", &"py", &"prev_px", &"prev_py", &"speed_x", &"speed_y",
	&"gravity_dir", &"on_ground", &"is_dead", &"in_god_mode", &"coins", &"blue_coins", &"has_crown",
	&"has_silver_crown", &"deaths", &"checkpoint", &"teleported", &"modifier_x", &"modifier_y",
	&"current_tile", &"flip_gravity", &"jump_count", &"max_jumps", &"jump_boost", &"speed_boost",
	&"low_gravity", &"is_invulnerable", &"is_on_fire", &"run_ticks", &"morx", &"mory", &"mox", &"moy",
	&"tiles", &"_lookup", &"_next_spawn", &"_secrets", &"_keys", &"_keys_timer", &"_offset",
	&"_timedoor_state", &"_hide_timedoor_offset", &"_show_coin_gate", &"_show_blue_coin_gate",
	&"_show_death_gate", &"_orange_switches", &"_switches", &"_collide_crown", &"_collide_silver_crown",
	&"_state_queue", &"_keys_queue", &"_tile_queue", &"_ticks", &"_queue", &"_last_jump", &"_slippery",
	&"_pastx", &"_pasty", &"_ox", &"_oy", &"overlapa", &"overlapb", &"overlapc", &"overlapd",
	&"_last_portal_set", &"_last_portal", &"_dead_offset", &"_fire_time_start", &"_fire_duration",
	&"_horizontal", &"_vertical", &"_spacedown", &"_spacejustdown", &"_prev_jump_held", &"_mx", &"_my",
	&"_current", &"_ev_keys", &"_ev_coins", &"_ev_bcoins", &"_ev_timedoor", &"_ev_grav"]


## Full state snapshot. restore() makes the sim continue bit-identically from that point, any
## number of times, in any order. Cheap: the big per-tile arrays are shared, which is safe because
## the sim never writes them in place (it swaps in a modified copy; see _set_tile).
func snapshot() -> Array:
	var s := []
	s.resize(_SNAP_PROPS.size() + 1)
	for i in _SNAP_PROPS.size():
		var v: Variant = get(_SNAP_PROPS[i])
		if v is Dictionary or v is Array:
			v = v.duplicate(true)
		s[i] = v
	s[_SNAP_PROPS.find(&"_queue")] = _queue.duplicate()   # mutated in place every tick
	s[_SNAP_PROPS.size()] = _rng.state
	return s


func restore(s: Array) -> void:
	for i in _SNAP_PROPS.size():
		var v: Variant = s[i]
		if v is Dictionary or v is Array:
			v = v.duplicate(true)
		set(_SNAP_PROPS[i], v)
	_queue = (s[_SNAP_PROPS.find(&"_queue")] as PackedInt32Array).duplicate()
	_rng.state = s[_SNAP_PROPS.size()]


## Hash of the whole simulation state (for determinism checks).
func state_hash() -> int:
	var h := 0
	for p in _SNAP_PROPS:
		var v: Variant = get(p)
		if v is Array and not v.is_empty() and v[0] is Callable:
			h = hash([h, v.size()])      # queued callables: compare count only
		else:
			h = hash([h, v])
	return hash([h, _rng.state])


# ================================================================ tick

## Exactly one original EE physics tick (10 ms): PlayState.tick() -> World.update() -> Player.tick(),
## then PlayState.enterFrame()'s queues and the death-animation respawn from Player.draw().
func tick(input: EEInput) -> void:
	prev_px = px
	prev_py = py
	teleported = false
	_ticks += 1
	# --- PlayState.tick()
	var old := _show_coin_gate
	_show_coin_gate = coins
	if _overlaps() != 0: _show_coin_gate = old
	old = _show_blue_coin_gate
	_show_blue_coin_gate = blue_coins
	if _overlaps() != 0: _show_blue_coin_gate = old
	old = _show_death_gate
	_show_death_gate = deaths
	if _overlaps() != 0: _show_death_gate = old
	if input.god_toggle:
		input.god_toggle = false
		in_god_mode = not in_god_mode
		is_dead = false
		sim_event.emit(&"god_mode", {"on": in_god_mode})
	# --- World.update()
	_offset += 0.3
	if ((_offset - _hide_timedoor_offset) / 30.0) >= 5.0:
		_hide_timedoor_offset = _offset
		_timedoor_state = not _timedoor_state
	for c: StringName in COLORS:
		if _keys[c] and ((_offset - float(_keys_timer[c])) / 30.0) >= 5.0:
			_switch_key(c, false)
	# --- Player.tick()
	_player_tick(input)
	# --- PlayState.enterFrame(): queue, then keysquene
	var n := _state_queue.size()
	while n > 0:
		n -= 1
		var f: Callable = _state_queue.pop_front()
		f.call()
	n = _keys_queue.size()
	while n > 0:
		n -= 1
		var k: Array = _keys_queue.pop_front()
		_switch_key(k[0], k[1], true)
	# --- Player.draw(): death animation finished -> respawn
	if is_dead and _dead_offset > 16.0:
		respawn()
		deaths += 1
	_emit_diffs()


func _player_tick(input: EEInput) -> void:
	var now := float(_now())
	var isgodmod := in_god_mode
	if is_dead:
		_dead_offset += 0.3
	else:
		_dead_offset = 0.0
	if not is_dead and is_on_fire:
		if _fire_duration != 0.0 and now - _fire_time_start > _fire_duration * 1000.0:
			kill_player()

	var cx: int = int(px + 8.0) >> 4
	var cy: int = int(py + 8.0) >> 4

	var delayed: int = _queue[0]
	_queue_shift()
	var current := get_tile(cx, cy)
	if _flag(current) & F_HALF != 0:
		var rot := _lookup[cy * width + cx] if _in_bounds(cx, cy) else 0
		if NONROT_HALF_IDS.has(current):
			rot = 1
		if rot == 1: cy -= 1
		if rot == 0: cx -= 1
		current = get_tile(cx, cy)
	_current_set(current)

	var current_below := _get_current_below(current, cx, cy)
	_queue_push(current)
	if current == 4 or current == 414 or _flag(current) & F_CLIMB != 0:
		delayed = _queue[0]
		_queue_shift()
		_queue_push(current)

	var ql := _tile_queue.size()
	while ql > 0:
		ql -= 1
		var f: Callable = _tile_queue.pop_front()
		f.call()

	# --- Me.getPlayerInput()
	_horizontal = (-1 if input.left else 0) + (1 if input.right else 0)
	_vertical = (-1 if input.up else 0) + (1 if input.down else 0)
	_spacedown = input.jump
	_spacejustdown = input.jump_pressed or (input.jump and not _prev_jump_held)
	_prev_jump_held = input.jump
	input.jump_pressed = false

	if is_dead:
		_spacejustdown = false
		_spacedown = false
		_horizontal = 0
		_vertical = 0

	var rotate_mo := true
	var rotate_mor := true
	morx = 0; mory = 0
	mox = 0.0; moy = 0.0
	var ig := int(GRAVITY)   # morx/mory are ints in AS3 (-_gravity -> -2)

	if not isgodmod:
		if _flag(current) & F_CLIMB != 0:
			morx = 0; mory = 0
		else:
			match current:
				1, 411:
					morx = -ig; mory = 0; rotate_mor = false
				2, 412:
					morx = 0; mory = -ig; rotate_mor = false
				3, 413:
					morx = ig; mory = 0; rotate_mor = false
				1518, 1519:
					morx = 0; mory = ig; rotate_mor = false
				SPEED_LEFT, SPEED_RIGHT, SPEED_UP, SPEED_DOWN, 4, 414:
					morx = 0; mory = 0
				WATER:
					morx = 0; mory = int(WATER_BUOYANCY)
				MUD:
					morx = 0; mory = int(MUD_BUOYANCY)
				LAVA:
					morx = 0; mory = int(LAVA_BUOYANCY)
				TOXIC_WASTE:
					morx = 0; mory = int(TOXIC_BUOYANCY)
					if not is_dead and not is_invulnerable:
						kill_player()
				_:
					morx = 0; mory = ig
					if current == FIRE or SPIKE_IDS.has(current):
						if not is_dead and not is_invulnerable:
							kill_player()

		if _flag(delayed) & F_CLIMB != 0:
			mox = 0.0; moy = 0.0
		else:
			match delayed:
				1, 411:
					mox = -GRAVITY; moy = 0.0; rotate_mo = false
				2, 412:
					mox = 0.0; moy = -GRAVITY; rotate_mo = false
				3, 413:
					mox = GRAVITY; moy = 0.0; rotate_mo = false
				1518, 1519:
					mox = 0.0; moy = GRAVITY; rotate_mo = false
				SPEED_LEFT, SPEED_RIGHT, SPEED_UP, SPEED_DOWN, 4, 414:
					mox = 0.0; moy = 0.0
				WATER:
					mox = 0.0; moy = WATER_BUOYANCY
				MUD:
					mox = 0.0; moy = MUD_BUOYANCY
				LAVA:
					mox = 0.0; moy = LAVA_BUOYANCY
				TOXIC_WASTE:
					mox = 0.0; moy = TOXIC_BUOYANCY
				_:
					mox = 0.0; moy = GRAVITY

	var temp: float
	var itemp: int
	match flip_gravity:
		1:
			if rotate_mo:
				temp = mox; mox = -moy; moy = temp
			if rotate_mor:
				itemp = morx; morx = -mory; mory = itemp
		2:
			if rotate_mo:
				mox = -mox; moy = -moy
			if rotate_mor:
				morx = -morx; mory = -mory
		3:
			if rotate_mo:
				temp = mox; mox = moy; moy = -temp
			if rotate_mor:
				itemp = morx; morx = mory; mory = -itemp
		4:
			if rotate_mo:
				mox = 0.0; moy = 0.0
			if rotate_mor:
				morx = 0; mory = 0

	if _flag(delayed) & F_LIQUID != 0:
		_mx = _horizontal; _my = _vertical
	elif moy != 0.0:
		_mx = _horizontal; _my = 0.0
	elif mox != 0.0:
		_mx = 0.0; _my = _vertical
	else:
		_mx = _horizontal; _my = _vertical

	var sm := _speed_multiplier()
	_mx *= sm
	_my *= sm
	var gm := _gravity_multiplier()
	mox *= gm
	moy *= gm

	modifier_x = (mox + _mx) / MULT
	modifier_y = (moy + _my) / MULT

	var climb_cur := _flag(current) & F_CLIMB != 0
	if current_below == ICE and not climb_cur and current != 4 and current != 414:
		_slippery = 2.0
	elif _flag(current_below) & F_SOLID != 0:
		_slippery = 0.0
	elif _slippery > 0.0:
		_slippery -= 0.2

	var mx := _mx
	var my := _my
	if speed_x != 0.0 or modifier_x != 0.0:
		speed_x += modifier_x
		if ((((mx == 0.0 and moy != 0.0) or (speed_x < 0.0 and mx > 0.0) or (speed_x > 0.0 and mx < 0.0)) and (_slippery <= 0.0 or isgodmod)) or (climb_cur and not isgodmod)):
			speed_x *= BASE_DRAG
			speed_x *= NO_MOD_DRAG
		elif current == WATER and not isgodmod:
			speed_x *= BASE_DRAG; speed_x *= WATER_DRAG
		elif current == MUD and not isgodmod:
			speed_x *= BASE_DRAG; speed_x *= MUD_DRAG
		elif current == LAVA and not isgodmod:
			speed_x *= BASE_DRAG; speed_x *= LAVA_DRAG
		elif current == TOXIC_WASTE and not isgodmod:
			speed_x *= BASE_DRAG; speed_x *= TOXIC_DRAG
		elif _slippery > 0.0 and not isgodmod:
			if mx != 0.0 and not ((speed_x < 0.0 and mx > 0.0) or (speed_x > 0.0 and mx < 0.0)):
				speed_x *= BASE_DRAG
			else:
				speed_x *= ICE_NO_MOD_DRAG
			if (speed_x < 0.0 and mx > 0.0) or (speed_x > 0.0 and mx < 0.0):
				speed_x *= ICE_DRAG
		else:
			speed_x *= BASE_DRAG
		if speed_x > 16.0:
			speed_x = 16.0
		elif speed_x < -16.0:
			speed_x = -16.0
		elif speed_x < 0.0001 and speed_x > -0.0001:
			speed_x = 0.0

	if speed_y != 0.0 or modifier_y != 0.0:
		speed_y += modifier_y
		if ((((my == 0.0 and mox != 0.0) or (speed_y < 0.0 and my > 0.0) or (speed_y > 0.0 and my < 0.0)) and (_slippery <= 0.0 or isgodmod)) or (climb_cur and not isgodmod)):
			speed_y *= BASE_DRAG
			speed_y *= NO_MOD_DRAG
		elif current == WATER and not isgodmod:
			speed_y *= BASE_DRAG; speed_y *= WATER_DRAG
		elif current == MUD and not isgodmod:
			speed_y *= BASE_DRAG; speed_y *= MUD_DRAG
		elif current == LAVA and not isgodmod:
			speed_y *= BASE_DRAG; speed_y *= LAVA_DRAG
		elif current == TOXIC_WASTE and not isgodmod:
			speed_y *= BASE_DRAG; speed_y *= TOXIC_DRAG
		elif _slippery > 0.0 and not isgodmod:
			if my != 0.0 and not ((speed_y < 0.0 and my > 0.0) or (speed_y > 0.0 and my < 0.0)):
				speed_y *= BASE_DRAG
			else:
				speed_y *= ICE_NO_MOD_DRAG
			if (speed_y < 0.0 and my > 0.0) or (speed_y > 0.0 and my < 0.0):
				speed_y *= ICE_DRAG
		else:
			speed_y *= BASE_DRAG
		if speed_y > 16.0:
			speed_y = 16.0
		elif speed_y < -16.0:
			speed_y = -16.0
		elif speed_y < 0.0001 and speed_y > -0.0001:
			speed_y = 0.0

	if not isgodmod:
		match current:
			SPEED_LEFT: speed_x = -BOOST
			SPEED_RIGHT: speed_x = BOOST
			SPEED_UP: speed_y = -BOOST
			SPEED_DOWN: speed_y = BOOST
		if is_dead:
			speed_x = 0.0
			speed_y = 0.0

	# --- sub-stepped movement (stepx/stepy + processPortals)
	_rem_x = fmod(px, 1.0)
	_cur_sx = speed_x
	_rem_y = fmod(py, 1.0)
	_cur_sy = speed_y
	_donex = false
	_doney = false
	_grounded = false
	_land_speed = 0.0
	_osx = 0.0
	_osy = 0.0

	while (_cur_sx != 0.0 and not _donex) or (_cur_sy != 0.0 and not _doney):
		_process_portals(cx, cy, isgodmod)
		_ox = px
		_oy = py
		_osx = _cur_sx
		_osy = _cur_sy
		_stepx()
		_stepy()

	# --- jumping, touching blocks
	if not is_dead:
		var mod := 1.0
		var injump := false
		if _spacejustdown:
			_last_jump = -now
			injump = true
			mod = -1.0
		if _spacedown:
			if _last_jump < 0.0:
				if now + _last_jump > 750.0:
					injump = true
			else:
				if now - _last_jump > 150.0:
					injump = true
		if (((speed_x == 0.0 and morx != 0 and mox != 0.0) or (speed_y == 0.0 and mory != 0 and moy != 0.0)) and _grounded) or _current == EFFECT_MULTIJUMP:
			jump_count = 0
		if jump_count == 0 and not _grounded:
			jump_count = 1
		if injump:
			var jumped := false
			if jump_count < max_jumps and morx != 0 and mox != 0.0:
				if max_jumps < 1000:
					jump_count += 1
				speed_x = (float(-morx) * JUMP_HEIGHT * _jump_multiplier()) / MULT
				_last_jump = now * mod
				jumped = true
			if jump_count < max_jumps and mory != 0 and moy != 0.0:
				if max_jumps < 1000:
					jump_count += 1
				speed_y = (float(-mory) * JUMP_HEIGHT * _jump_multiplier()) / MULT
				_last_jump = now * mod
				jumped = true
			if jumped:
				sim_event.emit(&"jump", {"pos": Vector2(px, py)})
		_touch_block(cx, cy, isgodmod)

	# --- auto align to grid (not in liquids)
	if int(speed_x) != 0 or (_flag(_current) & F_LIQUID != 0 and not isgodmod):
		pass
	elif modifier_x < 0.1 and modifier_x > -0.1:
		var tx := fmod(px, 16.0)
		if tx < 2.0:
			if tx < 0.2:
				px = float(int(px))
			else:
				px -= tx / 15.0
		elif tx > 14.0:
			if tx > 15.8:
				px = float(int(px))
				px += 1.0
			else:
				px += (tx - 14.0) / 15.0
	if int(speed_y) != 0 or (_flag(_current) & F_LIQUID != 0 and not isgodmod):
		pass
	elif modifier_y < 0.1 and modifier_y > -0.1:
		var ty := fmod(py, 16.0)
		if ty < 2.0:
			if ty < 0.2:
				py = float(int(py))
			else:
				py -= ty / 15.0
		elif ty > 14.0:
			if ty > 15.8:
				py = float(int(py))
				py += 1.0
			else:
				py += (ty - 14.0) / 15.0

	# --- Me.updateStuff()
	if not has_silver_crown and (run_ticks != 0 or _horizontal != 0 or _vertical != 0 or _spacedown):
		run_ticks += 1

	var was_ground := on_ground
	on_ground = _grounded
	if _grounded and not was_ground:
		sim_event.emit(&"land", {"impact_speed": _land_speed})


var _current := 0
func _current_set(v: int) -> void:
	_current = v
	current_tile = v


func _stepx() -> void:
	if _cur_sx > 0.0:
		if _cur_sx + _rem_x >= 1.0:
			px += (1.0 - _rem_x)
			px = float(int(px))
			_cur_sx -= (1.0 - _rem_x)
			_rem_x = 0.0
		else:
			px += _cur_sx
			_cur_sx = 0.0
	elif _cur_sx < 0.0:
		if _rem_x + _cur_sx < 0.0 and (_rem_x != 0.0 or _flag(_current) & F_BOOST != 0):
			_cur_sx += _rem_x
			px -= _rem_x
			px = float(int(px))
			_rem_x = 1.0
		else:
			px += _cur_sx
			_cur_sx = 0.0
	if _overlaps() != 0:
		px = _ox
		if speed_x > 0.0 and morx > 0:
			_mark_grounded(speed_x)
		if speed_x < 0.0 and morx < 0:
			_mark_grounded(speed_x)
		speed_x = 0.0
		_cur_sx = _osx
		_donex = true


func _stepy() -> void:
	if _cur_sy > 0.0:
		if _cur_sy + _rem_y >= 1.0:
			py += 1.0 - _rem_y
			py = float(int(py))
			_cur_sy -= (1.0 - _rem_y)
			_rem_y = 0.0
		else:
			py += _cur_sy
			_cur_sy = 0.0
	elif _cur_sy < 0.0:
		if _rem_y + _cur_sy < 0.0 and (_rem_y != 0.0 or _flag(_current) & F_BOOST != 0):
			py -= _rem_y
			py = float(int(py))
			_cur_sy += _rem_y
			_rem_y = 1.0
		else:
			py += _cur_sy
			_cur_sy = 0.0
	if _overlaps() != 0:
		py = _oy
		if speed_y > 0.0 and mory > 0:
			_mark_grounded(speed_y)
		if speed_y < 0.0 and mory < 0:
			_mark_grounded(speed_y)
		speed_y = 0.0
		_cur_sy = _osy
		_doney = true


func _mark_grounded(s: float) -> void:
	if not _grounded:
		_land_speed = absf(s)
	_grounded = true


func _process_portals(cx: int, cy: int, isgodmod: bool) -> void:
	_current_set(get_tile(cx, cy))
	# (world portals 374 need a key press + another world: not applicable offline)
	var p: Variant = null
	if _current == PORTAL or _current == PORTAL_INVISIBLE:
		p = _portals.get(cy * width + cx, Vector3i.ZERO)
	if isgodmod or p == null or (p as Vector3i).y == (p as Vector3i).x:
		_last_portal_set = false
		return
	if _last_portal_set:
		return
	_last_portal_set = true
	_last_portal = Vector2i(cx << 4, cy << 4)
	var targets: Array = _portals_by_id.get((p as Vector3i).y, [])
	if targets.size() <= 0:
		return
	var cp: Vector2i = targets[_rng.randi_range(0, targets.size() - 1)]
	var old_rot: int = (p as Vector3i).z
	var np: Vector3i = _portals.get((cp.y >> 4) * width + (cp.x >> 4), Vector3i.ZERO)
	var new_rot: int = np.z
	if old_rot < new_rot:
		old_rot += 4
	var osx := speed_x * MULT
	var osy := speed_y * MULT
	var omx := modifier_x * MULT
	var omy := modifier_y * MULT
	var dir := old_rot - new_rot
	var magic := 1.42
	match dir:
		1:
			speed_x = (osy * magic) / MULT
			speed_y = (-osx * magic) / MULT
			modifier_x = (omy * magic) / MULT
			modifier_y = (-omx * magic) / MULT
			_rem_y = -_rem_x
			_cur_sy = -_cur_sx
		2:
			speed_x = (-osx * magic) / MULT
			speed_y = (-osy * magic) / MULT
			modifier_x = (-omx * magic) / MULT
			modifier_y = (-omy * magic) / MULT
			_rem_y = -_rem_y
			_cur_sy = -_cur_sy
			_rem_x = -_rem_x
			_cur_sx = -_cur_sx
		3:
			speed_x = (-osy * magic) / MULT
			speed_y = (osx * magic) / MULT
			modifier_x = (-omy * magic) / MULT
			modifier_y = (omx * magic) / MULT
			_rem_x = -_rem_y
			_cur_sx = -_cur_sy
	px = float(cp.x)
	py = float(cp.y)
	_last_portal = cp
	teleported = true
	sim_event.emit(&"portal", {"from": Vector2i(cx, cy), "to": Vector2i(cp.x >> 4, cp.y >> 4)})


func _get_current_below(current: int, cx: int, cy: int) -> int:
	var x := 0
	var y := 0
	match current:
		1, 411: x -= 1
		2, 412: y -= 1
		3: x += 1
		4: y += 1
		_:
			match flip_gravity:
				0: y += 1
				1: x -= 1
				2: y -= 1
				_: x += 1
	return get_tile(cx + x, cy + y)


# ================================================================ World.overlaps()

## Returns the id of the first blocking tile (1 when out of bounds), 0 when free.
## Has EE's side effects: one-way overlap bookkeeping and secret reveals.
func _overlaps() -> int:
	var x := px
	var y := py
	if x < 0.0 or y < 0.0 or x > float(width * 16 - 16) or y > float(height * 16 - 16):
		return 1
	if in_god_mode:
		return 0
	var ox: int = int(x) >> 4
	var oy: int = int(y) >> 4
	var oh := (x + 16.0) / 16.0
	var ow := (y + 16.0) / 16.0
	var cx_end := int(ceil(oh))    # cx < oh
	var cy_end := int(ceil(ow))    # cy < ow
	var skipa := false
	var skipb := false
	var skipc := false
	var skipd := false
	for cy in range(oy, cy_end):
		var row := cy * width
		for cx in range(ox, cx_end):
			var val := tiles[row + cx]
			var fl := _flag(val)
			if fl & F_SOLID == 0:
				if val == 243:
					_reveal_secret(cx, cy)
				continue
			var tlx := float(cx * 16)
			var tly := float(cy * 16)
			if not (x < tlx + 16.0 and tlx < x + 16.0 and y < tly + 16.0 and tly < y + 16.0):
				continue
			if fl & (F_ROTHALF | F_HALF | F_JUMPTHRU) != 0:
				var rot := _lookup[row + cx]
				if fl & F_ROTHALF != 0:
					if fl & F_JUMPTHRU != 0:
						# up
						if (speed_y < 0.0 or cy <= overlapa or (speed_y == 0.0 and speed_x == 0.0 and (_oy + 15.0) > tly)) and rot == 1:
							if cy != oy or overlapa == -1: overlapa = cy
							skipa = true
							continue
						# right
						if (speed_x > 0.0 or (cx <= overlapb and speed_x <= 0.0 and _ox < tlx + 16.0)) and rot == 2:
							if cx != ox or overlapb == -1: overlapb = cx
							skipb = true
							continue
						# down
						if (speed_y > 0.0 or (cy <= overlapc and speed_y <= 0.0 and _oy < tly + 16.0)) and rot == 3:
							if cy != oy or overlapc == -1: overlapc = cy
							skipc = true
							continue
						# left
						if (speed_x < 0.0 or cx <= overlapd or (speed_y == 0.0 and speed_x < 0.0 and (_ox - 15.0) < tlx)) and rot == 0:
							if cx != ox or overlapd == -1: overlapd = cx
							skipd = true
							continue
				elif fl & F_HALF != 0:
					if rot == 1:
						if not _rect_hit(x, y, tlx, tly + 8.0, 16.0, 8.0): continue
					elif rot == 2:
						if not _rect_hit(x, y, tlx, tly, 8.0, 16.0): continue
					elif rot == 3:
						if not _rect_hit(x, y, tlx, tly, 16.0, 8.0): continue
					elif rot == 0:
						if not _rect_hit(x, y, tlx + 8.0, tly, 8.0, 16.0): continue
				else:
					# plain one-way (canJumpThroughFromBelow)
					if speed_y < 0.0 or cy <= overlapa or (speed_y == 0.0 and speed_x == 0.0 and (_oy + 15.0) > tly):
						if cy != oy or overlapa == -1: overlapa = cy
						skipa = true
						continue
			if fl & F_DOOR != 0:
				if val == 50:
					_reveal_secret(cx, cy)
				elif _door_passable(val, cx, cy):
					continue
			return val
	if not skipa: overlapa = -1
	if not skipb: overlapb = -1
	if not skipc: overlapc = -1
	if not skipd: overlapd = -1
	return 0


static func _rect_hit(x: float, y: float, rx: float, ry: float, rw: float, rh: float) -> bool:
	return x < rx + rw and rx < x + 16.0 and y < ry + rh and ry < y + 16.0


## The door/gate switch of World.overlaps(): true = the tile does NOT block (continue).
func _door_passable(val: int, cx: int, cy: int) -> bool:
	match val:
		23: return _keys[&"red"]
		24: return _keys[&"green"]
		25: return _keys[&"blue"]
		26: return not _keys[&"red"]
		27: return not _keys[&"green"]
		28: return not _keys[&"blue"]
		1005: return _keys[&"cyan"]
		1006: return _keys[&"magenta"]
		1007: return _keys[&"yellow"]
		1008: return not _keys[&"cyan"]
		1009: return not _keys[&"magenta"]
		1010: return not _keys[&"yellow"]
		156: return _timedoor_state
		157: return not _timedoor_state
		DOOR_PURPLE: return _switches.get(_lookup[cy * width + cx], false)
		GATE_PURPLE: return not _switches.get(_lookup[cy * width + cx], false)
		DOOR_ORANGE: return _orange_switches.get(_lookup[cy * width + cx], false)
		GATE_ORANGE: return not _orange_switches.get(_lookup[cy * width + cx], false)
		200: return false     # gold door: wearsGoldSmiley is false
		201: return true      # gold gate
		1094: return _collide_crown
		1095: return not _collide_crown
		1152: return _collide_silver_crown
		1153: return not _collide_silver_crown
		COINDOOR: return _lookup[cy * width + cx] <= coins
		BLUECOINDOOR: return _lookup[cy * width + cx] <= blue_coins
		DEATH_DOOR: return _lookup[cy * width + cx] <= deaths
		COINGATE: return _lookup[cy * width + cx] > _show_coin_gate
		BLUECOINGATE: return _lookup[cy * width + cx] > _show_blue_coin_gate
		DEATH_GATE: return _lookup[cy * width + cx] > _show_death_gate
		1027: return 0 == _lookup[cy * width + cx]   # team door (team is always 0 here)
		1028: return 0 != _lookup[cy * width + cx]
		206: return false     # zombie gate (never a zombie)
		207: return true      # zombie door
	return false


func _reveal_secret(cx: int, cy: int) -> void:
	var i := cy * width + cx
	if _secrets[i] == 0:
		_secrets = _secrets.duplicate()   # copy-on-write (see _set_tile)
		_secrets[i] = 1
		sim_event.emit(&"secret", {"tile": Vector2i(cx, cy)})


# ================================================================ Me.touchBlock()

func _touch_block(cx: int, cy: int, isgodmode: bool) -> void:
	var current := _current
	match current:
		COIN_GOLD, COIN_BLUE:
			_set_tile(cx, cy, current + 10)
			if current == COIN_GOLD:
				coins += 1
				sim_event.emit(&"coin", {"tile": Vector2i(cx, cy)})
			else:
				blue_coins += 1
				sim_event.emit(&"blue_coin", {"tile": Vector2i(cx, cy)})
		# RESET_POINT (466) needs the "risky" key: not reachable here.

	if _pastx != cx or _pasty != cy:
		if not isgodmode:
			match current:
				CROWN:
					if not has_crown:
						_remove_crown()
						has_crown = true
						_check_crown(true)
						sim_event.emit(&"crown", {"tile": Vector2i(cx, cy)})
				SWITCH_PURPLE:
					var sid := _lookup_at(cx, cy)
					_press_purple_switch(sid, not _switches.get(sid, false))
				SWITCH_ORANGE:
					var osid := _lookup_at(cx, cy)
					_press_orange_switch(osid, not _orange_switches.get(osid, false))
				RESET_PURPLE:
					var rsid := _lookup_at(cx, cy)
					if rsid == 1000 or _switches.get(rsid, false):
						_press_purple_switch(rsid, false)
				RESET_ORANGE:
					var rosid := _lookup_at(cx, cy)
					if rosid == 1000 or _orange_switches.get(rosid, false):
						_press_orange_switch(rosid, false)
				CHECKPOINT:
					checkpoint = Vector2i(cx, cy)
					sim_event.emit(&"checkpoint", {"tile": checkpoint})
				BRICK_COMPLETE:
					if not has_silver_crown:
						has_silver_crown = true
						_check_silver_crown(true)
						sim_event.emit(&"complete", {"tile": Vector2i(cx, cy), "ticks": run_ticks})
				6, 7, 8, 408, 409, 410:
					var col: StringName = KEY_COLORS[current]
					_switch_key(col, true)
					sim_event.emit(&"key", {"color": col, "tile": Vector2i(cx, cy)})
				EFFECT_JUMP:
					var nj := _lookup_at(cx, cy)
					if jump_boost != nj:
						jump_boost = nj
				EFFECT_RUN:
					var ns := _lookup_at(cx, cy)
					if speed_boost != ns:
						speed_boost = ns
				EFFECT_LOW_GRAVITY:
					low_gravity = _lookup_at(cx, cy) != 0
				EFFECT_PROTECTION:
					var inv := _lookup_at(cx, cy) != 0
					if is_invulnerable != inv:
						is_invulnerable = inv
						if inv:
							is_on_fire = false
				EFFECT_RESET:
					jump_boost = 0; speed_boost = 0; is_invulnerable = false; low_gravity = false
					max_jumps = 1; flip_gravity = 0
				LAVA:
					if not is_on_fire and not is_invulnerable:
						is_on_fire = true
						# setEffect(effectFire, true, 2, 2) with +2*ping on arg and duration
						var arg := 2.0 + 2.0 * PING
						var dur := 2.0 + 2.0 * PING
						_fire_time_start = float(_now()) - (dur - arg) * 1000.0
						_fire_duration = dur
				WATER, MUD, TOXIC_WASTE:
					is_on_fire = false
				EFFECT_MULTIJUMP:
					var jps := _lookup_at(cx, cy)
					if jps != max_jumps:
						max_jumps = jps
				EFFECT_GRAVITY:
					var nf := _lookup_at(cx, cy)
					if flip_gravity != nf:
						flip_gravity = nf
		_pastx = cx
		_pasty = cy


func _set_tile(cx: int, cy: int, id: int) -> void:
	# Packed arrays are shared by reference in Godot 4: never write in place, so snapshots that
	# still reference the old array stay valid (writes are rare: coin pickups only).
	var i := cy * width + cx
	tiles = tiles.duplicate()
	tiles[i] = id
	_lookup = _lookup.duplicate()
	_lookup[i] = 0          # setTileComplex -> lookup.deleteLookup


func _lookup_at(cx: int, cy: int) -> int:
	return _lookup[cy * width + cx] if _in_bounds(cx, cy) else 0


# ================================================================ PlayState / World key & state helpers

## PlayState.switchKey()
func _switch_key(color: StringName, state: bool, fromqueue := false) -> void:
	_set_key(color, state, fromqueue)
	if _overlaps() != 0:
		_set_key(color, not state)
		_keys_queue.append([color, state])


## World.setKey()
func _set_key(color: StringName, state: bool, fromqueue := false) -> void:
	if fromqueue and ((_offset - float(_keys_timer[color])) / 30.0) >= 5.0:
		return
	_keys[color] = state
	if state and not fromqueue:
		_keys_timer[color] = _offset


func _check_crown(collide: bool) -> void:
	_collide_crown = collide
	if _overlaps() != 0:
		_collide_crown = not collide
		_state_queue.append(_check_crown.bind(collide))


func _remove_crown() -> void:
	has_crown = false
	_check_crown(false)


func _check_silver_crown(collide: bool) -> void:
	_collide_silver_crown = collide
	if _overlaps() != 0:
		_collide_silver_crown = not collide
		_state_queue.append(_check_silver_crown.bind(collide))


func _press_purple_switch(sid: int, enabled: bool) -> void:
	if sid == 1000:
		for i in 1000:
			_press_purple_switch(i, enabled)
	_switches[sid] = enabled
	if _overlaps() != 0:
		_switches[sid] = not enabled
		_tile_queue.append(_press_purple_switch.bind(sid, enabled))


func _press_orange_switch(sid: int, enabled: bool) -> void:
	if sid == 1000:
		for i in 1000:
			_press_orange_switch(i, enabled)
	_orange_switches[sid] = enabled
	if _overlaps() != 0:
		_orange_switches[sid] = not enabled
		_state_queue.append(_press_orange_switch.bind(sid, enabled))


## Player.placeAtSpawn()
func _place_at_spawn(use_checkpoint: bool) -> void:
	var nx := 1
	var ny := 1
	if use_checkpoint and checkpoint.x != -1:
		nx = checkpoint.x
		ny = checkpoint.y
	elif _spawns.size() > 0:
		if _next_spawn >= _spawns.size():
			_next_spawn = 0
		nx = _spawns[_next_spawn].x
		ny = _spawns[_next_spawn].y
		_next_spawn += 1
	px = float(nx * 16)
	py = float(ny * 16)


# ================================================================ multipliers

func _jump_multiplier() -> float:
	var jm := 1.0
	if jump_boost == 1: jm *= 1.3
	if jump_boost == 2: jm *= 0.75
	if _slippery > 0.0: jm *= 0.88
	return jm


func _speed_multiplier() -> float:
	var s := 1.0
	if speed_boost == 1: s *= 1.5
	if speed_boost == 2: s *= 0.6
	return s


func _gravity_multiplier() -> float:
	var g := 1.0
	if low_gravity: g *= 0.15
	g *= world_gravity_multiplier
	return g


# ================================================================ utilities

func _now() -> int:
	return CLOCK_BASE + _ticks * MS_PER_TICK


func _in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < width and cy < height


func _queue_shift() -> void:
	# Vector.shift(): drop the first element
	_queue.remove_at(0)


func _queue_push(v: int) -> void:
	_queue.append(v)


func _flag(id: int) -> int:
	if id < 0 or id >= _flags.size():
		return 0
	return _flags[id]


func _build_flags() -> void:
	var n := 4096
	for v in level.fg:
		n = maxi(n, v + 1)
	_flags = PackedByteArray(); _flags.resize(n)
	for id in n:
		var f := 0
		var climb := CLIMBABLE_IDS.has(id)
		# ItemId.isSolid
		if not climb and ((9 <= id and id <= 97) or (122 <= id and id <= 217) or (id >= 1001 and id <= 1499)) and id != 83 and id != 77:
			f |= F_SOLID
		if climb: f |= F_CLIMB
		if JUMP_THROUGH_IDS.has(id): f |= F_JUMPTHRU
		if ROT_HALF_IDS.has(id): f |= F_ROTHALF
		if HALF_IDS.has(id): f |= F_HALF
		if DOOR_IDS.has(id): f |= F_DOOR
		if id == WATER or id == MUD or id == LAVA or id == TOXIC_WASTE: f |= F_LIQUID
		if id >= SPEED_LEFT and id <= SPEED_DOWN: f |= F_BOOST
		_flags[id] = f


func _emit_diffs() -> void:
	for c: StringName in COLORS:
		var now_on: bool = _keys[c]
		if now_on != _ev_keys[c]:
			_ev_keys[c] = now_on
			sim_event.emit(&"door_state", {"kind": c, "open": now_on})
			if not now_on:
				sim_event.emit(&"key_expired", {"color": c})
	if coins != _ev_coins:
		for t in _coin_door_thresholds:
			if (t <= coins) != (t <= _ev_coins):
				sim_event.emit(&"door_state", {"kind": &"coin", "open": t <= coins, "count": t})
		_ev_coins = coins
	if blue_coins != _ev_bcoins:
		for t in _blue_coin_door_thresholds:
			if (t <= blue_coins) != (t <= _ev_bcoins):
				sim_event.emit(&"door_state", {"kind": &"blue_coin", "open": t <= blue_coins, "count": t})
		_ev_bcoins = blue_coins
	if _timedoor_state != _ev_timedoor:
		_ev_timedoor = _timedoor_state
		if _has_time_doors:
			sim_event.emit(&"door_state", {"kind": &"time", "open": _timedoor_state})
	var g := Vector2i(int(signf(mox)), int(signf(moy)))
	if not in_god_mode and g != gravity_dir:
		gravity_dir = g
	if gravity_dir != _ev_grav:
		_ev_grav = gravity_dir
		sim_event.emit(&"gravity_changed", {"dir": gravity_dir})
