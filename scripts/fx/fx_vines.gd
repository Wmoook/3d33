class_name FxVines
extends Node3D
## Dynamic hanging vines for day levels (purely visual): sparse verlet strands hang from the undersides of
## vine / leaf painted tiles into open air, sway in a gentle gusting wind and part around the ball when it
## passes through. They live just in front of the back wall and behind the ball (Z), never cross a tile that
## holds a gameplay block, and are pooled near the camera: only strands within NEAR tiles are simulated.

const STRAND_SHADER := preload("res://shaders/fx/vine_strand.gdshader")
const LEAF_SHADER := preload("res://shaders/fx/vine_leaf.gdshader")
const Z := -0.32
const NEAR := 30.0
const MAX_STRANDS := 120
const NODES := 8
const MAX_LEAVES_PER := 8
const BUCKET := 16
const BALL_R := 0.62

var lvl: EELevel
var veil: FxVeil
var W := 0
var H := 0
var focus := Vector2(-1000, 0)
var ball := Vector2(-1000, 0)       # world xy (y up)
var _prev_ball := Vector2(-1000, 0)
var _sites: Array[Vector3] = []    # x, y (anchor, world), length in tiles
var _bucket := {}
var _active := {}                  # site index -> strand
var _seg_mm: MultiMesh
var _leaf_mm: MultiMesh
var _assign_t := 0.0
var _focus_fed := false

func build(level: EELevel, fx_veil: FxVeil) -> void:
	lvl = level
	veil = fx_veil
	W = lvl.width
	H = lvl.height
	_find_sites()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, -0.5, 0)
	var sm := ShaderMaterial.new()
	sm.shader = STRAND_SHADER
	q.material = sm
	_seg_mm = _mm(q, MAX_STRANDS * (NODES - 1), "VineStrands")
	var lq := QuadMesh.new()
	lq.size = Vector2(1, 1)
	lq.center_offset = Vector3(0, -0.5, 0)
	var lm := ShaderMaterial.new()
	lm.shader = LEAF_SHADER
	lq.material = lm
	_leaf_mm = _mm(lq, MAX_STRANDS * MAX_LEAVES_PER, "VineLeaves")
	print("FxVines: %d anchor sites" % _sites.size())

func _mm(mesh: Mesh, n: int, nm: String) -> MultiMesh:
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

## Air a strand may hang through: empty fg (no gameplay block, no deco) and not solid.
func _free(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and lvl.get_fg(x, y) == 0

func _find_sites() -> void:
	for y in range(1, H - 2):
		for x in range(1, W - 1):
			if not veil.is_foliage(x, y) or veil.is_foliage(x, y + 1) or not _free(x, y + 1):
				continue
			var h := FxInteractiveBlocks._tile_hash(Vector2i(x, y) + Vector2i(911, 37))
			if h.x > 0.4:
				continue
			# length: 1.2 .. 4 tiles, never reaching into anything below
			var room := 0
			while room < 5 and _free(x, y + 1 + room):
				room += 1
			var want := 1.2 + h.y * 2.8
			var length := minf(want, room - 0.35)
			if length < 0.9:
				continue
			var s := Vector3(x + 0.2 + h.z * 0.6, -float(y + 1) + 0.05, length)
			var k := Vector2i(x / BUCKET, y / BUCKET)
			if not _bucket.has(k):
				_bucket[k] = []
			_bucket[k].append(_sites.size())
			_sites.append(s)

# ------------------------------------------------------------------------------------------ runtime

func set_focus(cam_world: Vector3) -> void:
	focus = Vector2(cam_world.x, -cam_world.y)
	_focus_fed = true

func set_ball(p: Vector3) -> void:
	ball = Vector2(p.x, p.y)

func _assign() -> void:
	var want := {}
	var c := Vector2i(int(focus.x) / BUCKET, int(focus.y) / BUCKET)
	var br := int(ceil(NEAR / BUCKET)) + 1
	var cand: Array = []
	for by in range(c.y - br, c.y + br + 1):
		for bx in range(c.x - br, c.x + br + 1):
			for idx in _bucket.get(Vector2i(bx, by), []):
				var s := _sites[idx]
				var d := Vector2(s.x, -s.y).distance_to(focus)
				if d < NEAR:
					cand.append([d, idx])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(cand.size(), MAX_STRANDS):
		want[cand[i][1]] = true
	for idx in _active.keys():
		if not want.has(idx):
			_active.erase(idx)
	for idx in want:
		if not _active.has(idx):
			_active[idx] = _new_strand(_sites[idx], idx)

func _new_strand(s: Vector3, idx: int) -> Dictionary:
	var pts := PackedVector2Array()
	var prev := PackedVector2Array()
	var seg := s.z / (NODES - 1)
	for i in NODES:
		pts.append(Vector2(s.x, s.y - seg * i))
	prev = pts.duplicate()
	var h := FxInteractiveBlocks._tile_hash(Vector2i(idx, 7))
	var leaves: Array = []
	var n := 4 + int(h.x * (MAX_LEAVES_PER - 3))
	for k in n:
		var hk := FxInteractiveBlocks._tile_hash(Vector2i(idx, 100 + k))
		leaves.append({"node": 1 + int(hk.x * (NODES - 2)), "side": 1.0 if hk.y < 0.5 else -1.0,
			"size": 0.32 + hk.z * 0.18, "col": Color(0.16 + hk.x * 0.12, 0.36 + hk.y * 0.16, 0.07 + hk.z * 0.05)})
	return {"pts": pts, "prev": prev, "seg": seg, "anchor": Vector2(s.x, s.y), "ph": h.y * TAU,
		"w": 0.11 + h.z * 0.05, "leaves": leaves, "shade": h.z}

func _process(delta: float) -> void:
	if lvl == null:
		return
	if not _focus_fed:
		var cam := get_viewport().get_camera_3d()
		if cam:
			focus = Vector2(cam.global_position.x, -cam.global_position.y)
	_focus_fed = false
	delta = clampf(delta, 0.001, 0.033)
	_assign_t -= delta
	if _assign_t <= 0.0:
		_assign_t = 0.5
		_assign()
	var t := Time.get_ticks_msec() * 0.001
	var bv := (ball - _prev_ball) / delta if _prev_ball.x > -999.0 else Vector2.ZERO
	if bv.length() > 60.0:
		bv = Vector2.ZERO
	_prev_ball = ball
	var ns := 0
	var nl := 0
	var dt2 := delta * delta
	for idx in _active:
		var st: Dictionary = _active[idx]
		var pts: PackedVector2Array = st.pts
		var prev: PackedVector2Array = st.prev
		var near_ball: bool = st.anchor.distance_to(ball) < 6.0
		# gusting wind: slow base sway + faster flutter, varying along x so neighbours don't move in lockstep
		var ax: float = st.anchor.x
		var wind := (sin(t * 0.7 + ax * 0.21) * 0.6 + sin(t * 1.9 + ax * 0.53 + st.ph) * 0.3 + sin(t * 0.23) * 0.4) * 1.1
		for i in range(1, NODES):
			var p := pts[i]
			var v := (p - prev[i]) * 0.965
			prev[i] = p
			var acc := Vector2(wind * (0.4 + 0.6 * float(i) / NODES), -9.0)
			pts[i] = p + v + acc * dt2
		# ball parts the strands: push nodes out of its radius and drag them a little along its motion
		if near_ball:
			for i in range(1, NODES):
				var d := pts[i] - ball
				var l := d.length()
				if l < BALL_R and l > 1e-4:
					pts[i] = ball + d / l * BALL_R
					prev[i] -= bv * delta * 0.25
		# distance constraints (anchor fixed)
		pts[0] = st.anchor
		for it in 3:
			for i in range(1, NODES):
				var a := pts[i - 1]
				var b := pts[i]
				var d := b - a
				var l := d.length()
				if l < 1e-5:
					continue
				var corr: Vector2 = d * ((l - st.seg) / l)
				if i == 1:
					pts[i] = b - corr
				else:
					pts[i - 1] = a + corr * 0.5
					pts[i] = b - corr * 0.5
			pts[0] = st.anchor
		st.pts = pts
		st.prev = prev
		# segments
		var w0: float = st.w
		for i in range(NODES - 1):
			if ns >= _seg_mm.instance_count:
				break
			var a := pts[i]
			var b := pts[i + 1]
			var yv := Vector3(a.x - b.x, a.y - b.y, 0.0)
			var xv := Vector3(-yv.y, yv.x, 0.0).normalized()
			if xv == Vector3.ZERO:
				xv = Vector3.RIGHT
			var k0 := float(i) / (NODES - 1)
			var k1 := float(i + 1) / (NODES - 1)
			_seg_mm.set_instance_transform(ns, Transform3D(Basis(xv, yv, Vector3.BACK), Vector3(a.x, a.y, Z)))
			_seg_mm.set_instance_custom_data(ns, Color(w0 * (1.0 - k0 * 0.7), w0 * (1.0 - k1 * 0.7), st.shade, 0))
			ns += 1
		for lf in st.leaves:
			if nl >= _leaf_mm.instance_count:
				break
			var i: int = lf.node
			var a := pts[i]
			var dir := (pts[i] - pts[i - 1]).normalized()
			var ang: float = atan2(dir.y, dir.x) + PI * 0.5 + lf.side * (0.9 + 0.25 * sin(t * 2.3 + i + st.ph))
			var sz: float = lf.size
			var basis := Basis(Vector3(0, 0, 1), ang).scaled(Vector3(sz * 0.6, sz, 1.0))
			_leaf_mm.set_instance_transform(nl, Transform3D(basis, Vector3(a.x, a.y, Z + 0.02 + 0.01 * lf.side)))
			var col: Color = lf.col
			_leaf_mm.set_instance_custom_data(nl, col)
			nl += 1
	_seg_mm.visible_instance_count = ns
	_leaf_mm.visible_instance_count = nl
