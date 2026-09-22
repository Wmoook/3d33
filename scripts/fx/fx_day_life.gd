class_name FxDayLife
extends Node3D
## Daytime creatures for non-Odyssey levels (same pooled, near-camera, CPU-agent framework as FxAmbientLife):
## butterflies fluttering around flowers and canopies that scatter from the ball, songbirds perched on
## sunlit ledges that take off when the ball comes close, and distant flocks crossing the sky far behind
## the playfield. Purely visual; sites come from the level art (FxVeil foliage + sky visibility).

const SHADER := preload("res://shaders/fx/wing_creature.gdshader")
const MAX_BUTTERFLIES := 14
const MAX_BIRDS := 12
const MAX_FLOCK := 18
const NEAR := 26.0
const BUCKET := 16
## wing hues (negative = white)
const BUTTERFLY_HUES := [0.08, 0.12, 0.6, -1.0, 0.95, 0.15]

var lvl: EELevel
var veil: FxVeil
var W := 0
var H := 0
var focus := Vector2(-1000, 0)
var ball := Vector2(-1000, 0)

var _bfly_sites: Array[Vector2i] = []
var _bfly_bucket := {}
var _perch_sites: Array[Vector2i] = []
var _perch_bucket := {}
var _bflies: Array = []    # {home, pos, vel, ph, hue, flee, t}
var _birds: Array = []     # {site, pos, vel, state 0 perched/1 flying, ph, face, t, peck}
var _used_perch := {}
var _flock: Array = []     # {pos: Vector3, vel, ph}
var _flock_t := 4.0
var _bfly_mm: MultiMesh
var _bird_mm: MultiMesh
var _flock_mm: MultiMesh
var _assign_t := 0.0
var _focus_fed := false

func build(level: EELevel, fx_veil: FxVeil) -> void:
	lvl = level
	veil = fx_veil
	W = lvl.width
	H = lvl.height
	_find_sites()
	_bfly_mm = _make_mm(_butterfly_mesh(), MAX_BUTTERFLIES, "Butterflies")
	_bird_mm = _make_mm(_bird_mesh(), MAX_BIRDS, "Birds")
	_flock_mm = _make_mm(_bird_mesh(), MAX_FLOCK, "Flock")
	print("FxDayLife: butterfly sites %d, perches %d" % [_bfly_sites.size(), _perch_sites.size()])

func _open(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and FxOverlayMaps.is_open(lvl, x, y)

func _find_sites() -> void:
	for y in range(2, H - 2):
		for x in range(1, W - 1):
			if not _open(x, y):
				continue
			var h := FxInteractiveBlocks._tile_hash(Vector2i(x, y))
			var near_leaf := false
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 2)]:
				if veil.is_foliage(x + d.x, y + d.y):
					near_leaf = true
					break
			if near_leaf and h.x < 0.08 and (veil.sunny(x, y) or h.y < 0.3):
				_add(_bfly_sites, _bfly_bucket, Vector2i(x, y))
			# perch: sunlit open tile standing on solid ground with a little headroom
			if veil.sunny(x, y) and not _open(x, y + 1) and _open(x, y - 1) and h.z < 0.045:
				_add(_perch_sites, _perch_bucket, Vector2i(x, y))

func _add(arr: Array[Vector2i], bucket: Dictionary, t: Vector2i) -> void:
	var k := Vector2i(t.x / BUCKET, t.y / BUCKET)
	if not bucket.has(k):
		bucket[k] = []
	bucket[k].append(arr.size())
	arr.append(t)

func _near(arr: Array[Vector2i], bucket: Dictionary, r: float) -> Array[int]:
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

func _make_mm(mesh: Mesh, n: int, nm: String) -> MultiMesh:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mm

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	for v in [[a, ca], [b, cb], [c, cc]]:
		st.set_color(v[1])
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(v[0])

## Butterfly (~0.34 wide): dark body, two wings per side (fore + hind) with a dark rim and bright field.
func _butterfly_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0, -1.0]:
		var fore := [Vector2(0.01, 0.01), Vector2(0.06, 0.1), Vector2(0.15, 0.13), Vector2(0.17, 0.07), Vector2(0.12, 0.0)]
		var hind := [Vector2(0.01, -0.005), Vector2(0.1, -0.01), Vector2(0.12, -0.07), Vector2(0.07, -0.12), Vector2(0.02, -0.07)]
		for wing in [fore, hind]:
			var c := Vector2.ZERO
			for p in wing:
				c += p
			c /= wing.size()
			for i in wing.size():
				var a: Vector2 = wing[i]
				var b: Vector2 = wing[(i + 1) % wing.size()]
				# rim triangle (dark) + inner field (tinted)
				var ai := c.lerp(a, 0.72)
				var bi := c.lerp(b, 0.72)
				var wa := absf(a.x) / 0.17
				var wb := absf(b.x) / 0.17
				var wc := absf(c.x) / 0.17
				var dark_a := Color(wa, 0.0, 0)
				var dark_b := Color(wb, 0.0, 0)
				_tri(st, Vector3(c.x * s, c.y, 0), Vector3(ai.x * s, ai.y, 0), Vector3(bi.x * s, bi.y, 0),
					Color(wc, 1, 0), Color(wa * 0.72, 1, 0), Color(wb * 0.72, 1, 0))
				_tri(st, Vector3(ai.x * s, ai.y, 0), Vector3(a.x * s, a.y, 0), Vector3(b.x * s, b.y, 0),
					Color(wa * 0.72, 0.15, 0), dark_a, dark_b)
				_tri(st, Vector3(ai.x * s, ai.y, 0), Vector3(b.x * s, b.y, 0), Vector3(bi.x * s, bi.y, 0),
					Color(wa * 0.72, 0.15, 0), dark_b, Color(wb * 0.72, 0.15, 0))
	var body := Color(0, 0, 0)
	_tri(st, Vector3(-0.012, 0.07, 0.003), Vector3(0.012, 0.07, 0.003), Vector3(0.0, -0.09, 0.003), body, body, body)
	_tri(st, Vector3(-0.004, 0.07, 0.003), Vector3(-0.03, 0.12, 0.003), Vector3(-0.002, 0.075, 0.003), body, body, body)
	_tri(st, Vector3(0.004, 0.07, 0.003), Vector3(0.002, 0.075, 0.003), Vector3(0.03, 0.12, 0.003), body, body, body)
	return st.commit()

## Songbird silhouette facing +x (~0.4 wide): body, head, beak, tail and two swept wings.
func _bird_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := Color(0, 0, 0)
	var body := [Vector2(-0.12, 0.0), Vector2(-0.04, 0.05), Vector2(0.06, 0.05), Vector2(0.11, 0.02), Vector2(0.08, -0.03), Vector2(-0.04, -0.04)]
	for i in range(1, body.size() - 1):
		_tri(st, Vector3(body[0].x, body[0].y, 0), Vector3(body[i].x, body[i].y, 0), Vector3(body[i + 1].x, body[i + 1].y, 0), b, b, b)
	_tri(st, Vector3(0.1, 0.05, 0), Vector3(0.1, 0.0, 0), Vector3(0.16, 0.03, 0), b, b, b)       # beak
	_tri(st, Vector3(-0.1, 0.01, 0), Vector3(-0.22, 0.05, 0), Vector3(-0.2, -0.03, 0), b, b, b)   # tail
	# wings: the shader beats vertices by |x| * COLOR.r, so the wing is spread along x at the shoulders
	var w0 := Color(0, 0, 0)
	var w1 := Color(1, 0, 0)
	_tri(st, Vector3(-0.04, 0.04, 0.01), Vector3(0.04, 0.04, 0.01), Vector3(-0.1, 0.2, 0.01), w0, w0, w1)
	_tri(st, Vector3(0.04, 0.04, 0.01), Vector3(0.02, 0.2, 0.01), Vector3(-0.1, 0.2, 0.01), w0, w1, w1)
	return st.commit()

# ------------------------------------------------------------------------------------------ runtime

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
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = 0.4
		_spawn_butterflies()
		_spawn_birds()
	var t := Time.get_ticks_msec() * 0.001
	_update_butterflies(delta, t)
	_update_birds(delta, t)
	_update_flock(delta, t)

func _spawn_butterflies() -> void:
	for i in range(_bflies.size() - 1, -1, -1):
		if (_bflies[i].pos as Vector2).distance_to(focus) > NEAR + 6.0:
			_bflies.remove_at(i)
	var near := _near(_bfly_sites, _bfly_bucket, NEAR)
	var want := mini(MAX_BUTTERFLIES, near.size() / 3 + (1 if near.size() > 0 else 0))
	var tries := 0
	while _bflies.size() < want and tries < 6:
		tries += 1
		var s: Vector2i = _bfly_sites[near[randi() % near.size()]]
		var home := Vector2(s.x + 0.5, s.y + 0.3)
		_bflies.append({"home": home, "pos": home + Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)),
			"vel": Vector2.ZERO, "ph": randf() * TAU, "hue": BUTTERFLY_HUES[randi() % BUTTERFLY_HUES.size()],
			"flee": 0.0, "rate": randf_range(15.0, 20.0)})

func _update_butterflies(delta: float, t: float) -> void:
	var n := 0
	for b in _bflies:
		var db: Vector2 = b.pos - ball
		if db.length() < 2.2 and b.flee <= 0.0:
			b.flee = randf_range(2.5, 4.0)
			b.vel = (db.normalized() + Vector2(0, -1.2)).normalized() * 4.5
		var target: Vector2 = b.home + Vector2(sin(t * 0.7 + b.ph) * 1.6, sin(t * 1.1 + b.ph * 2.0) * 0.8 - 0.4)
		if b.flee > 0.0:
			b.flee -= delta
			target = b.pos + b.vel
		# erratic flutter: a jittery pull toward the wander target
		var jit := Vector2(sin(t * 9.0 + b.ph * 3.0), cos(t * 7.3 + b.ph * 5.0)) * 1.6
		b.vel = b.vel.lerp((target - b.pos) * 1.2 + jit, delta * 3.0)
		var np: Vector2 = b.pos + b.vel * delta
		if _open(int(np.x), int(np.y)):
			b.pos = np
		else:
			b.vel = -b.vel * 0.5
		b.ph += delta * b.rate
		var face := 1.0 if b.vel.x >= 0.0 else -1.0
		var basis := Basis(Vector3(0, 0, 1), clampf(-b.vel.x * 0.08, -0.4, 0.4)) * Basis.IDENTITY.scaled(Vector3(face, 1, 1) * 1.6)
		_bfly_mm.set_instance_transform(n, Transform3D(basis, Vector3(b.pos.x, -b.pos.y, 0.35)))
		_bfly_mm.set_instance_custom_data(n, Color(b.ph, b.hue, 0.0, 1.0))
		n += 1
	_bfly_mm.visible_instance_count = n

func _spawn_birds() -> void:
	for i in range(_birds.size() - 1, -1, -1):
		var b: Dictionary = _birds[i]
		var gone: bool = (b.pos as Vector2).distance_to(focus) > NEAR + 10.0
		if gone or (b.state == 1 and b.t <= 0.0):
			_used_perch.erase(b.site)
			_birds.remove_at(i)
	var near := _near(_perch_sites, _perch_bucket, NEAR)
	near.shuffle()
	for idx in near:
		if _birds.size() >= MAX_BIRDS:
			break
		if _used_perch.has(idx):
			continue
		var s := _perch_sites[idx]
		# never pop in right next to the ball
		if Vector2(s).distance_to(ball) < 7.0:
			continue
		_used_perch[idx] = true
		_birds.append({"site": idx, "pos": Vector2(s.x + 0.5, s.y + 0.92), "vel": Vector2.ZERO, "state": 0,
			"ph": randf() * TAU, "face": 1.0 if randf() < 0.5 else -1.0, "t": 0.0, "peck": randf() * 3.0})

func _update_birds(delta: float, t: float) -> void:
	var n := 0
	for b in _birds:
		var amp := 0.0
		var tilt := 0.0
		if b.state == 0:
			b.peck -= delta
			if b.peck < 0.0:
				b.peck = randf_range(1.2, 3.5)
				if randf() < 0.35:
					b.face = -b.face
			if b.peck < 0.25:   # quick peck: dip the head forward and back
				tilt = -0.5 * sin((0.25 - b.peck) * 4.0 * PI) * b.face
			if (b.pos as Vector2).distance_to(ball) < 4.5:
				b.state = 1
				b.t = 5.0
				var away: Vector2 = (b.pos - ball)
				away.x = signf(away.x) if absf(away.x) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
				b.vel = Vector2(away.x * randf_range(3.0, 5.0), -randf_range(4.0, 6.0))
				b.face = signf(b.vel.x)
		else:
			b.t -= delta
			b.vel += Vector2(b.face * 2.0, -1.5) * delta
			b.vel = b.vel.limit_length(9.0)
			b.pos += b.vel * delta
			b.ph += delta * 20.0
			amp = 1.0
			tilt = clampf(-b.vel.y * 0.04, -0.4, 0.4) * b.face
		var basis := Basis(Vector3(0, 0, 1), tilt) * Basis.IDENTITY.scaled(Vector3(b.face, 1, 1) * 1.5)
		_bird_mm.set_instance_transform(n, Transform3D(basis, Vector3(b.pos.x, -b.pos.y, 0.2)))
		_bird_mm.set_instance_custom_data(n, Color(b.ph, 0.0, 1.0, amp))
		n += 1
	_bird_mm.visible_instance_count = n

## Distant flocks: a loose V of silhouettes crossing the sky far behind the playfield, only when the
## camera sees open sky.
func _update_flock(delta: float, t: float) -> void:
	_flock_t -= delta
	if _flock.is_empty() and _flock_t <= 0.0:
		_flock_t = randf_range(10.0, 22.0)
		if veil.sunny(int(focus.x), int(focus.y) - 8):
			var dir := 1.0 if randf() < 0.5 else -1.0
			var z := randf_range(-16.0, -10.0)
			var start := Vector3(focus.x - dir * 34.0, -(focus.y - randf_range(8.0, 14.0)), z)
			var count := randi_range(5, 9)
			for i in count:
				var row := (i + 1) / 2
				var side := 1.0 if i % 2 == 0 else -1.0
				_flock.append({"pos": start + Vector3(-dir * row * 1.1, side * row * 0.55, 0), "vel": Vector3(dir * randf_range(4.5, 5.2), 0, 0),
					"ph": randf() * TAU, "face": dir})
	var n := 0
	for i in range(_flock.size() - 1, -1, -1):
		var b: Dictionary = _flock[i]
		b.pos += b.vel * delta + Vector3(0, sin(t * 0.8 + b.ph) * 0.3 * delta, 0)
		b.ph += delta * 11.0
		if absf(b.pos.x - focus.x) > 48.0 and signf(b.pos.x - focus.x) == signf(b.vel.x):
			_flock.remove_at(i)
	for b in _flock:
		if n >= MAX_FLOCK:
			break
		var basis := Basis.IDENTITY.scaled(Vector3(b.face, 1, 1) * 2.4)
		_flock_mm.set_instance_transform(n, Transform3D(basis, b.pos))
		_flock_mm.set_instance_custom_data(n, Color(b.ph, 0.0, 1.0, 1.0))
		n += 1
	_flock_mm.visible_instance_count = n
