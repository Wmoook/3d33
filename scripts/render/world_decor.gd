class_name WorldDecor
extends Node3D
## Props & vegetation (MultiMesh): grass on exposed grass tops, leaf tufts on tree canopies, the level's
## passive decorations (tufts, bushes, flowers, rocks, snow drifts, lanterns/garland bulbs, pines,
## fences, umbrellas) rebuilt as small 3D props consistent with the terrain style.

var _rng := RandomNumberGenerator.new()
var _mat_foliage: ShaderMaterial
var _mat_prop: ShaderMaterial
var _mat_glow: ShaderMaterial

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	_rng.seed = 1337
	_mat_foliage = _foliage_mat(1.0, 0.45, 0.0, 0.75)
	_mat_prop = _foliage_mat(0.0, 0.1, 0.0, 0.6)
	_mat_glow = _foliage_mat(0.0, 0.0, 0.0, 0.3)
	var W := lvl.width
	var H := lvl.height
	var grass_x: Array[Transform3D] = []
	var grass_c: Array[Color] = []
	var leaf_x: Array[Transform3D] = []
	var leaf_c: Array[Color] = []
	var rock_x: Array[Transform3D] = []
	var rock_c: Array[Color] = []
	var bulb_x: Array[Transform3D] = []
	var bulb_c: Array[Color] = []
	var cone_x: Array[Transform3D] = []
	var cone_c: Array[Color] = []
	var box_x: Array[Transform3D] = []
	var box_c: Array[Color] = []
	for y in H:
		for x in W:
			var i := y * W + x
			var id: int = lvl.fg[i]
			var above_air := y > 0 and not terrain.solid[i - W]
			if terrain.solid[i]:
				var m: int = terrain.mat_ids[i]
				if above_air and (m == WorldPalette.M_GRASS or (m == WorldPalette.M_FOLIAGE and y < 22)):
					var base := WorldPalette.base_color(id)
					var cnt := 5 if m == WorldPalette.M_GRASS else 3
					for k in cnt:
						var px := x + (k + _rng.randf()) / cnt
						var pz := _rng.randf_range(-2.6, 0.12)
						var s := _rng.randf_range(0.7, 1.35) * (1.0 if m == WorldPalette.M_GRASS else 0.8)
						var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s))
						grass_x.append(Transform3D(b, Vector3(px, -y + 0.02, pz)))
						grass_c.append(_vary(base.lightened(0.1), 0.12))
				if m == WorldPalette.M_FOLIAGE and y < 22:
					# fluffy leaf clusters around exposed canopy edges
					var exposed := 0
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = x + d.x
						var ny: int = y + d.y
						if nx >= 0 and ny >= 0 and nx < W and ny < H and not terrain.solid[ny * W + nx]:
							exposed += 1
					var nleaf := 2 + exposed
					for k in nleaf:
						var s := _rng.randf_range(0.5, 0.85)
						var r := 0.45 * s
						var inset := r - 0.08
						var lx := _rng.randf_range(0.0 + (inset if x > 0 and not terrain.solid[i - 1] else 0.0), 1.0 - (inset if x < W - 1 and not terrain.solid[i + 1] else 0.0))
						var ly := _rng.randf_range(0.0 + (inset if not above_air else 0.0), 1.0 - (inset if y < H - 1 and not terrain.solid[i + W] else 0.0))
						var front := _rng.randf() < 0.7
						var p := Vector3(x + lx, -y - ly, _rng.randf_range(0.35, 0.8) if front else _rng.randf_range(-2.2, 0.0))
						var b := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)).scaled(Vector3.ONE * s)
						leaf_x.append(Transform3D(b, p))
						leaf_c.append(_vary(WorldPalette.base_color(id), 0.18))
				continue
			if not WorldPalette.is_world_deco(id):
				continue
			var cx := x + 0.5
			var by := -y - 1.0   # bottom of the tile (world y)
			match id:
				233, 234, 235, 236, 237, 238, 240, 232:
					var col := _deco_color(id)
					var cnt := 6 if id >= 236 else 4
					for k in cnt:
						var px := x + _rng.randf()
						var s := _rng.randf_range(0.8, 1.4) * (1.3 if id >= 236 else 1.0)
						var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
						grass_x.append(Transform3D(b, Vector3(px, by + 0.02, _rng.randf_range(-1.5, -0.1))))
						grass_c.append(_vary(col, 0.12))
					if id >= 236 or id == 232 or id == 240:
						for k in 3:
							var p := Vector3(x + _rng.randf(), by + _rng.randf_range(0.2, 0.6), _rng.randf_range(-1.2, -0.2))
							var s := _rng.randf_range(0.35, 0.55)
							leaf_x.append(Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0)).scaled(Vector3.ONE * s), p))
							leaf_c.append(_vary(col, 0.15))
				239:
					# sunflower: stem (thin box) + glowing-ish head
					box_x.append(Transform3D(Basis().scaled(Vector3(0.05, 0.7, 0.05)), Vector3(cx, by + 0.35, -0.4)))
					box_c.append(Color(0.2, 0.45, 0.12))
					bulb_x.append(Transform3D(Basis().scaled(Vector3(0.28, 0.28, 0.1)), Vector3(cx, by + 0.75, -0.35)))
					bulb_c.append(Color(1.0, 0.75, 0.1, 0.4))
				231:
					var s := _rng.randf_range(0.35, 0.5)
					rock_x.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(s * 1.2, s * 0.7, s)), Vector3(cx, by + s * 0.3, -0.6)))
					rock_c.append(_vary(Color(0.42, 0.44, 0.48), 0.08))
				227, 249, 250, 229, 230:
					var col := Color(0.9, 0.93, 1.0) if id == 227 or id >= 249 else Color(0.85, 0.7, 0.45)
					var s := 0.55
					rock_x.append(Transform3D(Basis().scaled(Vector3(s * 1.4, s * 0.55, s)), Vector3(cx, by + 0.05, -0.5)))
					rock_c.append(col)
				244, 245, 246, 247, 248:
					var bc: Color = [Color(0.8, 0.4, 1.0), Color(1.0, 0.75, 0.3), Color(0.35, 0.6, 1.0), Color(1.0, 0.2, 0.2), Color(0.3, 1.0, 0.4)][id - 244]
					bulb_x.append(Transform3D(Basis().scaled(Vector3.ONE * 0.16), Vector3(cx, -y - 0.62, 0.05)))
					bulb_c.append(Color(bc.r, bc.g, bc.b, 3.0))
				251, 252:
					for k in 3:
						var s := 0.75 - k * 0.2
						cone_x.append(Transform3D(Basis().scaled(Vector3(s, 0.55, s)), Vector3(cx, by + 0.3 + k * 0.32, -0.6)))
						cone_c.append(_vary(Color(0.12, 0.35, 0.16), 0.05))
					if id == 252:
						for k in 4:
							bulb_x.append(Transform3D(Basis().scaled(Vector3.ONE * 0.07), Vector3(cx + _rng.randf_range(-0.35, 0.35), by + 0.3 + _rng.randf() * 0.7, -0.2)))
							bulb_c.append(Color(1.0, 0.3 + _rng.randf() * 0.6, 0.2, 3.0))
				253, 254:
					var fc := Color(0.45, 0.3, 0.18) if id == 253 else Color(0.5, 0.28, 0.1)
					for k in 3:
						box_x.append(Transform3D(Basis().scaled(Vector3(0.09, 0.6, 0.09)), Vector3(x + 0.17 + k * 0.33, by + 0.3, -0.3)))
						box_c.append(fc)
					for k in 2:
						box_x.append(Transform3D(Basis().scaled(Vector3(1.0, 0.07, 0.06)), Vector3(cx, by + 0.2 + k * 0.25, -0.3)))
						box_c.append(fc.darkened(0.1))
				228:
					box_x.append(Transform3D(Basis().scaled(Vector3(0.05, 0.9, 0.05)), Vector3(cx, by + 0.45, -0.4)))
					box_c.append(Color(0.5, 0.4, 0.3))
					cone_x.append(Transform3D(Basis().scaled(Vector3(0.9, 0.3, 0.9)), Vector3(cx, by + 0.95, -0.4)))
					cone_c.append(Color(0.2, 0.5, 0.75))
	# floating islands of 1-3 tiles (sparks, debris, droplets) as lumpy 3D pebbles / embers
	var float_x: Array[Transform3D] = []
	var float_c: Array[Color] = []
	var glow_x: Array[Transform3D] = []
	var glow_c: Array[Color] = []
	for i in terrain.floaters:
		var f: Array = terrain.floaters[i]
		var x: int = i % W
		var y: int = i / W
		var col: Color = f[0]
		var m: int = f[1]
		var b := Basis(Vector3.FORWARD, _rng.randf() * TAU).scaled(Vector3(0.56, 0.56, 0.5) * _rng.randf_range(0.92, 1.05))
		var t := Transform3D(b, Vector3(x + 0.5, -y - 0.5, 0.05))
		match m:
			WorldPalette.M_FIRE:
				glow_x.append(t); glow_c.append(Color(col.r, col.g, col.b, 2.5))
			WorldPalette.M_GEM, WorldPalette.M_CORRUPT, WorldPalette.M_GLASS:
				glow_x.append(t); glow_c.append(Color(col.r, col.g, col.b, 0.6))
			_:
				float_x.append(t); float_c.append(col)
	_add_mm("Floaters", _pebble_mesh(), _mat_prop, float_x, float_c)
	_add_mm("GlowFloaters", _pebble_mesh(), _mat_glow, glow_x, glow_c, true)
	_add_mm("Grass", _grass_mesh(), _mat_foliage, grass_x, grass_c)
	_add_mm("Leaves", _leaf_mesh(), _mat_foliage, leaf_x, leaf_c)
	_add_mm("Rocks", _rock_mesh(), _mat_prop, rock_x, rock_c)
	_add_mm("Bulbs", _sphere(), _mat_glow, bulb_x, bulb_c, true)
	_add_mm("Cones", _cone(), _mat_prop, cone_x, cone_c)
	_add_mm("Boxes", _box(), _mat_prop, box_x, box_c)

func _vary(c: Color, a: float) -> Color:
	var f := 1.0 + _rng.randf_range(-a, a)
	return Color(c.r * f, c.g * f * (1.0 + _rng.randf_range(-a, a) * 0.3), c.b * f, 1.0)

func _deco_color(id: int) -> Color:
	match id:
		232: return Color(0.5, 0.52, 0.12)
		236, 237, 238: return Color(0.2, 0.5, 0.14)
		240: return Color(0.22, 0.55, 0.12)
	return Color(0.26, 0.62, 0.14)

func _foliage_mat(wind: float, transl: float, emit: float, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/world/foliage.gdshader")
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("translucency", transl)
	m.set_shader_parameter("emission_boost", emit)
	m.set_shader_parameter("rough", rough)
	return m

## col.a > 1 is used as emission strength for glow props (stored in custom data).
func _add_mm(nm: String, mesh: Mesh, mat: Material, xs: Array[Transform3D], cs: Array[Color], glow := false) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		var c := cs[i]
		var e := 0.0
		if glow:
			e = c.a
		var lc := Color(c.r, c.g, c.b, 1.0).srgb_to_linear()
		mm.set_instance_color(i, lc)
		mm.set_instance_custom_data(i, Color(1, 1, 1, e))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not glow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## A clump of ~9 tapered blades; vertex colour dark base -> light tip, alpha = sway weight.
func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for b in 9:
		var ang := r.randf() * TAU
		var off := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
		var h := r.randf_range(0.28, 0.55)
		var wdt := r.randf_range(0.03, 0.05)
		var lean := Vector3(cos(ang), 0, sin(ang)) * r.randf_range(0.05, 0.18)
		var side := Vector3(-sin(ang), 0, cos(ang)) * wdt
		var segs := 3
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := off + Vector3(0, h * t0, 0) + lean * t0 * t0
			var p1 := off + Vector3(0, h * t1, 0) + lean * t1 * t1
			var w0 := side * (1.0 - t0)
			var w1 := side * (1.0 - t1)
			var c0 := Color(0.35 + 0.65 * t0, 0.35 + 0.65 * t0, 0.35 + 0.65 * t0, t0)
			var c1 := Color(0.35 + 0.65 * t1, 0.35 + 0.65 * t1, 0.35 + 0.65 * t1, t1)
			st.set_normal(Vector3(0, 0.3, 1).normalized())
			st.set_color(c0); st.add_vertex(p0 - w0)
			st.set_color(c0); st.add_vertex(p0 + w0)
			st.set_color(c1); st.add_vertex(p1 + w1)
			st.set_color(c0); st.add_vertex(p0 - w0)
			st.set_color(c1); st.add_vertex(p1 + w1)
			st.set_color(c1); st.add_vertex(p1 - w1)
	return st.commit()

## Leaf cluster: a lumpy low-poly blob of small leaf quads.
func _leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for k in 14:
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized()
		var c := dir * 0.45
		var t1 := dir.cross(Vector3(0.3, 1, 0.1)).normalized() * 0.22
		var t2 := dir.cross(t1).normalized() * 0.3
		var sh := 0.6 + 0.4 * (dir.y * 0.5 + 0.5)
		var col := Color(sh, sh, sh, 0.5 + 0.5 * (dir.y * 0.5 + 0.5))
		st.set_normal(dir)
		st.set_color(col)
		st.add_vertex(c - t2); st.add_vertex(c + t1); st.add_vertex(c + t2)
		st.add_vertex(c - t2); st.add_vertex(c + t2); st.add_vertex(c - t1)
	return st.commit()

## Lumpy pebble: sphere with low-frequency noise displacement.
func _pebble_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var fn := FastNoiseLite.new()
	fn.frequency = 1.3
	fn.seed = 5
	for k in v.size():
		var d := v[k].normalized()
		v[k] = d * (0.9 + 0.14 * fn.get_noise_3dv(d * 2.0))
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var cols := PackedColorArray()
	cols.resize(v.size())
	cols.fill(Color(1, 1, 1, 0))
	arr[Mesh.ARRAY_COLOR] = cols
	var st := SurfaceTool.new()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(m, 0)
	st.generate_normals()
	return st.commit()

func _rock_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 10
	s.rings = 6
	return _vertex_white(s)

func _sphere() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 12
	s.rings = 6
	return _vertex_white(s)

func _cone() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 10
	return _vertex_white(c)

func _box() -> Mesh:
	return _vertex_white(BoxMesh.new())

## Primitive meshes carry no vertex colour; bake white (alpha 0 = no sway) so COLOR = instance colour.
func _vertex_white(prim: PrimitiveMesh) -> ArrayMesh:
	var arr := prim.get_mesh_arrays()
	var n: int = arr[Mesh.ARRAY_VERTEX].size()
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(Color(1, 1, 1, 0))
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func update_focus(_world_pos: Vector3, _delta: float) -> void:
	pass
