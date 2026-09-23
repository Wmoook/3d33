class_name WorldDepthGreen
extends WorldGrass
## Vegetation on world's extruded depth tops (the ground tops continued backward into 3D hillsides,
## z ~ -1.5 .. -26): grass clumps with density / blade LOD falling off with depth, plus a few bushes and
## small trees (leaf-card crowns). Decor only: everything sits behind the gameplay plane (z < -1.8), so it
## can never cover the ball or a glyph.
## World provides the surface through two callables:
##   top_at(x: float, z: float) -> float : world y of the extruded top surface at (x, z); NAN = no surface
##   mat_at(x: float, z: float) -> int   : WorldPalette material there (-1 = none)
## Usage: add_child(g); g.build_depth(lvl, terrain, top_at, mat_at); g.update_focus(ball, delta) like WorldGrass.

const Z_START := -1.9          # the extrusion begins behind the gameplay strip (WorldGrass covers z > -1.8)
const Z_NEAR := -6.0           # full density down to here
const Z_MID := -14.0           # sparse, bigger / cheaper clumps down to here; none beyond (PBR + haze carry it)
const DENS_NEAR := 5.0         # clumps per tile^2
const DENS_MID := 0.9
const STEP := 0.5              # sampling grid over (x, z)
const BUSH_CHANCE := 0.012     # per sampled cell beyond z -4
const TREE_CHANCE := 0.003
const Z_TOP_BEGIN := -1.2      # WorldDepth: extruded solid tops start here
const TREE_MIN_D := 4.5        # trees stand at least this far behind the front edge (they'd poke into the
                               # sky above the gameplay air otherwise)
const TREE_NEAR_D := 8.0       # ... and stay short (<= TREE_NEAR_H incl. crown) within this depth
const TREE_NEAR_H := 2.5

var depth_stats := {}
var _leaf_mat: ShaderMaterial
var _groups := {}              # Vector3i(chunk_x, band, 0) -> {kind: [[xforms], [custom]]}

func build_depth(lvl: EELevel, terrain: WorldTerrain, top_at: Callable, mat_at: Callable) -> void:
	_rng.seed = 9090
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/world/grass_blade.gdshader")
	material.set_shader_parameter("day", 0.0 if WorldPalette.is_odyssey() else 1.0)
	material.set_shader_parameter("fade_far", 70.0)
	_meshes = {
		Kind.TALL: _clump_mesh(10, 0.18, 0.32, 0.016, 0.034, 0.2, 4, 11),
		Kind.SHORT: _clump_mesh(8, 0.1, 0.2, 0.02, 0.04, 0.3, 2, 12),   # LOD clump: fewer, wider blades
	}
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = load("res://shaders/world/leaf_card.gdshader")
	_leaf_mat.set_shader_parameter("leaf_albedo", load("res://assets/world/pbr/leaf_cluster_albedo.png"))
	_leaf_mat.set_shader_parameter("leaf_normal", load("res://assets/world/pbr/leaf_cluster_normal.png"))
	_leaf_mat.set_shader_parameter("day", 0.0 if WorldPalette.is_odyssey() else 1.0)
	var W := lvl.width
	var H := lvl.height
	var cols := terrain.fgcol_img
	var cm := WorldGrass.canopy_map(terrain)
	var leaf_x: Array[Transform3D] = []
	var leaf_c: Array[Color] = []
	var trunk_x: Array[Transform3D] = []
	var n := {"near": 0, "mid": 0, "bush": 0, "tree": 0}
	var z := Z_START
	while z > Z_MID:
		var near := z > Z_NEAR
		var dens := DENS_NEAR if near else lerpf(DENS_MID, 0.3, (Z_NEAR - z) / (Z_NEAR - Z_MID))
		var p_cell := dens * STEP * STEP
		var x := 0.0
		while x < W:
			var m: int = mat_at.call(x, z)
			if m == WorldPalette.M_GRASS or m == WorldPalette.M_FOLIAGE:
				var y: float = top_at.call(x, z)
				if not is_nan(y):
					var ty := clampi(int(floor(-y)), 0, H - 1)
					var base := cols.get_pixel(clampi(int(x), 0, W - 1), ty)
					var cnt := int(p_cell) + (1 if _rng.randf() < fmod(p_cell, 1.0) else 0)
					for k in cnt:
						var px := x + _rng.randf() * STEP
						var pz := z - _rng.randf() * STEP
						var py: float = top_at.call(px, pz)
						if is_nan(py):
							continue
						var band := 0 if near else 1
						var kind := Kind.TALL if near else Kind.SHORT
						var s := _rng.randf_range(0.8, 1.15) * (1.0 if near else 1.6)
						# optional smooth skin (WorldDepth.smooth_skin): sink the clump by its footprint's rise on
						# gentle slopes; block steps (rise >= 0.4 over 0.25) are walls, not slopes -> ignored
						var hx: float = top_at.call(px + 0.25, pz)
						var hz: float = top_at.call(px, pz - 0.25)
						if not is_nan(hx) and not is_nan(hz):
							var rise := maxf(absf(hx - py), absf(hz - py))
							if rise > 0.005 and rise < 0.4:
								py -= minf(rise / 0.25, 1.5) * (0.3 if near else 0.45) * s * 0.6
						_group_push(Vector3i(int(px) / CHUNK, band, 0), kind, Vector3(px, py, pz), s, _vary(base, 0.12))
						n["near" if near else "mid"] += 1
					if z < -4.0 and not cm[ty * W + clampi(int(x), 0, W - 1)] and _rng.randf() < BUSH_CHANCE:
						_bush(Vector3(x + 0.25, y, z - 0.25), base, leaf_x, leaf_c, 0.9)
						n.bush += 1
					elif Z_TOP_BEGIN - z > TREE_MIN_D and not cm[ty * W + clampi(int(x), 0, W - 1)] and _rng.randf() < TREE_CHANCE:
						# (never on top of a tree crown's extrusion.) Height grows with depth so the tree stays
						# below the front silhouette's sight line: <= 2.5 incl. crown within 8 tiles, then +0.35/tile
						var d := Z_TOP_BEGIN - z
						var h_max := TREE_NEAR_H + maxf(d - TREE_NEAR_D, 0.0) * 0.35 - 0.9   # crown ~0.9 above trunk
						var h := minf(_rng.randf_range(2.2, 3.6), h_max)
						trunk_x.append(Transform3D(Basis().scaled(Vector3(0.22, h, 0.22)), Vector3(x + 0.25, y + h * 0.5, z - 0.25)))
						for c in 3:
							_bush(Vector3(x + 0.25 + _rng.randf_range(-0.6, 0.6), y + h + _rng.randf_range(-0.4, 0.5), z - 0.25 + _rng.randf_range(-0.4, 0.4)), base.darkened(0.08), leaf_x, leaf_c, 1.6)
						n.tree += 1
			x += STEP
		z -= STEP
	for key in _groups:
		_make_group(key, _groups[key])
	_groups.clear()
	_add_cards(leaf_x, leaf_c)
	_add_trunks(trunk_x)
	depth_stats = n

## A bush: 5 leaf cards around a centre, facing the camera, resting on the surface.
func _bush(c: Vector3, col: Color, xs: Array[Transform3D], cs: Array[Color], scale_v: float) -> void:
	for k in 5:
		var sz := _rng.randf_range(0.7, 1.1) * scale_v
		var off := Vector3(_rng.randf_range(-0.45, 0.45), _rng.randf_range(0.1, 0.55), _rng.randf_range(-0.3, 0.3)) * scale_v
		var b := Basis(Vector3.BACK, _rng.randf() * TAU).scaled(Vector3.ONE * sz)
		xs.append(Transform3D(b, c + off + Vector3(0, sz * 0.3, 0)))
		var lc := col.srgb_to_linear()
		var f := _rng.randf_range(0.8, 1.1)
		cs.append(Color(lc.r * f, lc.g * f, lc.b * f, float(_rng.randi() % 4) + _rng.randf_range(0.5, 0.95)))

func _group_push(key: Vector3i, kind: int, p: Vector3, s: float, c: Color) -> void:
	if not _groups.has(key):
		_groups[key] = {}
	var g: Dictionary = _groups[key]
	if not g.has(kind):
		g[kind] = [[], []]
	var b := Basis(Vector3.UP, _rng.randf_range(-1.1, 1.1)).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s))
	g[kind][0].append(Transform3D(b, p))
	var lc := c.srgb_to_linear()
	g[kind][1].append(Color(lc.r, lc.g, lc.b, _rng.randf() * 0.99))

func _make_group(key: Vector3i, g: Dictionary) -> void:
	for kind in g:
		var xs: Array = g[kind][0]
		if xs.is_empty():
			continue
		var origin: Vector3 = xs[0].origin
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[kind]
		mm.instance_count = xs.size()
		for k in xs.size():
			var t: Transform3D = xs[k]
			t.origin -= origin
			mm.set_instance_transform(k, t)
			mm.set_instance_custom_data(k, g[kind][1][k])
		var mi := MultiMeshInstance3D.new()
		mi.name = "D_%d_%d_%d" % [key.x, key.y, kind]
		mi.multimesh = mm
		mi.material_override = material
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# aggressive LOD: the near band vanishes first, the sparse mid band a bit later
		mi.visibility_range_end = 60.0 if key.y == 0 else 75.0
		mi.visibility_range_end_margin = 8.0
		add_child(mi)

func _add_cards(xs: Array[Transform3D], cs: Array[Color]) -> void:
	if xs.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_custom_data(k, cs[k])
	var mi := MultiMeshInstance3D.new()
	mi.name = "DepthBushes"
	mi.multimesh = mm
	mi.material_override = _leaf_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _add_trunks(xs: Array[Transform3D]) -> void:
	if xs.is_empty():
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.15)
	m.roughness = 0.9
	cyl.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cyl
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
	var mi := MultiMeshInstance3D.new()
	mi.name = "DepthTrunks"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func update_focus(world_pos: Vector3, delta: float) -> void:
	super.update_focus(world_pos, delta)
	if _leaf_mat:
		_leaf_mat.set_shader_parameter("ball_pos", world_pos)
