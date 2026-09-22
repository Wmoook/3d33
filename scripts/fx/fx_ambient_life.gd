class_name FxAmbientLife
extends Node3D
## Ambient creatures (purely visual): fireflies over the surface, bats roosting on cave ceilings that
## scatter from the ball, fish that dart away in the lakes (+ bubbles), moths circling fires, and
## corruption wisps that orbit the ball for a moment. CPU-driven agents in pooled MultiMeshes, spawned only
## near the camera focus. No lights.

const BAT_SHADER := preload("res://shaders/fx/bat.gdshader")
const FISH_SHADER := preload("res://shaders/fx/fish.gdshader")
const GLOW_SHADER := preload("res://shaders/fx/glow_inst.gdshader")
const PARTICLE_SHADER := preload("res://shaders/fx/particle.gdshader")

const MAX_BATS := 40
const MAX_FISH := 18
const MAX_GLOW := 96
const NEAR := 26.0          # tiles from the camera focus where life is simulated
const BUCKET := 16

var lvl: EELevel
var maps: FxOverlayMaps
var W := 0
var H := 0
var focus := Vector2(-1000, 0)     # tile space (y down)
var ball := Vector2(-1000, 0)      # tile space (y down)
var ball_vel := Vector2.ZERO
var _prev_ball := Vector2(-1000, 0)

var _open := PackedByteArray()
var _sky_top := PackedInt32Array()

# sites (tile coords), bucketed for near-camera lookup
var _roosts: Array[Vector2i] = []
var _roost_bucket := {}
var _ff_sites: Array[Vector2i] = []
var _ff_bucket := {}
var _fish_sites: Array[Vector2i] = []
var _fish_bucket := {}

var _bats: Array = []       # {site: int, pos: Vector2, vel: Vector2, state: 0 roost/1 fly/2 return, t, flap, open}
var _site_bat := {}         # roost site index -> bat index
var _fish: Array = []       # {pos, vel, flee, ph}
var _glows: Array = []      # {kind, pos, vel, life, max, ph, col, ...}
var _bat_mm: MultiMesh
var _fish_mm: MultiMesh
var _glow_mm: MultiMesh
var _bubbles: Array[GPUParticles3D] = []
var _assign_t := 0.0
var _wisp_cd := 2.0

func build(level: EELevel, overlay_maps: FxOverlayMaps) -> void:
	lvl = level
	maps = overlay_maps
	W = lvl.width
	H = lvl.height
	_open.resize(W * H)
	for y in H:
		for x in W:
			_open[y * W + x] = 1 if FxOverlayMaps.is_open(lvl, x, y) else 0
	_sky_top.resize(W)
	for x in W:
		var top := H
		for y in range(1, H):   # row 0 is the level's border
			if _open[y * W + x] == 0:
				top = y
				break
		_sky_top[x] = top
	_build_deep()
	_find_sites()
	_bat_mm = _make_mm(_bat_mesh(), BAT_SHADER, MAX_BATS, false, "Bats")
	_fish_mm = _make_mm(_fish_mesh(), FISH_SHADER, MAX_FISH, false, "Fish")
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	_glow_mm = _make_mm(q, GLOW_SHADER, MAX_GLOW, true, "Glows")
	for i in 2:
		var b := _bubble_emitter()
		add_child(b)
		_bubbles.append(b)
	print("FxAmbientLife: roosts %d, firefly sites %d, fish sites %d" % [_roosts.size(), _ff_sites.size(), _fish_sites.size()])

var _deep := PackedByteArray()

## Water tiles below a real lake surface (a surface run >= 8 tiles wide), flooded straight down the column.
func _build_deep() -> void:
	_deep.resize(W * H)
	var surf := {}
	for t in maps.water_surface:
		surf[t] = true
	for t in maps.water_surface:
		var x0 := t.x
		while surf.has(Vector2i(x0 - 1, t.y)):
			x0 -= 1
		var x1 := t.x
		while surf.has(Vector2i(x1 + 1, t.y)):
			x1 += 1
		if x1 - x0 + 1 < 8:
			continue
		var y := t.y
		while y < H and maps.water[y * W + t.x] == 1:
			_deep[y * W + t.x] = 1
			y += 1

func _deep_at(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and _deep[y * W + x] == 1

func open_at(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and _open[y * W + x] == 1

func _water(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and maps.water[y * W + x] == 1

func _find_sites() -> void:
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			var h := FxInteractiveBlocks._tile_hash(Vector2i(x, y))
			var z := WorldPalette.zone_at(x, y)
			if _open[i] == 1 and _open[i - W] == 0 and y > _sky_top[x] and z != WorldPalette.Z_SURFACE \
					and z != WorldPalette.Z_LAKE and h.x < 0.2 and not _water(x, y) 					and lvl.fg[i] == 0 and open_at(x, y + 1) and open_at(x, y + 2):
				_add_site(_roosts, _roost_bucket, Vector2i(x, y))
			if _open[i] == 1 and y < _sky_top[x] and y < 30 and h.y < 0.35:
				var ground := false
				for k in range(1, 5):
					if not open_at(x, y + k):
						ground = true
						break
				if ground:
					_add_site(_ff_sites, _ff_bucket, Vector2i(x, y))
			if _deep_at(x, y) and _deep_at(x, y - 1) and _deep_at(x - 1, y) and _deep_at(x + 1, y) and h.z < 0.3:
				_add_site(_fish_sites, _fish_bucket, Vector2i(x, y))

func _add_site(arr: Array[Vector2i], bucket: Dictionary, t: Vector2i) -> void:
	var k := Vector2i(t.x / BUCKET, t.y / BUCKET)
	if not bucket.has(k):
		bucket[k] = []
	bucket[k].append(arr.size())
	arr.append(t)

func _near_sites(arr: Array[Vector2i], bucket: Dictionary, r: float) -> Array[int]:
	var out: Array[int] = []
	var c := Vector2i(int(focus.x) / BUCKET, int(focus.y) / BUCKET)
	var br := int(ceil(r / BUCKET)) + 1
	for by in range(c.y - br, c.y + br + 1):
		for bx in range(c.x - br, c.x + br + 1):
			for idx in bucket.get(Vector2i(bx, by), []):
				if Vector2(arr[idx]).distance_to(focus) < r:
					out.append(idx)
	return out

# ------------------------------------------------------------------------------------------ meshes

func _make_mm(mesh: Mesh, shader: Shader, n: int, colors: bool, nm: String) -> MultiMesh:
	var m := ShaderMaterial.new()
	m.shader = shader
	var mesh2 := mesh.duplicate() as Mesh
	mesh2.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = colors
	mm.mesh = mesh2
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mm

func _poly(st: SurfaceTool, pts: Array, col: Color, z := 0.0) -> void:
	for i in range(1, pts.size() - 1):
		for p in [pts[0], pts[i], pts[i + 1]]:
			st.set_color(col)
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(p.x, p.y, z))

func _bat_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0, 0, 0)
	# body + head + ears
	_poly(st, [Vector2(0, -0.12), Vector2(0.05, -0.02), Vector2(0.045, 0.07), Vector2(0, 0.1), Vector2(-0.045, 0.07), Vector2(-0.05, -0.02)], body)
	_poly(st, [Vector2(0.015, 0.09), Vector2(0.045, 0.15), Vector2(0.04, 0.07)], body)
	_poly(st, [Vector2(-0.015, 0.09), Vector2(-0.04, 0.07), Vector2(-0.045, 0.15)], body)
	for s in [1.0, -1.0]:
		var wing := [Vector2(0.03, 0.05), Vector2(0.2, 0.1), Vector2(0.42, 0.14), Vector2(0.36, 0.02), Vector2(0.28, 0.0),
			Vector2(0.2, -0.05), Vector2(0.12, -0.02), Vector2(0.03, -0.05)]
		var pts := []
		for p in wing:
			pts.append(Vector2(p.x * s, p.y))
		_poly(st, pts, body)
		_poly(st, [Vector2(0.018 * s, 0.055), Vector2(0.034 * s, 0.055), Vector2(0.026 * s, 0.07)], Color(1, 0, 0), 0.004)
	return st.commit()

func _fish_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 0.2 + 0.05, sin(a) * 0.075 * (1.0 - 0.3 * cos(a))))
	_poly(st, pts, Color(0, 0, 0))
	_poly(st, [Vector2(-0.12, 0.0), Vector2(-0.26, 0.09), Vector2(-0.22, 0.0), Vector2(-0.26, -0.09)], Color(0, 0, 0))
	_poly(st, [Vector2(0.02, 0.06), Vector2(0.1, 0.11), Vector2(0.12, 0.06)], Color(0, 0, 0))
	return st.commit()

func _bubble_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 2.2
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-10, -6, -2), Vector3(20, 8, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.0, 0.4, 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.5, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	g.colors = PackedColorArray([Color(0.7, 0.9, 1.0, 0), Color(0.7, 0.9, 1.0, 0.8), Color(0.8, 0.95, 1.0, 0.8), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := ShaderMaterial.new()
	m.shader = PARTICLE_SHADER
	m.set_shader_parameter("intensity", 2.0)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ------------------------------------------------------------------------------------------ runtime

var _focus_fed := false

func set_focus(cam_world: Vector3) -> void:
	focus = Vector2(cam_world.x, -cam_world.y)
	_focus_fed = true

func set_ball(ball_world: Vector3) -> void:
	ball = Vector2(ball_world.x, -ball_world.y)

func _process(delta: float) -> void:
	if lvl == null:
		return
	if not _focus_fed:
		var cam := get_viewport().get_camera_3d()
		if cam:
			focus = Vector2(cam.global_position.x, -cam.global_position.y)
	_focus_fed = false
	delta = minf(delta, 0.05)
	if _prev_ball.x > -999.0:
		var v := (ball - _prev_ball) / maxf(delta, 1e-4)
		if v.length() < 80.0:
			ball_vel = ball_vel.lerp(v, 0.3)
	_prev_ball = ball
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = 0.3
		_assign_bats()
		_spawn_fish()
		_place_bubbles()
	_update_bats(delta)
	_update_fish(delta)
	_update_glows(delta)

# ---------------------------------------------------------------- bats

func _assign_bats() -> void:
	var near := _near_sites(_roosts, _roost_bucket, NEAR)
	var want := {}
	for idx in near:
		want[idx] = true
	# free roosting bats whose site left the area
	for i in range(_bats.size() - 1, -1, -1):
		var b: Dictionary = _bats[i]
		if b.state == 0 and not want.has(b.site):
			_site_bat.erase(b.site)
			_bats.remove_at(i)
	_site_bat.clear()
	for i in _bats.size():
		_site_bat[_bats[i].site] = i
	near.sort_custom(func(a, b): return Vector2(_roosts[a]).distance_squared_to(focus) < Vector2(_roosts[b]).distance_squared_to(focus))
	for idx in near:
		if _bats.size() >= MAX_BATS:
			break
		if _site_bat.has(idx):
			continue
		var t := _roosts[idx]
		_site_bat[idx] = _bats.size()
		_bats.append({"site": idx, "pos": _roost_pos(t), "vel": Vector2.ZERO, "state": 0, "t": 0.0,
			"flap": randf() * TAU, "open": 0.0, "ph": randf() * TAU})

func _roost_pos(t: Vector2i) -> Vector2:
	return Vector2(t.x + 0.5, t.y + 0.2)

func _scatter(b: Dictionary, from: Vector2) -> void:
	if b.state == 1:
		return
	var away: Vector2 = (b.pos - from)
	if away.length() < 0.01:
		away = Vector2(randf_range(-1, 1), 1)
	away = away.normalized()
	b.vel = (away + Vector2(randf_range(-0.6, 0.6), randf_range(-0.2, 0.9))).normalized() * randf_range(6.0, 9.0)
	b.state = 1
	b.t = randf_range(3.5, 6.0)

func _update_bats(delta: float) -> void:
	var mm := _bat_mm
	var n := 0
	var t_now := Time.get_ticks_msec() * 0.001
	for b in _bats:
		var home := _roost_pos(_roosts[b.site])
		match b.state:
			0:
				b.pos = home
				b.open = move_toward(b.open, 0.0, delta * 3.0)
				if b.pos.distance_to(ball) < 3.5:
					_scatter(b, ball)
					for o in _bats:   # the whole roost panics
						if o.state == 0 and o.pos.distance_to(b.pos) < 4.0:
							_scatter(o, ball)
			1, 2:
				b.open = move_toward(b.open, 1.0, delta * 6.0)
				b.t -= delta
				var steer := Vector2(sin(t_now * 1.7 + b.ph), cos(t_now * 1.3 + b.ph * 1.7)) * 6.0
				var db: Vector2 = b.pos - ball
				if db.length() < 5.0:
					steer += db.normalized() * 14.0
				if b.state == 2 or b.t <= 0.0:
					b.state = 2
					var to: Vector2 = home - b.pos
					steer += to.normalized() * 10.0
					if to.length() < 0.35 and db.length() > 4.0:
						b.state = 0
				b.vel += steer * delta
				var sp: float = b.vel.length()
				var maxsp: float = 8.0 if b.state == 1 else 5.0
				if sp > maxsp:
					b.vel = b.vel / sp * maxsp
				var np: Vector2 = b.pos + b.vel * delta
				if not open_at(int(np.x), int(np.y)):
					# bounce off rock
					if not open_at(int(np.x), int(b.pos.y)):
						b.vel.x = -b.vel.x
					if not open_at(int(b.pos.x), int(np.y)):
						b.vel.y = -b.vel.y
					np = b.pos + b.vel * delta
					if not open_at(int(np.x), int(np.y)):
						np = b.pos
				b.pos = np
		b.flap += delta * (22.0 if b.state != 0 else 0.0)
		var basis := Basis.IDENTITY
		if b.state == 0:
			basis = Basis(Vector3(0, 0, 1), PI + sin(t_now * 1.1 + b.ph) * 0.12)   # hang upside down, sway
		else:
			basis = Basis(Vector3(0, 0, 1), clampf(-b.vel.x * 0.05, -0.5, 0.5))
		basis = basis.scaled(Vector3.ONE * 1.8)
		var z: float = -0.25 if b.state == 0 else -0.1 + sin(b.ph + t_now) * 0.15
		mm.set_instance_transform(n, Transform3D(basis, Vector3(b.pos.x, -b.pos.y, z)))
		mm.set_instance_custom_data(n, Color(b.flap, b.open, 0, 0))
		n += 1
	mm.visible_instance_count = n

# ---------------------------------------------------------------- fish + bubbles

func _spawn_fish() -> void:
	for i in range(_fish.size() - 1, -1, -1):
		if _fish[i].pos.distance_to(focus) > NEAR + 4.0:
			_fish.remove_at(i)
	if _fish.size() >= MAX_FISH:
		return
	var near := _near_sites(_fish_sites, _fish_bucket, NEAR)
	var tries := 0
	while _fish.size() < mini(MAX_FISH, near.size() / 6 + 1) and tries < 8 and not near.is_empty():
		tries += 1
		var t: Vector2i = _fish_sites[near[randi() % near.size()]]
		var dir := 1.0 if randf() < 0.5 else -1.0
		_fish.append({"pos": Vector2(t.x + 0.5, t.y + 0.5), "vel": Vector2(dir * randf_range(0.8, 1.6), 0),
			"flee": 0.0, "ph": randf() * TAU, "face": dir, "base": randf_range(0.8, 1.6)})

func _update_fish(delta: float) -> void:
	var mm := _fish_mm
	var n := 0
	var t_now := Time.get_ticks_msec() * 0.001
	for f in _fish:
		var db: Vector2 = f.pos - ball
		if db.length() < 3.0:
			f.flee = 1.0
			f.vel = db.normalized() * 5.5 + Vector2(0, randf_range(-0.5, 0.5))
		f.flee = maxf(f.flee - delta * 0.8, 0.0)
		var target: float = f.face * f.base
		f.vel.x = lerpf(f.vel.x, target, delta * (0.6 if f.flee > 0.0 else 2.0))
		f.vel.y = lerpf(f.vel.y, sin(t_now * 0.8 + f.ph) * 0.3, delta * 1.5)
		var np: Vector2 = f.pos + f.vel * delta
		if not _deep_at(int(np.x), int(np.y)) or not _deep_at(int(np.x), int(np.y) - 1):
			f.face = -signf(f.vel.x) if absf(f.vel.x) > 0.05 else -f.face
			f.vel = Vector2(f.face * f.base, -f.vel.y)
			np = f.pos
		f.pos = np
		if absf(f.vel.x) > 0.2:
			f.face = signf(f.vel.x)
		var basis := Basis.IDENTITY.scaled(Vector3(f.face * 2.1, 2.1, 2.1))
		basis = Basis(Vector3(0, 0, 1), clampf(-f.vel.y * 0.25 * f.face, -0.5, 0.5)) * basis
		mm.set_instance_transform(n, Transform3D(basis, Vector3(f.pos.x, -f.pos.y, 0.92)))
		mm.set_instance_custom_data(n, Color(f.ph, f.flee, 0, 0))
		n += 1
	mm.visible_instance_count = n

func _place_bubbles() -> void:
	# two nearest long water-surface runs get a bubble column
	var runs: Array = []
	for t in maps.water_surface:
		if maps.water_surface.has(t + Vector2i(-1, 0)):
			continue
		var d := Vector2(t).distance_to(focus)
		if d < NEAR:
			runs.append([d, t])
	runs.sort_custom(func(a, b): return a[0] < b[0])
	for i in _bubbles.size():
		var p := _bubbles[i]
		if i < runs.size():
			var t: Vector2i = runs[i][1]
			p.position = Vector3(t.x + 5.0, -t.y - 3.2, 0.3)
			p.emitting = true
		else:
			p.emitting = false

# ---------------------------------------------------------------- glows: fireflies, moths, wisps

func _count(kind: int) -> int:
	var c := 0
	for g in _glows:
		if g.kind == kind:
			c += 1
	return c

func _update_glows(delta: float) -> void:
	var t_now := Time.get_ticks_msec() * 0.001
	# fireflies
	if _count(0) < 34:
		var near := _near_sites(_ff_sites, _ff_bucket, NEAR * 0.8)
		if not near.is_empty() and randf() < 0.5:
			var t: Vector2i = _ff_sites[near[randi() % near.size()]]
			_glows.append({"kind": 0, "pos": Vector2(t.x + randf(), t.y + randf()), "vel": Vector2.ZERO,
				"life": 0.0, "max": randf_range(5.0, 10.0), "ph": randf() * TAU, "col": Color(0.75, 1.0, 0.35)})
	# moths around fires
	if _count(1) < 18 and maps.fire_chunks.size() > 0 and randf() < 0.5:
		var cands: Array = []
		for ch in maps.fire_chunks:
			if (ch.center as Vector2).distance_to(focus) < 14.0:
				cands.append(ch)
		if not cands.is_empty():
			var best: Dictionary = cands[randi() % cands.size()]
			var top := Vector2(randf_range(best.min.x, best.max.x + 1.0), float(best.min.y) - 1.8)
			_glows.append({"kind": 1, "pos": top, "vel": Vector2.ZERO, "life": 0.0, "max": randf_range(6.0, 12.0),
				"ph": randf() * TAU, "col": Color(1.0, 0.72, 0.42), "home": top, "r": randf_range(0.5, 1.3)})
	# corruption wisps orbit the ball for a moment
	_wisp_cd -= delta
	if _wisp_cd <= 0.0 and WorldPalette.zone_at(int(ball.x), int(ball.y)) == WorldPalette.Z_CORRUPT:
		_wisp_cd = randf_range(7.0, 11.0)
		for k in 5:
			_glows.append({"kind": 2, "pos": ball + Vector2.from_angle(TAU * k / 5.0) * 2.0, "vel": Vector2.ZERO,
				"life": 0.0, "max": randf_range(3.5, 5.0), "ph": TAU * k / 5.0,
				"col": Color(0.85, 0.45, 1.0) if k % 2 == 0 else Color(1.0, 0.5, 0.85)})
	var mm := _glow_mm
	var n := 0
	for i in range(_glows.size() - 1, -1, -1):
		var g: Dictionary = _glows[i]
		g.life += delta
		if g.life > g.max or g.pos.distance_to(focus) > NEAR + 6.0:
			_glows.remove_at(i)
			continue
		var fade: float = smoothstep(0.0, 0.8, g.life) * (1.0 - smoothstep(g.max - 1.0, g.max, g.life))
		var bright := 1.0
		var size := 0.5
		match g.kind:
			0:
				var wander := Vector2(sin(t_now * 0.9 + g.ph) + sin(t_now * 2.3 + g.ph * 3.0) * 0.5,
					cos(t_now * 0.7 + g.ph * 1.3) * 0.8) * 0.9
				var db: Vector2 = g.pos - ball
				if db.length() < 2.5:
					wander += db.normalized() * 6.0 * (2.5 - db.length())
				g.vel = g.vel.lerp(wander, delta * 2.0)
				bright = pow(0.5 + 0.5 * sin(t_now * 2.2 + g.ph * 5.0), 3.0) * 1.2 + 0.08
				size = 0.45
			1:
				var ang: float = t_now * (3.0 + sin(g.ph) * 1.5) + g.ph
				var target: Vector2 = g.home + Vector2(cos(ang) * g.r, sin(ang * 1.3) * g.r * 0.6)
				target += Vector2(sin(t_now * 13.0 + g.ph), cos(t_now * 11.0 + g.ph)) * 0.15
				var db: Vector2 = g.pos - ball
				if db.length() < 1.5:
					target += db.normalized() * 2.0
				g.vel = (target - g.pos) * 6.0
				bright = 1.0 + 0.4 * sin(t_now * 30.0 + g.ph)
				size = 0.6
			2:
				var orbit: bool = g.life < g.max - 1.3
				var ang: float = g.ph + g.life * 3.2
				var r: float = 1.15 + 0.25 * sin(g.life * 2.0 + g.ph)
				if orbit:
					var target: Vector2 = ball + Vector2(cos(ang), sin(ang) * 0.8) * r
					g.vel = (target - g.pos) * 7.0 + ball_vel * 0.5
				else:
					g.vel = g.vel.lerp((g.pos - ball).normalized() * 3.0 + Vector2(0, -1.2), delta * 2.0)
				bright = 1.3 + 0.4 * sin(t_now * 7.0 + g.ph)
				size = 0.75
		g.pos += g.vel * delta
		if n >= MAX_GLOW:
			continue
		var z: float = 0.3 if g.kind != 2 else 0.35 + sin(g.ph + g.life * 3.2) * 0.3
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3(g.pos.x, -g.pos.y, z)))
		var col: Color = g.col
		col.a = bright * fade
		mm.set_instance_color(n, col)
		n += 1
	mm.visible_instance_count = n
