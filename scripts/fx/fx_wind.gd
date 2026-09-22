class_name FxWind
extends Node3D
## Wind in the arrow fields (non-Odyssey levels): every large connected field of one gravity-arrow id
## (1 left, 2 up, 3 right) gets pale drifting motes and thin streaks blowing along its direction, so the
## trial rooms' currents read as moving air (FV's spire updraft shaft is the showcase). The chevrons stay
## crisp: particles are faint, small, and live just behind the glyph plane. Culled by camera distance.

const MIN_TILES := 40
const ACTIVE_RADIUS := 34.0
const DIRS := {1: Vector3(-1, 0, 0), 2: Vector3(0, 1, 0), 3: Vector3(1, 0, 0)}

var lvl: EELevel
var _fields: Array = []   # {motes, streaks, center: Vector2}
var _cull_t := 0.0
var focus_override := Vector3(INF, 0, 0)

func build(level: EELevel) -> void:
	lvl = level
	for id in DIRS:
		var tiles := lvl.find_all(id)
		var set_ := {}
		for t in tiles:
			set_[t] = true
		var seen := {}
		for t0 in tiles:
			if seen.has(t0):
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [t0]
			seen[t0] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				comp.append(c)
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var n := c + Vector2i(dx, dy)
						if set_.has(n) and not seen.has(n):
							seen[n] = true
							stack.append(n)
			if comp.size() >= MIN_TILES:
				_build_field(comp, DIRS[id])
	print("FxWind: %d arrow-field currents" % _fields.size())

func _build_field(comp: Array[Vector2i], dir: Vector3) -> void:
	var mn := Vector2i(99999, 99999)
	var mx := Vector2i(-1, -1)
	for t in comp:
		mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
		mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
	var size := Vector2(mx - mn) + Vector2.ONE
	var center := Vector3(mn.x + size.x * 0.5, -(mn.y + size.y * 0.5), -0.2)
	var along := size.y if dir.y != 0.0 else size.x
	var n := clampi(int(comp.size() * 0.12), 8, 90)
	var motes := _emitter(size, dir, along, n, false)
	motes.position = center
	add_child(motes)
	var streaks := _emitter(size, dir, along, clampi(n / 3, 4, 30), true)
	streaks.position = center
	add_child(streaks)
	_fields.append({"motes": motes, "streaks": streaks, "center": Vector2(center.x, -center.y),
		"r": maxf(size.x, size.y) * 0.5})

## Particles fill the field's bounding box and blow along its direction.
func _emitter(size: Vector2, dir: Vector3, along: float, amount: int, streak: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "WindStreaks" if streak else "WindMotes"
	var speed := 6.0 if streak else 3.2
	p.amount = amount
	p.lifetime = clampf(along / speed, 1.5, 10.0)
	p.preprocess = p.lifetime
	p.randomness = 0.3
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY if streak else GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-size.x, -size.y, -2), Vector3(size.x * 2, size.y * 2, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.5, 0.25)
	pm.direction = dir
	pm.spread = 4.0 if streak else 12.0
	pm.initial_velocity_min = speed * 0.8
	pm.initial_velocity_max = speed * 1.2
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = not streak
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	var a := 0.55 if streak else 0.8
	g.colors = PackedColorArray([Color(1.0, 0.92, 0.7, 0), Color(1.0, 0.92, 0.7, a), Color(1.0, 0.9, 0.65, a), Color(1.0, 0.9, 0.6, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.5) if streak else Vector2(0.07, 0.07)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/particle.gdshader")
	m.set_shader_parameter("intensity", 1.4 if streak else 2.0)
	m.set_shader_parameter("streak", 1.0 if streak else 0.0)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _process(delta: float) -> void:
	_cull_t -= delta
	if _cull_t > 0.0:
		return
	_cull_t = 0.3
	var f := focus_override
	if f.x == INF:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		f = cam.global_position
	var ft := Vector2(f.x, -f.y)
	for fl in _fields:
		var on: bool = (fl.center as Vector2).distance_to(ft) < ACTIVE_RADIUS + fl.r
		fl.motes.emitting = on
		fl.streaks.emitting = on
