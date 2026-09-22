class_name FxOverlays
extends Node3D
## Hero FX over the world's terrain: living fire (glow field, flame tongues, embers, heat haze, pooled
## flicker lights), water (surface crest/foam, caustics, splash streams, mist, splashes), the tornado swirl,
## ice glints + snow, corruption spores. Sources come from FxOverlayMaps (minimap analysis).
## Everything expensive is chunked and switched on/off by distance to the active camera (_process).

const FIELD_SHADER := preload("res://shaders/fx/overlay_field.gdshader")
const FLAME_SHADER := preload("res://shaders/fx/flame.gdshader")
const HAZE_SHADER := preload("res://shaders/fx/heat_haze.gdshader")
const WATER_SHADER := preload("res://shaders/fx/water_surface.gdshader")
const TORNADO_SHADER := preload("res://shaders/fx/tornado.gdshader")
const PARTICLE_SHADER := preload("res://shaders/fx/particle.gdshader")

const Z_FIELD := 0.86        # just in front of the terrain face (world terrain front ~0.8)
const Z_FLAME := -0.15       # flame tongues live in the air above fire, behind the ball's front
const LIGHT_POOL := 20
const ACTIVE_RADIUS := 34.0  # tiles from the camera focus
const CULL_PERIOD := 0.2

var maps := FxOverlayMaps.new()
var lvl: EELevel

var _flame_chunks: Array = []    # [{node: MultiMeshInstance3D, center: Vector2}]
var _ember_chunks: Array = []    # [{node: GPUParticles3D, center: Vector2}]
var _haze_chunks: Array = []     # [{node: MeshInstance3D, center: Vector2}]
var _light_sites: Array = []     # [{pos: Vector3, energy: float, color: Color}]
var _lights: Array[OmniLight3D] = []
var _light_site_of: Array[int] = []
var _mist_chunks: Array = []
var _splash_sites: Array[Vector3] = []
var _splash_pool: Array[GPUParticles3D] = []
var _splash_next := 0
var _splash_t := 0.0
var _tornado: GPUParticles3D
var _tornado_dust: GPUParticles3D
var _snow: GPUParticles3D
var _spores: GPUParticles3D
var _cull_t := 0.0
var _focus := Vector3(-1000, 0, 0)
var _zone_w := {}  # zone -> smoothed weight around the camera
var focus_override := Vector3(INF, 0, 0)  # tests may pin the focus

func build(level: EELevel) -> void:
	lvl = level
	var t := Time.get_ticks_msec()
	maps.build(level)
	_build_field()
	_build_fire()
	_build_water()
	_build_ambient()
	print("FxOverlays: %d ms, fire tops %d, fire chunks %d, water surface %d, streams %d" % [
		Time.get_ticks_msec() - t, maps.fire_tops.size(), maps.fire_chunks.size(),
		maps.water_surface.size(), maps.stream_tiles.size()])

# ----------------------------------------------------------------------------- field (one draw call)

func _build_field() -> void:
	var tex := ImageTexture.create_from_image(maps.mask)
	var mi := MeshInstance3D.new()
	mi.name = "OverlayField"
	var q := QuadMesh.new()
	q.size = Vector2(lvl.width, lvl.height)
	mi.mesh = q
	mi.position = Vector3(lvl.width * 0.5, -lvl.height * 0.5, Z_FIELD)
	var m := ShaderMaterial.new()
	m.shader = FIELD_SHADER
	m.set_shader_parameter("mask_lin", tex)
	m.set_shader_parameter("mask_near", tex)
	m.set_shader_parameter("level_size", Vector2(lvl.width, lvl.height))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ----------------------------------------------------------------------------- fire

func _build_fire() -> void:
	var fm := ShaderMaterial.new()
	fm.shader = FLAME_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0, 0.5, 0)   # pivot at the bottom edge
	quad.material = fm
	# flame tongues grouped by chunk
	var by_chunk := {}
	for t in maps.fire_tops:
		var key := Vector2i(t.x / FxOverlayMaps.CHUNK, t.y / FxOverlayMaps.CHUNK)
		if not by_chunk.has(key):
			by_chunk[key] = [] as Array[Vector2i]
		by_chunk[key].append(t)
	for key in by_chunk:
		var tiles: Array = by_chunk[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = tiles.size() * 2
		var c := Vector2.ZERO
		for i in tiles.size():
			var t: Vector2i = tiles[i]
			c += Vector2(t.x + 0.5, t.y)
			var hot := 1.0 if maps.fire[t.y * maps.W + t.x] == 2 else 0.45
			for k in 2:
				var h := FxInteractiveBlocks._tile_hash(t + Vector2i(k * 71, k * 13))
				var hgt := (1.4 + h.x * 1.6) * (0.75 + hot * 0.45) * (1.0 if k == 0 else 0.65)
				var wid := 1.5 + h.y * 0.7
				var b := Basis.IDENTITY.scaled(Vector3(wid, hgt, 1.0))
				var o := Vector3(t.x + 0.5 + (h.z - 0.5) * 0.5, -t.y - 0.08, Z_FLAME - k * 0.2)
				if k == 1 and h.x > 0.35:
					b = b.scaled(Vector3.ZERO)   # only some tiles get a second, rear tongue
				mm.set_instance_transform(i * 2 + k, Transform3D(b, o))
				mm.set_instance_custom_data(i * 2 + k, Color(h.x * 0.7 + h.z * 0.3, hot, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Flames_%d_%d" % [key.x, key.y]
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_flame_chunks.append({"node": mi, "center": c / tiles.size()})
	# embers, haze and light sites per fire chunk
	for ch in maps.fire_chunks:
		var center: Vector2 = ch.center
		var mn: Vector2i = ch.min
		var mx: Vector2i = ch.max
		var size := Vector2(mx - mn) + Vector2.ONE
		var wc := Vector3(center.x, -center.y, 0.0)
		var e := _embers(size)
		e.position = Vector3(mn.x + size.x * 0.5, -(mn.y + size.y * 0.5), 0.1)
		e.emitting = false
		add_child(e)
		_ember_chunks.append({"node": e, "center": center})
		if ch.count >= 8:
			var hz := MeshInstance3D.new()
			var hq := QuadMesh.new()
			hq.size = Vector2(size.x + 2.0, minf(size.y, 6.0) + 4.0)
			hq.center_offset = Vector3(0, hq.size.y * 0.5, 0)
			hz.mesh = hq
			var hm := ShaderMaterial.new()
			hm.shader = HAZE_SHADER
			hz.material_override = hm
			hz.position = Vector3(mn.x + size.x * 0.5, -(mn.y + 1.0), 0.6)
			hz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hz.visible = false
			add_child(hz)
			_haze_chunks.append({"node": hz, "center": center})
		_light_sites.append({"pos": wc + Vector3(0, 0.8, 1.2), "energy": clampf(0.5 + ch.count * 0.01, 0.5, 0.9),
			"color": Color(1.0, 0.55, 0.2)})
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.omni_range = 3.5
		l.omni_attenuation = 1.6
		l.distance_fade_enabled = true
		l.distance_fade_begin = 36.0
		l.distance_fade_length = 8.0
		l.light_color = Color(1.0, 0.55, 0.2)
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 0.6
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_site_of.append(-1)

func _embers(size: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = clampi(int(size.x * size.y * 0.25), 12, 70)
	p.lifetime = 2.6
	p.preprocess = 2.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(Vector3(-size.x, -size.y, -2), Vector3(size.x * 2, size.y * 2 + 10, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.5, 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.5
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.3
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 0.2)); c.add_point(Vector2(0.15, 1.0)); c.add_point(Vector2(1, 0))
	var ct := CurveTexture.new(); ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.5, 1), Color(1.0, 0.45, 0.08, 1), Color(0.6, 0.08, 0.0, 0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _sprite(0.07, true, 5.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _sprite(size: float, streak: bool, intensity: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size * (3.0 if streak else 1.0))
	var m := ShaderMaterial.new()
	m.shader = PARTICLE_SHADER
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("streak", 1.0 if streak else 0.0)
	q.material = m
	return q

# ----------------------------------------------------------------------------- water

func _build_water() -> void:
	# merge surface tiles into horizontal runs -> one strip mesh each
	var sm := ShaderMaterial.new()
	sm.shader = WATER_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var surf := {}
	for t in maps.water_surface:
		surf[t] = true
	var done := {}
	var runs := 0
	for t in maps.water_surface:
		if done.has(t) or surf.has(t + Vector2i(-1, 0)):
			continue
		var x1 := t.x
		while surf.has(Vector2i(x1 + 1, t.y)):
			x1 += 1
		for x in range(t.x, x1 + 1):
			done[Vector2i(x, t.y)] = true
		if x1 - t.x < 3:
			continue   # short steps (splash sheets, icicle tips) get no crest line
		var top := -float(t.y) + 0.14
		var bot := -float(t.y) - 0.9
		var a := float(t.x) - 0.05
		var b := float(x1) + 1.05
		var z := Z_FIELD + 0.02
		for v in [[a, top, 0.0], [a, bot, 1.0], [b, bot, 1.0], [a, top, 0.0], [b, bot, 1.0], [b, top, 0.0]]:
			st.set_uv(Vector2(v[0], v[2]))
			st.add_vertex(Vector3(v[0], v[1], z))
		runs += 1
		var cx := (a + b) * 0.5
		if (b - a) >= 3.0:
			var mist := _mist(b - a)
			mist.position = Vector3(cx, top + 0.1, 0.2)
			mist.emitting = false
			add_child(mist)
			_mist_chunks.append({"node": mist, "center": Vector2(cx, t.y)})
		var x := a + 1.5
		while x < b - 1.0:
			_splash_sites.append(Vector3(x, top, 0.3))
			x += 4.0
	if runs > 0:
		var mi := MeshInstance3D.new()
		mi.name = "WaterSurface"
		mi.mesh = st.commit()
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# streams: splash sites at the base of each stream column
	for t in maps.stream_tiles:
		if (t.x + t.y) % 5 == 0 and maps.stream[(t.y + 1) * maps.W + t.x] == 0:
			_splash_sites.append(Vector3(t.x + 0.5, -t.y - 1.0, 0.4))
	for i in 5:
		var s := _splash()
		add_child(s)
		_splash_pool.append(s)

func _mist(width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = clampi(int(width * 0.8), 6, 40)
	p.lifetime = 4.0
	p.preprocess = 3.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-width, -2, -2), Vector3(width * 2, 6, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.2, 0.4)
	pm.direction = Vector3(1, 0.3, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.12, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4)); c.add_point(Vector2(1, 1.5))
	var ct := CurveTexture.new(); ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(0.6, 0.8, 1.0, 0), Color(0.6, 0.8, 1.0, 0.16), Color(0.6, 0.8, 1.0, 0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _sprite(1.4, false, 0.8)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(Vector3(-4, -2, -2), Vector3(8, 8, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.4, 0.05, 0.2)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 28.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -12, 0)
	var c := Curve.new()
	c.add_point(Vector2(0, 1)); c.add_point(Vector2(1, 0.3))
	var ct := CurveTexture.new(); ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0.8, 0.93, 1.0, 0.9), Color(0.5, 0.75, 1.0, 0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _sprite(0.06, true, 3.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ----------------------------------------------------------------------------- tornado / snow / spores

func _build_ambient() -> void:
	_tornado = _tornado_system(2600, false)
	_tornado_dust = _tornado_system(700, true)

	_snow = _camera_emitter(420, 7.0, Color(0.9, 0.95, 1.0, 0.8), Vector3(0.2, -1.1, 0), 0.13, false)
	_snow.name = "Snow"
	add_child(_snow)
	_spores = _camera_emitter(220, 9.0, Color(0.85, 0.5, 1.0, 0.9), Vector3(0.1, 0.18, 0), 0.16, true)
	_spores.name = "Spores"
	add_child(_spores)

func _tornado_system(n: int, dust: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "TornadoDust" if dust else "TornadoDebris"
	p.amount = n
	p.lifetime = 30.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD if dust else GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(Vector3(-5, -145, -12), Vector3(60, 75, 24))
	var tm := ShaderMaterial.new()
	tm.shader = TORNADO_SHADER
	tm.set_shader_parameter("dust", 1.0 if dust else 0.0)
	p.process_material = tm
	p.draw_pass_1 = _sprite(2.2, false, 0.7) if dust else _sprite(0.2, true, 1.6)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = true
	add_child(p)
	return p

## Ambient emitter that covers the camera view; particles stay in world space.
func _camera_emitter(amount: int, life: float, color: Color, grav: Vector3, size: float, wander: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emitting = false
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-40, -30, -6), Vector3(80, 60, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 16, 1.2)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = grav
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5 if wander else 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2 if wander else 0.1
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = color
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _sprite(size, false, 2.5 if wander else 1.6)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ----------------------------------------------------------------------------- runtime culling

func _process(delta: float) -> void:
	var f := focus_override
	if f.x == INF:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		f = cam.global_position
	_focus = f
	var ftile := Vector2(f.x, -f.y)
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = CULL_PERIOD
		_cull(ftile)
	_update_lights(delta)
	# ambient zone emitters follow the camera and fade in with the zone around it
	_zone_w["ice"] = move_toward(_zone_w.get("ice", 0.0), _zone_frac(ftile, WorldPalette.Z_ICE), delta)
	_zone_w["corrupt"] = move_toward(_zone_w.get("corrupt", 0.0), _zone_frac(ftile, WorldPalette.Z_CORRUPT), delta)
	_drive_camera_emitter(_snow, _zone_w["ice"], f)
	_drive_camera_emitter(_spores, _zone_w["corrupt"], f)
	var tv := ftile.x < 46.0 + ACTIVE_RADIUS and ftile.y > 75.0 - 25.0 and ftile.y < 150.0 + 25.0
	_tornado.visible = tv
	_tornado_dust.visible = tv
	# random splashes near the camera
	_splash_t -= delta
	if _splash_t <= 0.0 and not _splash_sites.is_empty():
		_splash_t = randf_range(0.15, 0.5)
		for tries in 6:
			var s: Vector3 = _splash_sites[randi() % _splash_sites.size()]
			if Vector2(s.x - f.x, s.y - f.y).length() < 22.0:
				var p := _splash_pool[_splash_next]
				_splash_next = (_splash_next + 1) % _splash_pool.size()
				p.global_position = s
				p.restart()
				p.emitting = true
				break

func _zone_frac(ftile: Vector2, zone: int) -> float:
	var n := 0
	var hit := 0
	for dy in range(-8, 9, 4):
		for dx in range(-12, 13, 4):
			n += 1
			if WorldPalette.zone_at(int(ftile.x) + dx, int(ftile.y) + dy) == zone:
				hit += 1
	return float(hit) / n

func _drive_camera_emitter(p: GPUParticles3D, w: float, f: Vector3) -> void:
	p.emitting = w > 0.05
	p.amount_ratio = clampf(w, 0.05, 1.0)
	p.global_position = Vector3(f.x, f.y + 4.0, 0.3)

func _near(center: Vector2, ftile: Vector2, r: float) -> bool:
	return center.distance_squared_to(ftile) < r * r

func _cull(ftile: Vector2) -> void:
	for c in _flame_chunks:
		c.node.visible = _near(c.center, ftile, ACTIVE_RADIUS + 6.0)
	for c in _ember_chunks:
		c.node.emitting = _near(c.center, ftile, ACTIVE_RADIUS)
	for c in _haze_chunks:
		c.node.visible = _near(c.center, ftile, ACTIVE_RADIUS * 0.8)
	for c in _mist_chunks:
		c.node.emitting = _near(c.center, ftile, ACTIVE_RADIUS)
	# assign the light pool to the nearest fire sites
	var order: Array = []
	for i in _light_sites.size():
		var p: Vector3 = _light_sites[i].pos
		var d := Vector2(p.x, -p.y).distance_squared_to(ftile)
		if d < ACTIVE_RADIUS * ACTIVE_RADIUS:
			order.append([d, i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for k in _lights.size():
		var l := _lights[k]
		if k < order.size():
			var si: int = order[k][1]
			_light_site_of[k] = si
			l.position = _light_sites[si].pos
			l.light_color = _light_sites[si].color
			l.visible = true
		else:
			_light_site_of[k] = -1
			l.visible = false

func _update_lights(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for k in _lights.size():
		var si := _light_site_of[k]
		if si < 0:
			continue
		var base: float = _light_sites[si].energy
		var fl := 0.75 + 0.15 * sin(t * 11.0 + si * 1.7) + 0.1 * sin(t * 23.0 + si * 3.1)
		_lights[k].light_energy = base * fl
