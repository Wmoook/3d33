class_name CameraRig
extends Node3D
## Perspective gameplay camera. Orbits a focus point on the gameplay plane (z = 0):
## - critically damped follow with velocity look-ahead and slight vertical framing
## - gentle 3D parallax tilt toward the direction of motion (+ a constant slight downward pitch)
## - trauma-based shake (landings, deaths), zoom = tiles visible horizontally, clamped to level bounds
## - cinematic mode: slow Catmull-Rom flyover through keyframes (title screen)

enum Mode { FOLLOW, CINEMATIC }

signal cinematic_cut   # the flyover jumped (portal cut); the shell dips to black

const FOV_V := 34.0                  # default vertical fov (degrees); moderate perspective = readable parallax
## Dynamic horizon camera (day levels, "Cinematic camera" setting): the EE-exact follow of the focus point is
## unchanged; the camera only ROTATES about that pivot by a slow, altitude-dependent pitch: high in the sky it
## looks down (tops of land receding, cloud sea below), near the bottom it looks up, ~0 around the horizon line.
## No velocity dependence; heavily smoothed (time constant HORIZON_TAU).
const HORIZON_DOWN_DEG := 7.0
const HORIZON_UP_DEG := 4.5
const HORIZON_TAU := 2.5
var fov_v := FOV_V
var horizon_pitch_on := false
var horizon_y := -100.0              # world y of the "eye level" line (pitch 0)
var horizon_top := 0.0               # world y where the full look-down is reached
var horizon_bottom := -200.0         # world y where the full look-up is reached
var _alt_pitch := 0.0
const BASE_PITCH := 0.0              # straight-on view like EE (was -5: looked down on the diorama)
const MAX_YAW := 3.2                 # degrees of parallax tilt at full look-ahead
const MAX_PITCH_TILT := 2.0
const LOOK_AHEAD_TIME := 0.22        # seconds of velocity projected ahead
const LOOK_AHEAD_MAX := Vector2(4.5, 3.0)
const FRAME_UP := 0.9                # player sits slightly "below" center (relative to gravity)
const FALL_LOOK_START := 9.0         # tiles/s along gravity before the extra fall look-ahead kicks in
const FALL_LOOK_GAIN := 0.3          # extra tiles of look-ahead per tile/s above the start speed
const FALL_LOOK_MAX := 6.0
const GRAV_SMOOTH := 1.6             # rate (1/s) at which gravity-relative framing follows gravity changes
const ZOOM_MIN := 20.0
const ZOOM_MAX := 60.0

var cam: Camera3D
var mode := Mode.FOLLOW
var level_size := Vector2(400, 200)  # tiles
var zoom := 30.0                     # current visible width (tiles)
var target_zoom := 30.0
var follow_smooth := 0.14            # seconds (critically damped)
var focus := Vector3.ZERO            # smoothed pivot on z = 0
var trauma := 0.0

var _focus_vel := Vector3.ZERO
var _look := Vector2.ZERO
var _tilt := Vector2.ZERO
var _grav := Vector2(0, -1)          # smoothed gravity direction (world axes, y up)
var _fall_look := Vector2.ZERO
var _lag_comp := Vector2.ZERO
var _smooth_boost := 0.0             # extra smoothing during intro swoop (decays)
## Cinematic override while following (e.g. FV victory: frame the Summit Shrine's light pillar).
var override_on := false
var override_target := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _t := 0.0
var _cine_keys: Array = []           # [{pos: Vector2 (tile space, y down), zoom: float}]
var _cine_s := 0.0
var _cine_last_i := -1

func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov_v
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.3
	cam.far = 900.0
	cam.current = true
	add_child(cam)
	_noise.seed = 7
	_noise.frequency = 1.6
	_noise.fractal_octaves = 2
	_apply_transform(Vector2.ZERO)

func distance_for_zoom(z: float) -> float:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var aspect := vp.x / maxf(vp.y, 1.0)
	var tan_h := tan(deg_to_rad(fov_v) * 0.5) * aspect
	return (z * 0.5) / tan_h

## Half extents of the visible region at z = 0 (tiles).
func half_extents() -> Vector2:
	var d := distance_for_zoom(zoom)
	var tv := tan(deg_to_rad(fov_v) * 0.5)
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	return Vector2(d * tv * vp.x / maxf(vp.y, 1.0), d * tv)

func add_zoom_steps(steps: float) -> void:
	target_zoom = clampf(target_zoom * pow(1.12, steps), ZOOM_MIN, ZOOM_MAX)

func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)

func snap_to(world_pos: Vector3) -> void:
	focus = Vector3(world_pos.x - 0.5, world_pos.y + 0.5, 0.0)  # EE target: player top-left, no clamp
	_focus_vel = Vector3.ZERO
	_look = Vector2.ZERO
	_fall_look = Vector2.ZERO
	_lag_comp = Vector2.ZERO

## Switch to follow mode; with swoop=true the camera glides from wherever it is (title -> gameplay).
func begin_follow(swoop: bool) -> void:
	mode = Mode.FOLLOW
	_smooth_boost = 1.1 if swoop else 0.0

## EE-exact follow (BlContainer.tick): every 100 Hz physics tick the camera moves 1/16 of the way toward the
## player's top-left corner (EE centres Player.x/.y, the box's top-left) and snaps once within 0.5 px.
## No look-ahead, tilt, fall lead, shake or level clamping, exactly like the original.
## world_pos: interpolated player center; vel/gravity kept for API compatibility (unused).
const EE_CAMERA_LAG := 1.0 / 16.0
const EE_SNAP := 0.5 / 16.0          # 0.5 px in tiles
var _ee_accum := 0.0
func follow(world_pos: Vector3, vel: Vector2, delta: float, gravity: Vector2 = Vector2(0, -1)) -> void:
	_t += delta
	zoom = _damp(zoom, target_zoom, 7.0, delta)
	var target := Vector3(world_pos.x - 0.5, world_pos.y + 0.5, 0.0)
	if override_on:
		# cinematic ease toward a framed shot (victory), outside the EE follow
		focus = _smooth_damp(focus, override_target, 0.9, delta)
	elif _smooth_boost > 0.0:
		# title -> gameplay swoop: glide in, then hand over to the EE follow
		_smooth_boost = maxf(0.0, _smooth_boost - delta * 0.45)
		focus = _smooth_damp(focus, target, 0.14 + _smooth_boost * _smooth_boost * 1.1, delta)
	else:
		_ee_accum += delta * 100.0
		var steps := int(_ee_accum)
		_ee_accum -= steps
		for i in mini(steps, 60):
			focus.x -= (focus.x - target.x) * EE_CAMERA_LAG
			focus.y -= (focus.y - target.y) * EE_CAMERA_LAG
			if absf(focus.x - target.x) < EE_SNAP: focus.x = target.x
			if absf(focus.y - target.y) < EE_SNAP: focus.y = target.y
	focus.z = 0.0
	_tilt = Vector2.ZERO
	trauma = 0.0
	_update_horizon(delta)
	_apply_transform(Vector2.ZERO)

# ---------------------------------------------------------------- cinematic
func set_cinematic_path(keys: Array) -> void:
	_cine_keys = keys
	_cine_s = 0.0

func begin_cinematic() -> void:
	mode = Mode.CINEMATIC

## speed in keyframes per second.
func cinematic(delta: float, speed: float = 0.055) -> void:
	_t += delta
	if _cine_keys.size() < 2:
		return
	_cine_s += delta * speed
	var n := _cine_keys.size()
	var i := int(floorf(_cine_s)) % n
	var f := _cine_s - floorf(_cine_s)
	f = f * f * (3.0 - 2.0 * f) * 0.35 + f * 0.65  # ease a little at the keys
	var p0: Dictionary = _cine_keys[(i - 1 + n) % n]
	var p1: Dictionary = _cine_keys[i]
	var p2: Dictionary = _cine_keys[(i + 1) % n]
	var p3: Dictionary = _cine_keys[(i + 2) % n]
	# Camera cuts (portal jumps / loop wrap): never fly across the map; jump to the next key instead.
	var wrap_cut: bool = (i + 1) % n == 0 and (p1.pos as Vector2).distance_to(p2.pos) > 30.0
	if (p2.get("cut", false) or wrap_cut) and p1.get("showcase", false):
		# showcase keys (hand-picked title shots) DWELL with a slow drift before the cut instead of skipping
		p0 = p1
		p2 = {"pos": (p1.pos as Vector2) + Vector2(4.0, -0.5), "zoom": float(p1.zoom) * 0.97}
		p3 = p2
	elif p2.get("cut", false) or wrap_cut:
		_cine_s = floorf(_cine_s) + 1.0
		cinematic_cut.emit()
		i = int(_cine_s) % n
		f = 0.0
		p0 = _cine_keys[i]
		p1 = _cine_keys[i]
		p2 = _cine_keys[(i + 1) % n]
		p3 = _cine_keys[(i + 2) % n]
		_tilt = Vector2.ZERO
	if p1.get("cut", false):
		p0 = p1
	if p3.get("cut", false):
		p3 = p2
	if i != _cine_last_i and _cine_last_i >= 0 and _cine_keys[i].get("cut", false) and _cine_keys[(i - 1 + n) % n].get("showcase", false):
		cinematic_cut.emit()   # entering the route after the showcase
		_tilt = Vector2.ZERO
	_cine_last_i = i
	var pos := _catmull(p0.pos, p1.pos, p2.pos, p3.pos, f)
	zoom = lerpf(p1.zoom, p2.zoom, f * f * (3.0 - 2.0 * f))
	target_zoom = zoom
	focus = _clamp_focus(Vector3(pos.x, -pos.y, 0.0))
	var d := _catmull(p0.pos, p1.pos, p2.pos, p3.pos, minf(f + 0.02, 1.0)) - pos
	var tilt := Vector2(clampf(d.x * 6.0, -1.0, 1.0) * MAX_YAW * 1.4, clampf(-d.y * 6.0, -1.0, 1.0) * MAX_PITCH_TILT)
	_tilt = _tilt.lerp(tilt, 1.0 - exp(-1.2 * delta))
	trauma = maxf(0.0, trauma - delta)
	_update_horizon(delta)
	_apply_transform(_tilt + Vector2(sin(_t * 0.21) * 0.6, sin(_t * 0.17) * 0.4))

# ---------------------------------------------------------------- internals
## Set the vertical fov at runtime (visible WIDTH stays the same: distance_for_zoom uses fov_v).
func set_fov(v: float) -> void:
	fov_v = v
	if cam:
		cam.fov = v

func _update_horizon(delta: float) -> void:
	var target := 0.0
	if horizon_pitch_on:
		var y := focus.y
		if y > horizon_y:
			target = -HORIZON_DOWN_DEG * clampf((y - horizon_y) / maxf(horizon_top - horizon_y, 1.0), 0.0, 1.0)
		else:
			target = HORIZON_UP_DEG * clampf((horizon_y - y) / maxf(horizon_y - horizon_bottom, 1.0), 0.0, 1.0)
	_alt_pitch = lerpf(_alt_pitch, target, 1.0 - exp(-delta / HORIZON_TAU))

func _apply_transform(tilt: Vector2) -> void:
	if cam == null:
		return
	var d := distance_for_zoom(zoom)
	var sh := trauma * trauma
	var shake_rot := Vector3(_noise.get_noise_2d(_t * 40.0, 0.0), _noise.get_noise_2d(0.0, _t * 40.0), _noise.get_noise_2d(_t * 40.0, 100.0)) * sh
	var pitch := deg_to_rad(BASE_PITCH + tilt.y + shake_rot.x * 1.4 + _alt_pitch)
	var yaw := deg_to_rad(tilt.x + shake_rot.y * 1.4)
	var roll := deg_to_rad(shake_rot.z * 2.0)
	var basis := Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_YXZ)
	var pivot := focus + Vector3(shake_rot.y, shake_rot.x, 0.0) * 0.35 * (zoom / 40.0)
	cam.global_transform = Transform3D(basis, pivot + basis * Vector3(0, 0, d))
	# DOF focus plane follows the gameplay plane when the world uses practical attributes.
	var attrs := cam.attributes if cam.attributes else null
	if attrs is CameraAttributesPractical and attrs.dof_blur_far_enabled:
		attrs.dof_blur_far_distance = d + 7.0

func _clamp_focus(p: Vector3) -> Vector3:
	var he := half_extents()
	var minx := he.x
	var maxx := level_size.x - he.x
	var maxy := -he.y          # top of level is y = 0
	var miny := -level_size.y + he.y
	p.x = level_size.x * 0.5 if minx > maxx else clampf(p.x, minx, maxx)
	p.y = -level_size.y * 0.5 if miny > maxy else clampf(p.y, miny, maxy)
	return p

func _smooth_damp(cur: Vector3, target: Vector3, smooth_time: float, dt: float) -> Vector3:
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var temp := (_focus_vel + omega * change) * dt
	_focus_vel = (_focus_vel - omega * temp) * e
	return target + (change + temp) * e

static func _damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
