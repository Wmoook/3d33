class_name FxBursts
extends Node3D
## Pooled one-shot GPU particle bursts + short-lived flash lights for gameplay events.
## Usage: bursts.play(&"coin", world_pos, dir, color)

const PARTICLE_SHADER := preload("res://shaders/fx/particle.gdshader")
const SHARD_SHADER := preload("res://shaders/fx/shard.gdshader")

var _pools := {}      # kind -> Array[GPUParticles3D]
var _next := {}       # kind -> int
var _flashes: Array[OmniLight3D] = []
var _flash_t: Array[float] = []
var _flash_len: Array[float] = []
var _flash_e: Array[float] = []

func _ready() -> void:
	_make_pool(&"dust", 4, _dust)
	_make_pool(&"sparks", 4, _sparks)
	_make_pool(&"coin", 3, _coin)
	_make_pool(&"coin_ring", 3, _coin_ring)
	_make_pool(&"key", 4, _key)
	_make_pool(&"portal", 4, _portal)
	_make_pool(&"shards", 2, _shards)
	_make_pool(&"death_sparks", 2, _death_sparks)
	_make_pool(&"respawn", 2, _respawn)
	_make_pool(&"crown", 2, _crown)
	for i in 6:
		var l := OmniLight3D.new()
		l.visible = false
		l.omni_range = 6.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_flashes.append(l)
		_flash_t.append(0.0)
		_flash_len.append(1.0)
		_flash_e.append(0.0)

func _process(delta: float) -> void:
	for i in _flashes.size():
		var l := _flashes[i]
		if not l.visible:
			continue
		_flash_t[i] += delta
		var k := _flash_t[i] / _flash_len[i]
		if k >= 1.0:
			l.visible = false
			continue
		l.light_energy = _flash_e[i] * pow(1.0 - k, 2.0)

## Plays a burst. dir: world-space direction hint (e.g. up-vector away from the floor on landing).
func play(kind: StringName, pos: Vector3, dir := Vector3.UP, color := Color.WHITE, strength := 1.0) -> void:
	if not _pools.has(kind):
		return
	var pool: Array = _pools[kind]
	var i: int = _next[kind]
	_next[kind] = (i + 1) % pool.size()
	var p: GPUParticles3D = pool[i]
	p.global_position = pos
	# Orient so local +y = dir (process materials emit along +y).
	var up := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	p.global_transform.basis = Basis(side, up, side.cross(up)).orthonormalized()
	p.amount_ratio = clampf(strength, 0.1, 1.0)
	var pm := p.process_material as ParticleProcessMaterial
	if p.has_meta("tint"):
		pm.color = color
	p.restart()
	p.emitting = true

func flash(pos: Vector3, color: Color, energy := 4.0, length := 0.35, light_range := 6.0) -> void:
	var best := 0
	for i in _flashes.size():
		if not _flashes[i].visible:
			best = i
			break
	var l := _flashes[best]
	l.global_position = pos
	l.light_color = color
	l.omni_range = light_range
	l.light_energy = energy
	l.visible = true
	_flash_t[best] = 0.0
	_flash_len[best] = length
	_flash_e[best] = energy

# ----------------------------------------------------------------------------- builders

func _make_pool(kind: StringName, n: int, builder: Callable) -> void:
	var arr: Array = []
	for i in n:
		var p: GPUParticles3D = builder.call()
		p.one_shot = true
		p.emitting = false
		p.local_coords = false
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		add_child(p)
		arr.append(p)
	_pools[kind] = arr
	_next[kind] = 0

func _sprite_pass(size: float, streak := false, intensity := 3.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size * (3.0 if streak else 1.0))
	var m := ShaderMaterial.new()
	m.shader = PARTICLE_SHADER
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("streak", 1.0 if streak else 0.0)
	q.material = m
	return q

func _ramp(cols: Array, offs: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in pts:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t

func _base(amount: int, life: float, explos := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.explosiveness = explos
	p.fixed_fps = 0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	return p

func _dust() -> GPUParticles3D:
	var p := _base(28, 0.75)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3(1, 0.25, 0)
	pm.spread = 180.0
	pm.flatness = 0.85
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _curve([Vector2(0, 0.4), Vector2(0.3, 1.0), Vector2(1, 1.6)])
	pm.color_ramp = _ramp([Color(0.9, 0.82, 0.68, 0.5), Color(0.7, 0.62, 0.5, 0.25), Color(0.5, 0.45, 0.4, 0.0)], [0.0, 0.5, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(0.42, false, 0.9)
	return p

func _sparks() -> GPUParticles3D:
	var p := _base(26, 0.45)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.flatness = 0.7
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -14, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	pm.color_ramp = _ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.55, 0.12, 1), Color(0.8, 0.2, 0.02, 0)], [0.0, 0.4, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(0.07, true, 4.0)
	return p

func _coin() -> GPUParticles3D:
	var p := _base(48, 0.9)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.set_meta("tint", true)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.flatness = 0.4
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	pm.color = Color(1, 0.8, 0.25)
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.5, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(0.08, true, 5.0)
	return p

func _coin_ring() -> GPUParticles3D:
	var p := _base(1, 0.35)
	p.set_meta("tint", true)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(1, 1.0)])
	pm.color = Color(1, 0.85, 0.4)
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(2.6, false, 2.5)
	return p

func _key() -> GPUParticles3D:
	var p := _base(40, 0.8)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.set_meta("tint", true)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.flatness = 0.5
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, 1.5, 0)
	pm.damping_min = 4.0
	pm.damping_max = 6.0
	pm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	pm.color = Color(1, 0.3, 0.3)
	pm.color_ramp = _ramp([Color(1.6, 1.6, 1.6, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.3, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(0.09, true, 5.0)
	return p

func _portal() -> GPUParticles3D:
	var p := _base(56, 0.6)
	p.set_meta("tint", true)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 0.9
	pm.emission_ring_inner_radius = 0.6
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.5
	pm.radial_accel_min = -14.0
	pm.radial_accel_max = -8.0
	pm.tangential_accel_min = 12.0
	pm.tangential_accel_max = 18.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 0.2), Vector2(0.3, 1), Vector2(1, 0)])
	pm.color = Color(0.5, 0.85, 1.0)
	pm.color_ramp = _ramp([Color(1.5, 1.5, 1.5, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.5, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(0.12, false, 4.0)
	return p

func _shards() -> GPUParticles3D:
	var p := _base(26, 1.3)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.flatness = 0.55
	pm.initial_velocity_min = 3.5
	pm.initial_velocity_max = 8.5
	pm.gravity = Vector3(0, -16, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.2
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.08
	pm.scale_max = 0.2
	pm.scale_curve = _curve([Vector2(0, 1), Vector2(0.8, 0.9), Vector2(1, 0)])
	pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 0.9, 0.8, 0.5), Color(0.8, 0.6, 0.5, 0.0)], [0.0, 0.35, 1.0])
	p.process_material = pm
	var m := FxMeshes.shard().duplicate() as Mesh
	var sm := ShaderMaterial.new()
	sm.shader = SHARD_SHADER
	m.surface_set_material(0, sm)
	p.draw_pass_1 = m
	return p

func _death_sparks() -> GPUParticles3D:
	var p := _sparks()
	p.amount = 70
	p.lifetime = 0.8
	var pm := p.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -8, 0)
	return p

func _respawn() -> GPUParticles3D:
	var p := _base(60, 0.5)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 1.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.radial_accel_min = -26.0
	pm.radial_accel_max = -18.0
	pm.gravity = Vector3.ZERO
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.6, 1), Vector2(1, 0)])
	pm.color_ramp = _ramp([Color(1, 0.8, 0.35, 0), Color(1, 0.9, 0.55, 1), Color(1, 1, 0.9, 0)], [0.0, 0.4, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _sprite_pass(0.07, true, 5.0)
	return p

func _crown() -> GPUParticles3D:
	var p := _coin()
	p.amount = 60
	var pm := p.process_material as ParticleProcessMaterial
	pm.gravity = Vector3(0, 2, 0)
	pm.color = Color(1.0, 0.82, 0.3)
	return p
