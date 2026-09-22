class_name CollisionOverlay
extends Node3D
## F3 debug view of TRUE collision: every tile the sim currently treats as solid (sim.is_tile_solid_now,
## so doors/gates follow their keys) as a translucent cyan outlined square, one-way platforms in amber,
## and the player's 16x16 hitbox in magenta. Drawn exactly ON the gameplay plane (z = 0, where the ball
## lives) with no depth test, so it lines up with the ball regardless of perspective/tilt and is never
## hidden by sculpted geometry. Rebuilt for the visible region when the camera moves a tile or doors change.

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, blend_mix;
uniform float line = 0.07;
void fragment() {
	vec2 d = min(UV, 1.0 - UV);
	float e = min(d.x, d.y);
	float border = 1.0 - smoothstep(line * 0.6, line, e);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * mix(0.16, 0.95, border);
}
"""

const SOLID_COLOR := Color(0.2, 0.95, 1.0, 0.9)
const ONEWAY_COLOR := Color(1.0, 0.75, 0.15, 0.9)
const PLAYER_COLOR := Color(1.0, 0.2, 0.85, 1.0)
const MARGIN := 4

var sim
var level
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _player: MultiMesh
var _region := Rect2i()
var _dirty := true

func setup(lvl, s) -> void:
	level = lvl
	sim = s
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 120
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 16384.0
	add_child(_mmi)
	# player hitbox: a 1-instance multimesh so it can use the same vertex-color shader
	_player = MultiMesh.new()
	_player.transform_format = MultiMesh.TRANSFORM_3D
	_player.use_colors = true
	var pq := QuadMesh.new()
	pq.size = Vector2(1, 1)
	var pm := mat.duplicate() as ShaderMaterial
	pm.render_priority = 121
	pq.material = pm
	_player.mesh = pq
	_player.instance_count = 1
	_player.set_instance_color(0, PLAYER_COLOR)
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = _player
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.extra_cull_margin = 16384.0
	add_child(pmi)
	visible = false

func mark_dirty() -> void:
	_dirty = true

## focus: camera focus (world units, z = 0); half: visible half extents in tiles.
func update_view(focus: Vector3, half: Vector2, player_pos: Vector3) -> void:
	if not visible or sim == null:
		return
	var tx0 := int(floorf(focus.x - half.x)) - MARGIN
	var ty0 := int(floorf(-focus.y - half.y)) - MARGIN
	var r := Rect2i(tx0, ty0, int(ceilf(half.x * 2.0)) + MARGIN * 2 + 1, int(ceilf(half.y * 2.0)) + MARGIN * 2 + 1)
	if r != _region or _dirty:
		_region = r
		_dirty = false
		_rebuild()
	# player hitbox (16x16 px box) at the interpolated render position, so it overlays the ball exactly
	_player.set_instance_transform(0, Transform3D(Basis(), Vector3(player_pos.x, player_pos.y, 0.0)))

func _rebuild() -> void:
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var one_way: bool = sim.has_method(&"is_tile_one_way")
	for ty in range(_region.position.y, _region.end.y):
		for tx in range(_region.position.x, _region.end.x):
			if tx < 0 or ty < 0 or tx >= level.width or ty >= level.height:
				continue
			if not sim.is_tile_solid_now(tx, ty):
				continue
			xf.append(Transform3D(Basis(), EECoords.tile_center(tx, ty, 0.0)))
			col.append(ONEWAY_COLOR if one_way and sim.is_tile_one_way(tx, ty) else SOLID_COLOR)
	_mm.instance_count = xf.size()
	for i in xf.size():
		_mm.set_instance_transform(i, xf[i])
		_mm.set_instance_color(i, col[i])
