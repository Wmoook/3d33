class_name WorldDecor
extends Node3D
## Props & vegetation (MultiMesh): grass on exposed grass tops, leaf tufts on tree canopies, the level's
## passive decorations (tufts, bushes, flowers, rocks, snow drifts, lanterns/garland bulbs, pines,
## fences, umbrellas) rebuilt as small 3D props consistent with the terrain style.

var _rng := RandomNumberGenerator.new()
var _mat_foliage: ShaderMaterial
var _mat_prop: ShaderMaterial
var _mat_glow: ShaderMaterial
## Validation: cave props placed in total / inside the sky mask (must be 0).
var cave_prop_count := 0
var cave_props_in_sky := 0
var near_silhouette_count := 0

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
				# lawn / leafy tops are WorldGrass's (dense blade carpet); deco tufts and the shrine stay here
				if WorldPalette.is_odyssey() and above_air and (m == WorldPalette.M_GRASS or (m == WorldPalette.M_FOLIAGE and _leafy(terrain, x, y, W, H))):
					var base := WorldPalette.base_color(id)
					var cnt := 5 if m == WorldPalette.M_GRASS else 3
					for k in cnt:
						var px := x + (k + _rng.randf()) / cnt
						var pz := _rng.randf_range(-2.6, 0.12)
						var s := _rng.randf_range(0.7, 1.35) * (1.0 if m == WorldPalette.M_GRASS else 0.8)
						var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s))
						grass_x.append(Transform3D(b, Vector3(px, -y + 0.02, pz)))
						grass_c.append(_vary(base.lightened(0.1), 0.12))
				if m == WorldPalette.M_FOLIAGE and _leafy(terrain, x, y, W, H):
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
	_build_cave_depth(lvl, terrain)
	if WorldPalette.is_odyssey():   # on day levels the crown edges are WorldFoliage's leaf cards
		_add_mm("Leaves", _leaf_mesh(), _mat_foliage, leaf_x, leaf_c)
	_add_mm("Rocks", _rock_mesh(), _mat_prop, rock_x, rock_c)
	_add_mm("Bulbs", _sphere(), _mat_glow, bulb_x, bulb_c, true)
	_add_mm("Cones", _cone(), _mat_prop, cone_x, cone_c)
	_add_mm("Boxes", _box(), _mat_prop, box_x, box_c)

## Depth layers for caves: stalactites / stalagmites behind the gameplay plane (z -2.8..-8, parallax
## mid-layer) and a few big dark near-camera silhouettes (z +3.5..+5.5) hanging from thick ceilings.
func _build_cave_depth(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var cols := terrain.fgcol_img
	var mid_x: Array[Transform3D] = []
	var mid_c: Array[Color] = []
	var fg_x: Array[Transform3D] = []
	var fg_c: Array[Color] = []
	for y in range(2, H - 2):
		for x in range(1, W - 1):
			var i := y * W + x
			# cave props only in air the sky flood never reaches (and never in the surface band's air)
			if terrain.solid[i] or terrain.sky[i] or terrain.pocket[i] or _near_sky(terrain, x, y, W, H):
				continue
			if terrain.wall_code.size() == W * H and terrain.wall_code[i] >= 2:
				continue   # day depth rooms (stone halls, earth caves): no free-floating cone props
			var ceil := terrain.solid[i - W] == 1
			var floor := terrain.solid[i + W] == 1
			if not ceil and not floor:
				continue
			var c := cols.get_pixel(x, y - 1 if ceil else y + 1).darkened(0.35)
			if ceil and _rng.randf() < 0.22:
				var len := _rng.randf_range(0.8, 3.8)
				var r := _rng.randf_range(0.18, 0.55) * clampf(len / 2.0, 0.6, 1.3)
				var b := Basis.from_scale(Vector3(r * 2.0, -len, r * 2.0)).rotated(Vector3.UP, _rng.randf() * TAU)
				mid_x.append(Transform3D(b, Vector3(x + _rng.randf(), -y + 0.3 - len * 0.5, _rng.randf_range(-8.0, -2.8))))
				mid_c.append(_vary(c, 0.15))
			if floor and _rng.randf() < 0.12:
				var len := _rng.randf_range(0.6, 2.6)
				var r := _rng.randf_range(0.25, 0.6)
				var b := Basis.from_scale(Vector3(r * 2.0, len, r * 2.0)).rotated(Vector3.UP, _rng.randf() * TAU)
				mid_x.append(Transform3D(b, Vector3(x + _rng.randf(), -y - 1.2 + len * 0.5, _rng.randf_range(-8.0, -2.8))))
				mid_c.append(_vary(c, 0.15))
	cave_props_in_sky = 0
	for t in mid_x + fg_x:
		var tx := clampi(int(floor(t.origin.x)), 0, W - 1)
		var ty := clampi(int(floor(-t.origin.y)), 0, H - 1)
		if terrain.sky[ty * W + tx]:
			cave_props_in_sky += 1
	cave_prop_count = mid_x.size() + fg_x.size()
	# moss tufts on underground rock tops and hanging moss under ceilings: break up stair silhouettes
	var moss_x: Array[Transform3D] = []
	var moss_c: Array[Color] = []
	for y in range(2, H - 2):
		for x in range(1, W - 1):
			var i := y * W + x
			if not terrain.solid[i] or terrain.sky[i - W] or terrain.sky[i + W]:
				continue
			var m: int = terrain.mat_ids[i]
			if m != WorldPalette.M_EARTH and m != WorldPalette.M_STONE and m != WorldPalette.M_WOOD and m != WorldPalette.M_BONE and m != WorldPalette.M_RUIN:
				continue
			var top := not terrain.solid[i - W]
			var under := not terrain.solid[i + W]
			var mc := Color(0.2, 0.3, 0.12).lerp(cols.get_pixel(x, y), 0.35).darkened(0.2)
			if top and _rng.randf() < 0.3:
				for k in 2:
					var s := _rng.randf_range(0.4, 0.7)
					moss_x.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s)),
						Vector3(x + _rng.randf(), -y + 0.02, _rng.randf_range(-1.8, 0.2))))
					moss_c.append(_vary(mc, 0.15))
			if under and _rng.randf() < 0.25:
				var s := _rng.randf_range(0.45, 0.8)
				moss_x.append(Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3(s, s * 1.1, s)),
					Vector3(x + _rng.randf(), -y - 1.0 + 0.02, _rng.randf_range(-1.8, 0.1))))
				moss_c.append(_vary(mc.darkened(0.2), 0.15))
	# pocket rims: tiny hanging root strands from the pore ceilings, crumbs on their floors
	var root_x: Array[Transform3D] = []
	var root_c: Array[Color] = []
	var crumb_x: Array[Transform3D] = []
	var crumb_c: Array[Color] = []
	for i in W * H:
		if not terrain.pocket[i]:
			continue
		var x := i % W
		var y := i / W
		if y < 1 or y >= H - 1:
			continue
		var rc := cols.get_pixel(x, y).darkened(0.45)
		if terrain.solid[i - W] and _rng.randf() < 0.45:
			var l := _rng.randf_range(0.25, 0.6)
			root_x.append(Transform3D(Basis(Vector3.FORWARD, _rng.randf_range(-0.3, 0.3)).scaled(Vector3(0.05, -l, 0.05)),
				Vector3(x + _rng.randf_range(0.2, 0.8), -y - l * 0.5, _rng.randf_range(-1.1, -0.85))))
			root_c.append(rc.darkened(0.3))
		if terrain.solid[i + W] and _rng.randf() < 0.6:
			var s := _rng.randf_range(0.08, 0.16)
			crumb_x.append(Transform3D(Basis.from_euler(Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * TAU).scaled(Vector3(s, s * 0.7, s)),
				Vector3(x + _rng.randf_range(0.2, 0.8), -y - 1.0 + s * 0.4, _rng.randf_range(-1.2, -0.85))))
			crumb_c.append(rc.lightened(0.15))
	_add_mm("PocketRoots", _box(), _mat_prop, root_x, root_c)
	_add_mm("PocketCrumbs", _pebble_mesh(), _mat_prop, crumb_x, crumb_c)
	# day: a small self-lit floor so tufts in unlit forest-hollow pockets never render exact black (Eastern Wood)
	_add_mm("CaveMoss", _grass_mesh(), _foliage_mat(1.0, 0.45, 0.1, 0.75) if terrain.day else _mat_foliage, moss_x, moss_c)
	_add_mm("CaveDepth", _cone(), _mat_prop, mid_x, mid_c)
	if not terrain.day:
		_build_near_silhouettes(lvl, terrain)   # day levels: near-camera roots read as floating lines (depth rooms carry the caves)
	if not WorldPalette.is_odyssey():
		_build_shrine(lvl, terrain)
		_build_floating_anchors(lvl, terrain)

var _near_mat: ShaderMaterial

## Sparse, edge-weighted foreground silhouettes very close to the camera (z +3..+6), per zone:
## hanging roots in earth tunnels and caves, icicles in the frozen cavern, chains in the drowned forge,
## big grass blades on the surface. Faded around the focus by near_silhouette.gdshader.
func _build_near_silhouettes(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var cone_x: Array[Transform3D] = []
	var cone_c: Array[Color] = []
	var chain_x: Array[Transform3D] = []
	var chain_c: Array[Color] = []
	var blade_x: Array[Transform3D] = []
	var blade_c: Array[Color] = []
	for y in range(2, H - 2):
		for x in range(1, W - 1):
			var i := y * W + x
			var z: int = terrain.zones[i]
			var ceil := not terrain.solid[i] and terrain.solid[i - W] and terrain.solid[i - 2 * W]
			var ground := terrain.solid[i] and not terrain.solid[i - W]
			if not ceil or terrain.sky[i] or _rng.randf() > 0.05 or _near_sky(terrain, x, y, W, H):
				continue
			if terrain.wall_code.size() == W * H and terrain.wall_code[i] >= 5:
				continue   # no hanging roots in built stone rooms
			var p := Vector3(x + _rng.randf(), -y + 1.2, _rng.randf_range(3.2, 5.8))
			var shape := 0.0
			var col := Color(0.035, 0.025, 0.02)
			var w := _rng.randf_range(2.0, 3.4)
			var len := _rng.randf_range(3.5, 7.0)
			if z == WorldPalette.Z_ICE:
				shape = 1.0
				col = Color(0.06, 0.09, 0.14)
				w = _rng.randf_range(1.0, 1.8)
				len = _rng.randf_range(2.5, 5.0)
			elif z == WorldPalette.Z_DEEP:
				shape = 2.0
				col = Color(0.02, 0.018, 0.02)
				w = 1.0
				len = _rng.randf_range(4.0, 8.0)
			# card: top edge at the anchor, hanging down
			cone_x.append(Transform3D(Basis.from_scale(Vector3(w, len, 1.0)), p - Vector3(0, len * 0.5, 0)))
			cone_c.append(Color(col.r, col.g, col.b, 1.0 + shape * 10.0 + _rng.randf() * 0.9))
	_near_mat = ShaderMaterial.new()
	_near_mat.shader = load("res://shaders/world/near_silhouette.gdshader")
	var card := QuadMesh.new()
	card.size = Vector2(1, 1)
	_add_mm("NearSilhouettes", _vertex_white(card), _near_mat, cone_x, cone_c, false, false, true)
	near_silhouette_count = cone_x.size()

## Leaf clusters / canopy grass: Odyssey's trees are the surface band; other levels' foliage anywhere near sky.
func _leafy(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> bool:
	if WorldPalette.is_odyssey():
		return y < 22
	return _near_sky(terrain, x, y, W, H)

## FV finale: dense wind-swept grass on every exposed top of the summit shrine peak (all leaning east).
func _build_shrine(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var fx: Array[Transform3D] = []
	var fc: Array[Color] = []
	var stem_x: Array[Transform3D] = []
	var stem_c: Array[Color] = []
	var r := WorldPalette.FV_RECT_SHRINE
	var flower_cols := [Color(1.0, 0.85, 0.25), Color(1.0, 0.5, 0.7), Color(0.95, 0.95, 1.0), Color(0.6, 0.55, 1.0), Color(1.0, 0.6, 0.25)]
	for y in range(r.position.y, mini(r.end.y, H - 1)):
		for x in range(r.position.x, mini(r.end.x, W - 1)):
			var i := y * W + x
			if not terrain.solid[i]:
				continue
			# every tile of the peak that touches open air gets lush grass on that face (tops dense, sides lighter)
			var top := not terrain.solid[i - W]
			var left := not terrain.solid[i - 1]
			var right := not terrain.solid[i + 1]
			if not (top or left or right):
				continue
			var n := 2 if top else 0   # a few tall wind-swept accents; WorldGrass carpets the shrine
			for k in n:
				var sc := _rng.randf_range(0.9, 1.7)
				var px := x + _rng.randf()
				var py := -y + 0.02 if top else -y - _rng.randf_range(0.05, 0.6)
				if not top:
					px = x + (0.02 if left else 0.98)
				var lean := -0.4 + _rng.randf_range(-0.12, 0.12)
				var b := Basis(Vector3.FORWARD, lean).scaled(Vector3(sc, sc * 1.25, sc))
				xs.append(Transform3D(b, Vector3(px, py, _rng.randf_range(-1.8, 0.3))))
				cs.append(_vary(Color(0.42, 0.66, 0.2).lerp(Color(0.62, 0.72, 0.25), _rng.randf() * 0.4), 0.1))
			if top:
				for k in 5:
					var fcol: Color = flower_cols[_rng.randi() % flower_cols.size()]
					var h := _rng.randf_range(0.25, 0.55)
					var p := Vector3(x + _rng.randf(), -y + h, _rng.randf_range(-1.2, 0.3))
					fx.append(Transform3D(Basis().scaled(Vector3(1.0, 0.6, 1.0) * _rng.randf_range(0.15, 0.22)), p))
					fc.append(Color(fcol.r, fcol.g, fcol.b, 0.6))
					stem_x.append(Transform3D(Basis().scaled(Vector3(0.025, h, 0.025)), p - Vector3(0, h * 0.5, 0)))
					stem_c.append(Color(0.25, 0.45, 0.15))
	var m := _foliage_mat(2.2, 0.6, 0.0, 0.7)
	_add_mm("ShrineGrass", _grass_mesh(), m, xs, cs)
	_add_mm("ShrineFlowers", _sphere(), _mat_glow, fx, fc, true)
	_add_mm("ShrineStems", _box(), _mat_prop, stem_x, stem_c)

## Floating art (the ΣX logo, the Winners' Scroll, marble V-birds): vines and roots trailing below them,
## set back behind the gameplay plane (z -1.2..-2.2) so they anchor the piece without occluding play.
func _build_floating_anchors(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var logo := Rect2i(300, 14, 46, 29)
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for y in range(1, H - 1):
		for x in W:
			var i := y * W + x
			if not terrain.solid[i] or terrain.solid[i + W] or not terrain.sky[i + W]:
				continue
			var pt := Vector2i(x, y)
			var bird: bool = lvl.fg[i] == 87
			var art := logo.has_point(pt) or bird
			if WorldPalette.FV_RECT_SCROLL.has_point(pt):
				continue   # the scroll hangs clean: strands read as ink drips
			# every sky-facing underside: sparse roots / moss drips; art pieces get a little more
			if _rng.randf() > (0.25 if bird else (0.55 if art else 0.22)):
				continue
			var n := 1 if bird else 2
			for k in n:
				var l := _rng.randf_range(0.8, 2.2) if bird else _rng.randf_range(1.2, 4.5)
				# soft-edged card, a little wider than the old 0.06 box (which aliased under sub-pixel motion)
				var b := Basis(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12)).scaled(Vector3(0.1, l, 1.0))
				xs.append(Transform3D(b, Vector3(x + _rng.randf_range(0.15, 0.85), -y - 1.0 - l * 0.5, _rng.randf_range(-2.2, -1.2))))
				cs.append(_vary(Color(0.2, 0.36, 0.12) if not bird else Color(0.55, 0.6, 0.5), 0.15))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/world/decor_strand.gdshader")
	var card := QuadMesh.new()
	card.size = Vector2(1, 1)
	_add_mm("FloatingVines", _vertex_white(card), m, xs, cs)

func _near_sky(terrain: WorldTerrain, x: int, y: int, W: int, H: int) -> bool:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var nx := clampi(x + dx, 0, W - 1)
			var ny := clampi(y + dy, 0, H - 1)
			if terrain.sky[ny * W + nx]:
				return true
	return false

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
## shape_custom: colour alpha encodes 1 + shape*10 + seed (near-silhouette cards).
func _add_mm(nm: String, mesh: Mesh, mat: Material, xs: Array[Transform3D], cs: Array[Color], glow := false, cast_shadows := false, shape_custom := false) -> void:
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
		if shape_custom:
			var code := c.a - 1.0
			var shp := floorf(code / 10.0 + 0.001)
			mm.set_instance_custom_data(i, Color(shp, code - shp * 10.0, 0, 0))
		else:
			mm.set_instance_custom_data(i, Color(1, 1, 1, e))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

func update_focus(world_pos: Vector3, _delta: float) -> void:
	if _near_mat:
		_near_mat.set_shader_parameter("focus", world_pos)
