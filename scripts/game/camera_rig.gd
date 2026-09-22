class_name CameraRig
extends Node3D
## Perspective gameplay camera. Orbits a focus point on the gameplay plane (z = 0):
## - critically damped follow with velocity look-ahead and slight vertical framing
## - gentle 3D parallax tilt toward the direction of motion (+ a constant slight downward pitch)
## - trauma-based shake (landings, deaths), zoom = tiles visible horizontally, clamped to level bounds
## - cinematic mode: slow Catmull-Rom flyover through keyframes (title screen)

enum Mode { FOLLOW, CINEMATIC }

const FOV_V := 34.0                  # vertical fov (degrees); moderate perspective = readable parallax
const BASE_PITCH := -5.0             # look slightly down on the diorama
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
var _smooth_boost := 0.0             # extra smoothing during intro swoop (decays)
var _noise := FastNoiseLite.new()
var _t := 0.0
var _cine_keys: Array = []           # [{pos: Vector2 (tile space, y down), zoom: float}]
var _cine_s := 0.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = FOV_V
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
	var tan_h := tan(deg_to_rad(FOV_V) * 0.5) * aspect
	return (z * 0.5) / tan_h

## Half extents of the visible region at z = 0 (tiles).
func half_extents() -> Vector2:
	var d := distance_for_zoom(zoom)
	var tv := tan(deg_to_rad(FOV_V) * 0.5)
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	return Vector2(d * tv * vp.x / maxf(vp.y, 1.0), d * tv)

func add_zoom_steps(steps: float) -> void:
	target_zoom = clampf(target_zoom * pow(1.12, steps), ZOOM_MIN, ZOOM_MAX)

func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)

func snap_to(world_pos: Vector3) -> void:
	focus = _clamp_focus(Vector3(world_pos.x, world_pos.y + FRAME_UP, 0.0))
	_focus_vel = Vector3.ZERO
	_look = Vector2.ZERO
	_fall_look = Vector2.ZERO

## Switch to follow mode; with swoop=true the camera glides from wherever it is (title -> gameplay).
func begin_follow(swoop: bool) -> void:
	mode = Mode.FOLLOW
	_smooth_boost = 1.1 if swoop else 0.0

## world_pos: interpolated player center; vel: tiles/second (world axes, y up);
## gravity: current gravity direction (world axes, y up; zero for dots / god mode keeps the last one).
func follow(world_pos: Vector3, vel: Vector2, delta: float, gravity: Vector2 = Vector2(0, -1)) -> void:
	_t += delta
	zoom = _damp(zoom, target_zoom, 7.0, delta)
	var la := Vector2(clampf(vel.x * LOOK_AHEAD_TIME, -LOOK_AHEAD_MAX.x, LOOK_AHEAD_MAX.x),
		clampf(vel.y * LOOK_AHEAD_TIME * 0.6, -LOOK_AHEAD_MAX.y, LOOK_AHEAD_MAX.y * 0.5))
	_look = _look.lerp(la, 1.0 - exp(-2.2 * delta))
	# Gravity-relative framing is smoothed so arrow fields (rapid gravity flips) never jitter the camera.
	if gravity.length_squared() > 0.01:
		_grav = _grav.slerp(gravity.normalized(), 1.0 - exp(-GRAV_SMOOTH * delta)).normalized()
	# Long falls: frame the terrain coming up along gravity.
	# The damped follow trails a fast fall by ~speed * smooth_time, so compensate that lag first, then lead
	# by an extra amount that grows with speed; capped so the ball stays in the upper part of the frame.
	var v_g := vel.dot(_grav)
	var he := half_extents()
	var lead := 0.0
	if v_g > FALL_LOOK_START:
		lead = (v_g - FALL_LOOK_START) * follow_smooth + clampf((v_g - FALL_LOOK_START) * FALL_LOOK_GAIN, 0.0, FALL_LOOK_MAX)
	var fl := _grav * minf(lead, he.y * 1.25)
	_fall_look = _fall_look.lerp(fl, 1.0 - exp(-(6.0 if fl.length() > _fall_look.length() else 1.5) * delta))
	var up := -_grav * FRAME_UP
	var target := Vector3(world_pos.x + _look.x + _fall_look.x + up.x, world_pos.y + _look.y + _fall_look.y + up.y, 0.0)
	target = _clamp_focus(target)
	# Teleports (portals, respawn far away): don't drag the camera across the map.
	if focus.distance_to(target) > 30.0 and _smooth_boost <= 0.0:
		focus = target
		_focus_vel = Vector3.ZERO
	_smooth_boost = maxf(0.0, _smooth_boost - delta * 0.45)
	var st := follow_smooth + _smooth_boost * _smooth_boost * 1.1
	focus = _smooth_damp(focus, target, st, delta)
	var tl := _look + _fall_look * 0.5
	var tilt_target := Vector2(clampf(tl.x / LOOK_AHEAD_MAX.x, -1.0, 1.0) * MAX_YAW, clampf(tl.y / LOOK_AHEAD_MAX.y, -1.0, 1.0) * MAX_PITCH_TILT)
	_tilt = _tilt.lerp(tilt_target, 1.0 - exp(-3.0 * delta))
	trauma = maxf(0.0, trauma - delta * 1.5)
	_apply_transform(_tilt)

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
	var pos := _catmull(p0.pos, p1.pos, p2.pos, p3.pos, f)
	zoom = lerpf(p1.zoom, p2.zoom, f * f * (3.0 - 2.0 * f))
	target_zoom = zoom
	focus = _clamp_focus(Vector3(pos.x, -pos.y, 0.0))
	var d := _catmull(p0.pos, p1.pos, p2.pos, p3.pos, minf(f + 0.02, 1.0)) - pos
	var tilt := Vector2(clampf(d.x * 6.0, -1.0, 1.0) * MAX_YAW * 1.4, clampf(-d.y * 6.0, -1.0, 1.0) * MAX_PITCH_TILT)
	_tilt = _tilt.lerp(tilt, 1.0 - exp(-1.2 * delta))
	trauma = maxf(0.0, trauma - delta)
	_apply_transform(_tilt + Vector2(sin(_t * 0.21) * 0.6, sin(_t * 0.17) * 0.4))

# ---------------------------------------------------------------- internals
func _apply_transform(tilt: Vector2) -> void:
	if cam == null:
		return
	var d := distance_for_zoom(zoom)
	var sh := trauma * trauma
	var shake_rot := Vector3(_noise.get_noise_2d(_t * 40.0, 0.0), _noise.get_noise_2d(0.0, _t * 40.0), _noise.get_noise_2d(_t * 40.0, 100.0)) * sh
	var pitch := deg_to_rad(BASE_PITCH + tilt.y + shake_rot.x * 1.4)
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
