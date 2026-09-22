class_name FxVeil
extends Node3D
## Daylight scenic FX for levels other than Odyssey (first: Forgotten Veil), all derived from the level's
## own art via FxOverlayMaps: waterfalls (foaming falling sheet over every tall narrow water column, mist
## and spray at the base, splash rings where it plunges into a pool), sunbeam dust motes in sunlit air,
## and drifting leaves / petals under the tree canopies. Expensive pieces are chunked and switched by
## distance to the camera focus.

const FALL_SHADER := preload("res://shaders/fx/waterfall.gdshader")
const MIX_SHADER := preload("res://shaders/fx/soft_mix.gdshader")
const RING_SHADER := preload("res://shaders/fx/splash_ring.gdshader")
const LEAF_SHADER := preload("res://shaders/fx/leaf.gdshader")
const PARTICLE_SHADER := preload("res://shaders/fx/particle.gdshader")

const Z_SHEET := 0.9          # just in front of the terrain face (overlay field is 0.86)
const ACTIVE_RADIUS := 36.0
const CULL_PERIOD := 0.25
const CHUNK := 12

var lvl: EELevel
var maps: FxOverlayMaps
var W := 0
var H := 0
var _sky_top := PackedInt32Array()
var _foliage := PackedByteArray()
var _falls: Array = []        # [{center: Vector2, sheet, mist, spray, ring}]
var _fall_mats: Array[ShaderMaterial] = []
var _leaf_chunks: Array = []  # [{node, center}]
var _motes: GPUParticles3D
var _mote_w := 0.0
var _cull_t := 0.0
var focus_override := Vector3(INF, 0, 0)

func build(level: EELevel, overlay_maps: FxOverlayMaps) -> void:
	lvl = level
	maps = overlay_maps
	W = lvl.width
	H = lvl.height
	var t0 := Time.get_ticks_msec()
	_sky_top.resize(W)
	for x in W:
		var top := H
		for y in range(1, H):
			if not FxOverlayMaps.is_open(lvl, x, y):
				top = y
				break
		_sky_top[x] = top
	_find_foliage()
	_build_falls()
	_build_leaves()
	_motes = _mote_emitter()
	add_child(_motes)
	print("FxVeil: %d ms, falls %d, leaf chunks %d" % [Time.get_ticks_msec() - t0, _falls.size(), _leaf_chunks.size()])

func sunny(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < _sky_top[x]

## Canopy / grass pixels of the painting (green minimap hues), fg or bg.
func _find_foliage() -> void:
	_foliage.resize(W * H)
	for y in H:
		for x in W:
			var c := maps.img.get_pixel(x, y)
			if c.s > 0.35 and c.h > 0.2 and c.h < 0.45 and c.v > 0.2:
				_foliage[y * W + x] = 1

func is_foliage(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and _foliage[y * W + x] == 1

# ------------------------------------------------------------------------------------------ waterfalls

func _build_falls() -> void:
	var seen := {}
	for t0 in maps.stream_tiles:
		if seen.has(t0):
			continue
		# 8-connected cluster with a 1-tile gap tolerance (painted falls are dithered)
		var comp: Array[Vector2i] = []
		var stack: Array[Vector2i] = [t0]
		seen[t0] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var n := c + Vector2i(dx, dy)
					if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or seen.has(n):
						continue
					if maps.stream[n.y * W + n.x] == 1:
						seen[n] = true
						stack.append(n)
		if comp.size() >= 12:
			_build_fall(comp)

func _build_fall(comp: Array[Vector2i]) -> void:
	var rows := {}
	var y0 := H
	var y1 := -1
	for t in comp:
		if not rows.has(t.y):
			rows[t.y] = [] as Array[int]
		rows[t.y].append(t.x)
		y0 = mini(y0, t.y)
		y1 = maxi(y1, t.y)
	if y1 - y0 < 5:
		return
	# the lip: the water feeding the column from above (a channel row) joins the sheet
	var lip := y0
	if y0 > 0:
		for x in rows[y0]:
			if maps.water[(y0 - 1) * W + x] == 1:
				lip = y0 - 1
				break
	# follow the column's core down (painted falls are dithered and sprout splash bits sideways): per row keep
	# the stream tiles within 3 tiles of the running centre, at most ~4 tiles wide; gaps keep the last extent
	var c := 0.0
	for x in rows[y0]:
		c += x + 0.5
	c /= rows[y0].size()
	var ext: Array[Vector2] = []
	var last := Vector2(c - 1.0, c + 1.0)
	for y in range(y0, y1 + 1):
		if rows.has(y):
			var lo := INF
			var hi := -INF
			for x in rows[y]:
				if absf(x + 0.5 - c) <= 3.0:
					lo = minf(lo, float(x))
					hi = maxf(hi, x + 1.0)
			if lo < INF:
				var mid := (lo + hi) * 0.5
				var half := minf((hi - lo) * 0.5, 2.2)
				last = Vector2(mid - half, mid + half)
				c = lerpf(c, mid, 0.35)
		ext.append(last)
	var sm: Array[Vector2] = []
	for i in ext.size():
		var a := Vector2.ZERO
		var n := 0
		for k in range(-3, 4):
			var j := clampi(i + k, 0, ext.size() - 1)
			a += ext[j]
			n += 1
		sm.append(a / n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := float(y1 + 1 - lip)
	var prev_l := sm[0].x - 0.15
	var prev_r := sm[0].y + 0.15
	var prev_y := float(lip)
	for i in sm.size():
		var yb := float(y0 + i + 1)
		var l := sm[i].x - 0.15
		var r := sm[i].y + 0.15
		var ka := (prev_y - lip) / total
		var kb := (yb - lip) / total
		var quad := [[prev_l, prev_y, 0.0, ka], [prev_r, prev_y, 1.0, ka], [r, yb, 1.0, kb],
			[prev_l, prev_y, 0.0, ka], [r, yb, 1.0, kb], [l, yb, 0.0, kb]]
		for v in quad:
			st.set_color(Color(v[3], 0, 0))
			st.set_uv(Vector2(v[2], v[1]))
			st.add_vertex(Vector3(v[0], -v[1], Z_SHEET))
		prev_l = l
		prev_r = r
		prev_y = yb
	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = FALL_SHADER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_fall_mats.append(m)
	# plunge point: the bottom row centre; the pool surface is the first water body tile below it
	var bot := sm[sm.size() - 1]
	var cx := (bot.x + bot.y) * 0.5
	var width := maxf(bot.y - bot.x, 1.5)
	var py := float(y1 + 1)
	for k in range(0, 6):
		if maps.water[mini(y1 + 1 + k, H - 1) * W + int(cx)] == 1:
			py = float(y1 + 1 + k)
			break
	var base := Vector3(cx, -py, 0.0)
	var mist := _mist(width)
	mist.position = base + Vector3(0, 0.4, 0.5)
	add_child(mist)
	var spray := _spray(width)
	spray.position = base + Vector3(0, 0.1, 0.6)
	add_child(spray)
	var veil := _fall_mist(float(y1 - lip))
	veil.position = Vector3((sm[0].x + sm[0].y) * 0.5, -(lip + y1) * 0.5, 0.95)
	add_child(veil)
	var ring := MeshInstance3D.new()
	ring.name = "SplashRing"
	var q := QuadMesh.new()
	q.size = Vector2(width + 5.0, 1.6)
	ring.mesh = q
	var rm := ShaderMaterial.new()
	rm.shader = RING_SHADER
	ring.material_override = rm
	ring.position = base + Vector3(0, 0.05, 0.97)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_falls.append({"center": Vector2(cx, (lip + y1) * 0.5), "sheet": mi, "mist": mist, "spray": spray,
		"veil": veil, "ring": ring, "h": y1 - lip})

func _ramp(cols: Array, offs: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t

func _mix_sprite(size: float, opacity := 1.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = MIX_SHADER
	m.set_shader_parameter("opacity", opacity)
	q.material = m
	return q

## Billowing white mist at the plunge point.
func _mist(width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FallMist"
	p.amount = 36
	p.lifetime = 3.2
	p.preprocess = 3.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-10, -3, -3), Vector3(20, 10, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5 + 0.5, 0.3, 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.scale_curve = _curve([Vector2(0, 0.35), Vector2(1, 1.6)])
	pm.color_ramp = _ramp([Color(0.92, 0.96, 1.0, 0), Color(0.92, 0.96, 1.0, 0.42), Color(0.9, 0.95, 1.0, 0)], [0.0, 0.2, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _mix_sprite(2.0, 0.9)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Droplets flung up and out of the plunge.
func _spray(width: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FallSpray"
	p.amount = 60
	p.lifetime = 1.0
	p.preprocess = 1.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(Vector3(-8, -2, -3), Vector3(16, 8, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.1, 0.2)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -11, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(0.95, 0.98, 1.0, 0.95), Color(0.85, 0.93, 1.0, 0)], [0.0, 1.0])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.2)
	var m := ShaderMaterial.new()
	m.shader = MIX_SHADER
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Thin drifting spray veil along the whole fall.
func _fall_mist(height: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FallVeil"
	p.amount = clampi(int(height * 0.8), 8, 40)
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-6, -height, -3), Vector3(12, height * 2.0, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.6, height * 0.5, 0.3)
	pm.direction = Vector3(1, -0.4, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -0.3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.3)])
	pm.color_ramp = _ramp([Color(0.9, 0.95, 1.0, 0), Color(0.9, 0.95, 1.0, 0.2), Color(0.9, 0.95, 1.0, 0)], [0.0, 0.3, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _mix_sprite(1.4, 0.8)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ------------------------------------------------------------------------------------------ leaves

## Leaf fall under canopies: foliage chunks with open air beneath them.
func _build_leaves() -> void:
	var bins := {}
	for y in range(1, H - 1):
		for x in W:
			if not is_foliage(x, y):
				continue
			if not (FxOverlayMaps.is_open(lvl, x, y + 1) and not is_foliage(x, y + 1)):
				continue
			var key := Vector2i(x / CHUNK, y / CHUNK)
			if not bins.has(key):
				bins[key] = {"n": 0, "sum": Vector2.ZERO, "min": Vector2i(9999, 9999), "max": Vector2i(-1, -1)}
			var b: Dictionary = bins[key]
			b.n += 1
			b.sum += Vector2(x + 0.5, y + 1.0)
			b.min = Vector2i(mini(b.min.x, x), mini(b.min.y, y))
			b.max = Vector2i(maxi(b.max.x, x), maxi(b.max.y, y))
	for key in bins:
		var b: Dictionary = bins[key]
		if b.n < 4:
			continue
		var c: Vector2 = b.sum / b.n
		var wdt := float(b.max.x - b.min.x + 1)
		var e := _leaf_emitter(wdt, b.n)
		e.position = Vector3((b.min.x + b.max.x + 1) * 0.5, -c.y, -0.1)
		e.emitting = false
		add_child(e)
		_leaf_chunks.append({"node": e, "center": c})

func _leaf_emitter(width: float, n: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Leaves"
	p.amount = clampi(int(n * 0.5), 3, 14)
	p.lifetime = 7.0
	p.preprocess = 6.0
	p.randomness = 0.6
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-width - 4, -14, -3), Vector3(width * 2 + 8, 16, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.3, 0.8)
	pm.direction = Vector3(0.4, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.35, -0.55, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.15
	pm.turbulence_influence_max = 0.35
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 0), Vector2(0.08, 1), Vector2(0.85, 1), Vector2(1, 0)])
	# mostly greens and a few sun-bleached yellows; ~1 in 6 is a pale pink petal
	pm.color_initial_ramp = _ramp([Color(0.3, 0.55, 0.12), Color(0.45, 0.68, 0.16), Color(0.7, 0.72, 0.2),
		Color(0.36, 0.6, 0.14), Color(1.0, 0.72, 0.82), Color(1.0, 0.9, 0.94)], [0.0, 0.3, 0.55, 0.8, 0.84, 1.0])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.3)
	var m := ShaderMaterial.new()
	m.shader = LEAF_SHADER
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ------------------------------------------------------------------------------------------ sun motes

func _mote_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SunMotes"
	p.amount = 160
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emitting = false
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-40, -30, -6), Vector3(80, 60, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 16, 1.5)
	pm.direction = Vector3(1, 0.2, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0.05, -0.03, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.color = Color(1.0, 0.92, 0.7)
	pm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.2, 0.8, 1.0])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := ShaderMaterial.new()
	m.shader = PARTICLE_SHADER
	m.set_shader_parameter("intensity", 1.6)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ------------------------------------------------------------------------------------------ runtime

func set_ball(p: Vector3) -> void:
	for m in _fall_mats:
		m.set_shader_parameter("ball_pos", p)

func _process(delta: float) -> void:
	var f := focus_override
	if f.x == INF:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		f = cam.global_position
	var ft := Vector2(f.x, -f.y)
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = CULL_PERIOD
		for c in _leaf_chunks:
			c.node.emitting = (c.center as Vector2).distance_to(ft) < ACTIVE_RADIUS
		for fl in _falls:
			var near: bool = (fl.center as Vector2).distance_to(ft) < ACTIVE_RADIUS + fl.h * 0.5
			fl.mist.emitting = near
			fl.spray.emitting = near
			fl.veil.emitting = near
	# dust motes fade in with the share of sunlit open air around the camera
	var n := 0
	var hit := 0
	for dy in range(-12, 13, 4):
		for dx in range(-16, 17, 4):
			var x := int(ft.x) + dx
			var y := int(ft.y) + dy
			n += 1
			if sunny(x, y):
				hit += 1
	_mote_w = move_toward(_mote_w, float(hit) / n, delta * 0.5)
	_motes.emitting = _mote_w > 0.05
	_motes.amount_ratio = clampf(_mote_w, 0.05, 1.0)
	_motes.global_position = Vector3(f.x, f.y - 2.0, 0.4)
