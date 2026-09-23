class_name FxMeshes
## Procedural meshes for actor visuals (gems, crowns, coins, shards, rings). All built once and cached.

static var _cache := {}

static func _cached(key: String, builder: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]

## Faceted crystal: hexagonal bipyramid with a short prism waist, y-up, centered, height ~1.
static func gem() -> Mesh:
	return _cached("gem", func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 6
		var r := 0.28
		var top := Vector3(0, 0.55, 0)
		var bot := Vector3(0, -0.45, 0)
		var hi := 0.12
		var lo := -0.06
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var p0h := Vector3(cos(a0) * r, hi, sin(a0) * r)
			var p1h := Vector3(cos(a1) * r, hi, sin(a1) * r)
			var p0l := Vector3(cos(a0) * r * 0.92, lo, sin(a0) * r * 0.92)
			var p1l := Vector3(cos(a1) * r * 0.92, lo, sin(a1) * r * 0.92)
			_tri(st, top, p1h, p0h)
			_tri(st, p0h, p1h, p1l)
			_tri(st, p0h, p1l, p0l)
			_tri(st, bot, p0l, p1l)
		st.generate_normals()
		return st.commit())

## Golden crown: zig-zag band (outer + inner faces + top rim) as surface 0, tip gem balls as surface 1.
## Base radius 0.5, height ~0.62, sits on y=0.
static func crown() -> Mesh:
	return _cached("crown", func() -> Mesh:
		var mesh := ArrayMesh.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 60
		var spikes := 5
		var r_out := 0.5
		var r_in := 0.44
		var h_base := 0.26
		var h_tip := 0.62
		var tips: Array[Vector3] = []
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var h0 := _crown_h(a0, spikes, h_base, h_tip)
			var h1 := _crown_h(a1, spikes, h_base, h_tip)
			var o0b := Vector3(cos(a0) * r_out, 0, sin(a0) * r_out)
			var o1b := Vector3(cos(a1) * r_out, 0, sin(a1) * r_out)
			var o0t := Vector3(cos(a0) * r_out * 0.97, h0, sin(a0) * r_out * 0.97)
			var o1t := Vector3(cos(a1) * r_out * 0.97, h1, sin(a1) * r_out * 0.97)
			var i0b := Vector3(cos(a0) * r_in, 0, sin(a0) * r_in)
			var i1b := Vector3(cos(a1) * r_in, 0, sin(a1) * r_in)
			var i0t := Vector3(cos(a0) * r_in * 0.97, h0 - 0.02, sin(a0) * r_in * 0.97)
			var i1t := Vector3(cos(a1) * r_in * 0.97, h1 - 0.02, sin(a1) * r_in * 0.97)
			# outer
			_quad(st, o0b, o1b, o1t, o0t)
			# inner (reversed)
			_quad(st, i1b, i0b, i0t, i1t)
			# top rim
			_quad(st, o0t, o1t, i1t, i0t)
			# bottom rim
			_quad(st, i0b, i1b, o1b, o0b)
		# thick base ring bulge (a torus-ish band) for an ornate look
		var ring_r := 0.515
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			for j in 6:
				var b0 := TAU * j / 6
				var b1 := TAU * (j + 1) / 6
				var q00 := _torus(a0, b0, ring_r, 0.035, 0.05)
				var q10 := _torus(a1, b0, ring_r, 0.035, 0.05)
				var q11 := _torus(a1, b1, ring_r, 0.035, 0.05)
				var q01 := _torus(a0, b1, ring_r, 0.035, 0.05)
				_quad(st, q00, q01, q11, q10)
		st.generate_normals()
		mesh = st.commit()
		for k in spikes:
			var a := TAU * (k + 0.5) / spikes
			tips.append(Vector3(cos(a) * r_out * 0.97, h_tip + 0.05, sin(a) * r_out * 0.97))
		# front band jewels
		var jewels: Array[Vector3] = []
		for k in spikes:
			var a := TAU * (k + 0.5) / spikes
			jewels.append(Vector3(cos(a) * (r_out + 0.02), 0.13, sin(a) * (r_out + 0.02)))
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in tips:
			_sphere(st2, t, 0.055, 8, 6)
		for j in jewels:
			_sphere(st2, j, 0.06, 8, 6)
		st2.generate_normals()
		st2.commit(mesh)
		return mesh)

static func _crown_h(a: float, spikes: int, hb: float, ht: float) -> float:
	var f := fposmod(a / TAU * spikes, 1.0)
	var tri := 1.0 - absf(f - 0.5) * 2.0
	tri = pow(tri, 1.6)
	return hb + (ht - hb) * tri

static func _torus(a: float, b: float, R: float, r: float, y: float) -> Vector3:
	var rr := R + cos(b) * r
	return Vector3(cos(a) * rr, y + sin(b) * r, sin(a) * rr)

## Coin: beveled disc facing +z. radius 0.5, thickness 0.12. UVs on caps are planar (0..1), rim uv.y = 2.
static func coin() -> Mesh:
	return _cached("coin", func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 64
		var r := 0.5
		var rb := 0.45
		var t := 0.06
		var tb := 0.042
		for side in [1.0, -1.0]:
			for i in seg:
				var a0 := TAU * i / seg
				var a1 := TAU * (i + 1) / seg
				var c := Vector3(0, 0, t * side)
				var p0 := Vector3(cos(a0) * rb, sin(a0) * rb, t * side)
				var p1 := Vector3(cos(a1) * rb, sin(a1) * rb, t * side)
				var e0 := Vector3(cos(a0) * r, sin(a0) * r, tb * side)
				var e1 := Vector3(cos(a1) * r, sin(a1) * r, tb * side)
				if side > 0:
					_tri_uv(st, c, p0, p1, true)
					_quad_uv(st, p0, e0, e1, p1)
				else:
					_tri_uv(st, c, p1, p0, true)
					_quad_uv(st, p1, e1, e0, p0)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var f0 := Vector3(cos(a0) * r, sin(a0) * r, tb)
			var f1 := Vector3(cos(a1) * r, sin(a1) * r, tb)
			var b0 := Vector3(cos(a0) * r, sin(a0) * r, -tb)
			var b1 := Vector3(cos(a1) * r, sin(a1) * r, -tb)
			_quad_uv(st, f0, b0, b1, f1, 2.0)
		st.generate_normals()
		st.generate_tangents()
		return st.commit())

## Sharp little tetra shard for shatter FX.
static func shard() -> Mesh:
	return _cached("shard", func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(0, 0.6, 0)
		var b := Vector3(-0.35, -0.3, 0.25)
		var c := Vector3(0.4, -0.25, 0.2)
		var d := Vector3(0.0, -0.2, -0.4)
		_tri(st, a, b, c); _tri(st, a, c, d); _tri(st, a, d, b); _tri(st, b, d, c)
		st.generate_normals()
		return st.commit())

## Flat torus ring lying in the XZ plane (y up), major radius R, minor radius r.
static func ring(R: float, r: float, seg := 64, sides := 10) -> Mesh:
	return _cached("ring_%s_%s" % [R, r], func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			for j in sides:
				var b0 := TAU * j / sides
				var b1 := TAU * (j + 1) / sides
				_quad(st, _torus(a0, b0, R, r, 0), _torus(a0, b1, R, r, 0), _torus(a1, b1, R, r, 0), _torus(a1, b0, R, r, 0))
		st.generate_normals()
		return st.commit())

## Triangles are authored counter-clockwise; Godot's front faces are clockwise, so emit a,c,b.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c); _tri(st, a, c, d)

static func _cap_uv(p: Vector3) -> Vector2:
	return Vector2(p.x + 0.5, 0.5 - p.y) if p.z >= 0.0 else Vector2(0.5 - p.x, 0.5 - p.y)

static func _tri_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, _cap: bool) -> void:
	for p in [a, c, b]:
		st.set_uv(_cap_uv(p)); st.add_vertex(p)

static func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, rim := 0.0) -> void:
	for p in [a, c, b, a, d, c]:
		var uv := _cap_uv(p)
		if rim > 0.0:
			uv = Vector2(atan2(p.y, p.x) / TAU, 2.0)
		st.set_uv(uv); st.add_vertex(p)

static func _sphere(st: SurfaceTool, c: Vector3, r: float, seg: int, rings: int) -> void:
	for i in rings:
		var v0 := PI * i / rings
		var v1 := PI * (i + 1) / rings
		for j in seg:
			var u0 := TAU * j / seg
			var u1 := TAU * (j + 1) / seg
			var p00 := c + r * Vector3(sin(v0) * cos(u0), cos(v0), sin(v0) * sin(u0))
			var p01 := c + r * Vector3(sin(v0) * cos(u1), cos(v0), sin(v0) * sin(u1))
			var p10 := c + r * Vector3(sin(v1) * cos(u0), cos(v1), sin(v1) * sin(u0))
			var p11 := c + r * Vector3(sin(v1) * cos(u1), cos(v1), sin(v1) * sin(u1))
			_quad(st, p00, p01, p11, p10)

static func soft_dot_texture() -> Texture2D:
	if not _cache.has("softdot"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_cache["softdot"] = t
	return _cache["softdot"]

## Gravity arrow glyph: chevron ">" pointing +x in the XY plane (size ~0.5), slightly extruded.
## Surface 0 = glowing chevron, surface 1 = dark outline backing (thicker, behind).
static func chevron_glyph() -> Mesh:
	return _cached("chevron", func() -> Mesh:
		var mesh := ArrayMesh.new()
		for pass_i in 2:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var th := 0.075 if pass_i == 0 else 0.13
			var z := 0.02 if pass_i == 0 else -0.02
			var ext := 0.2 + (0.035 if pass_i == 1 else 0.0)
			var tip := Vector2(0.14 + (0.04 if pass_i == 1 else 0.0), 0.0)
			for sgn in [1.0, -1.0]:
				var a := Vector2(-0.1 - (0.03 if pass_i == 1 else 0.0), ext * sgn)
				var dir := (tip - a).normalized()
				var n := Vector2(-dir.y, dir.x) * th * 0.5
				# mitered apex: both arms end on the shared miter points on the axis (y = 0), so the two
				# strokes meet in one clean point with no notch or overlap seam
				var p0 := a + n; var p1 := a - n
				var p2 := p1 + dir * (-p1.y / dir.y)
				var p3 := p0 + dir * (-p0.y / dir.y)
				var q := [p0, p1, p2, p3]
				_prism(st, q, z, 0.03)
			st.generate_normals()
			st.commit(mesh)
		return mesh)

## Zero-gravity dot glyph: orb + floating ring in the XY plane. Surface 0 glow, surface 1 dark backing disc.
static func dot_glyph() -> Mesh:
	return _cached("dotglyph", func() -> Mesh:
		var mesh := ArrayMesh.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sphere(st, Vector3.ZERO, 0.085, 10, 6)
		var seg := 28
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			for j in 4:
				var b0 := TAU * j / 4
				var b1 := TAU * (j + 1) / 4
				var R := 0.2
				var r := 0.011
				var f := func(a: float, b: float) -> Vector3:
					var rr := R + cos(b) * r
					return Vector3(cos(a) * rr, sin(a) * rr, sin(b) * r)
				_quad(st, f.call(a0, b0), f.call(a1, b0), f.call(a1, b1), f.call(a0, b1))
		st.generate_normals()
		st.commit(mesh)
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			_tri(st2, Vector3(0, 0, -0.03), Vector3(cos(a0) * 0.36, sin(a0) * 0.36, -0.03), Vector3(cos(a1) * 0.36, sin(a1) * 0.36, -0.03))
		st2.generate_normals()
		st2.commit(mesh)
		return mesh)

static func _prism(st: SurfaceTool, q: Array, z: float, depth: float) -> void:
	var f: Array[Vector3] = []
	var b: Array[Vector3] = []
	for p: Vector2 in q:
		f.append(Vector3(p.x, p.y, z + depth * 0.5))
		b.append(Vector3(p.x, p.y, z - depth * 0.5))
	_quad(st, f[0], f[1], f[2], f[3])
	_quad(st, b[3], b[2], b[1], b[0])
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, f[j], f[i], b[i], b[j])

## EE portal (242) as a 3D block: a 1x1 tile slab with a chamfered front edge, extruded back to the level's
## blocky depth. Front face z = 0.3, back z = -0.6, chamfer 0.1. UV = front-face coords (0..1, y down) on
## every vertex; COLOR.r = face kind (1 front, 0.5 chamfer, 0 sides/back) for the shader.
static func portal_block() -> Mesh:
	return _cached("portal_block", func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var F := 0.3
		var B := -0.6
		var e := 0.1
		var h := 0.5
		var i := h - e
		var zc := F - e
		# clockwise-from-outside quads (Godot front faces)
		var quads := [
			# front
			[[-i, -i, F], [-i, i, F], [i, i, F], [i, -i, F], 1.0, Vector3(0, 0, 1)],
			# chamfers
			[[-i, i, F], [-h, h, zc], [h, h, zc], [i, i, F], 0.5, Vector3(0, 0.7, 0.7)],
			[[i, -i, F], [h, -h, zc], [-h, -h, zc], [-i, -i, F], 0.5, Vector3(0, -0.7, 0.7)],
			[[-h, -h, zc], [-h, h, zc], [-i, i, F], [-i, -i, F], 0.5, Vector3(-0.7, 0, 0.7)],
			[[i, -i, F], [i, i, F], [h, h, zc], [h, -h, zc], 0.5, Vector3(0.7, 0, 0.7)],
			# sides
			[[-h, h, zc], [-h, h, B], [h, h, B], [h, h, zc], 0.0, Vector3(0, 1, 0)],
			[[h, -h, zc], [h, -h, B], [-h, -h, B], [-h, -h, zc], 0.0, Vector3(0, -1, 0)],
			[[-h, -h, B], [-h, h, B], [-h, h, zc], [-h, -h, zc], 0.0, Vector3(-1, 0, 0)],
			[[h, -h, zc], [h, h, zc], [h, h, B], [h, -h, B], 0.0, Vector3(1, 0, 0)],
			# back
			[[h, -h, B], [h, h, B], [-h, h, B], [-h, -h, B], 0.0, Vector3(0, 0, -1)],
		]
		for qd in quads:
			var pts: Array = [qd[0], qd[1], qd[2], qd[0], qd[2], qd[3]]
			for p in pts:
				var v := Vector3(p[0], p[1], p[2])
				st.set_color(Color(qd[4], 0, 0))
				st.set_normal((qd[5] as Vector3).normalized())
				st.set_uv(Vector2(v.x + 0.5, 0.5 - v.y))
				st.add_vertex(v)
		return st.commit())
