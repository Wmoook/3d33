class_name FxTrail
extends MeshInstance3D
## Speed-streak ribbon: records recent ball centers (world space) and rebuilds a tapered strip each frame.

const TRAIL_SHADER := preload("res://shaders/fx/trail.gdshader")
const MAX_AGE := 0.2
const WIDTH := 0.78

var _pts: Array[Vector3] = []
var _ages: Array[float] = []
var _str: Array[float] = []
var _im := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 10000.0

func clear() -> void:
	_pts.clear(); _ages.clear(); _str.clear()
	_im.clear_surfaces()

func push(p: Vector3, strength: float, delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	while _ages.size() > 0 and _ages[_ages.size() - 1] > MAX_AGE:
		_pts.pop_back(); _ages.pop_back(); _str.pop_back()
	var tp := Vector3(p.x, p.y, -0.08)
	if _pts.is_empty() or _pts[0].distance_to(tp) > 0.02:
		_pts.push_front(tp); _ages.push_front(0.0); _str.push_front(strength)
	else:
		_str[0] = strength
	_rebuild()

func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	var total := 0.0
	for i in n - 1:
		total += _pts[i].distance_to(_pts[i + 1])
	if total < 0.05:
		return
	var any := false
	for s in _str:
		if s > 0.01:
			any = true
			break
	if not any:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var acc := 0.0
	for i in n:
		var d: Vector3
		if i == 0:
			d = _pts[0] - _pts[1]
		elif i == n - 1:
			d = _pts[i - 1] - _pts[i]
		else:
			d = _pts[i - 1] - _pts[i + 1]
		var d2 := Vector2(d.x, d.y).normalized()
		var side := Vector3(-d2.y, d2.x, 0)
		if i > 0:
			acc += _pts[i - 1].distance_to(_pts[i])
		var u := acc / total
		var age_k := 1.0 - _ages[i] / MAX_AGE
		var w := WIDTH * 0.5 * (1.0 - u * 0.75)
		var a := clampf(_str[i] * age_k, 0.0, 1.0)
		_im.surface_set_color(Color(1, 1, 1, a))
		_im.surface_set_uv(Vector2(u, 0.0))
		_im.surface_add_vertex(_pts[i] + side * w)
		_im.surface_set_color(Color(1, 1, 1, a))
		_im.surface_set_uv(Vector2(u, 1.0))
		_im.surface_add_vertex(_pts[i] - side * w)
	_im.surface_end()
