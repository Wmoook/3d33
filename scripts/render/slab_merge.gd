class_name SlabMerge
## Shared layer-slab builder (WorldForest block trees, sky's cave rock layers): tiles on a few depth layers,
## greedy-merged per layer into big boxes so each tile-stepped mass is a handful of slabs lying in ONE plane,
## one colour per (layer, material) so merged faces never step in tone. The occupancy image lets a shader find
## mass silhouettes per tile (bevel / edge shade only where a mass meets air or another class).
##
## grid: Vector3i(tile x, world y (= floor of the world-space y, up), layer) -> [mat id, slab depth, linear colour]
## fronts: front-face world z per layer; fogs: per-layer value written to custom.g.
## mat_class: Callable(mat: int) -> int in 1..4: materials of one class form one mass for the silhouettes
##            (an invalid Callable = every material its own class, clamped to 1..4).
## Returns {"xs": Array[Transform3D], "cs": Array[Color], "cu": Array[Color] (r mat, g fog, b layer, a depth),
##          "occ": Image (RGBA8, channel = layer 0..3, value = class / 4, 0 = empty), "occ_origin": Vector2}.
## Up to 4 layers (one occupancy channel each).
static func merge(grid: Dictionary, fronts: Array[float], fogs: Array[float], mat_class: Callable) -> Dictionary:
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var cu: Array[Color] = []
	if grid.is_empty():
		return {"xs": xs, "cs": cs, "cu": cu, "occ": Image.create(1, 1, false, Image.FORMAT_RGBA8), "occ_origin": Vector2.ZERO}
	var sum := {}
	var cnt := {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for key: Vector3i in grid:
		var e: Array = grid[key]
		var sk := Vector2i(key.z, int(e[0]))
		sum[sk] = (sum.get(sk, Color(0, 0, 0)) as Color) + (e[2] as Color)
		cnt[sk] = int(cnt.get(sk, 0)) + 1
		lo = Vector2i(mini(lo.x, key.x), mini(lo.y, key.y))
		hi = Vector2i(maxi(hi.x, key.x), maxi(hi.y, key.y))
	var org := lo - Vector2i(1, 1)
	var img := Image.create(hi.x - lo.x + 3, hi.y - lo.y + 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for key: Vector3i in grid:
		var mat := int((grid[key] as Array)[0])
		var cls: int = int(mat_class.call(mat)) if mat_class.is_valid() else mat
		var px := img.get_pixel(key.x - org.x, key.y - org.y)
		px[clampi(key.z, 0, 3)] = float(clampi(cls, 1, 4)) / 4.0
		img.set_pixel(key.x - org.x, key.y - org.y, px)
	var done := {}
	var keys := grid.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y > b.y if a.y != b.y else a.x < b.x)
	for key: Vector3i in keys:
		if done.has(key):
			continue
		var e: Array = grid[key]
		var mat := int(e[0])
		var depth: float = e[1]
		var w := 1
		while _merge_ok(grid, key + Vector3i(w, 0, 0), mat, depth, done):
			w += 1
		var h := 1
		while true:
			var ok := true
			for dx in w:
				if not _merge_ok(grid, key + Vector3i(dx, -h, 0), mat, depth, done):
					ok = false
					break
			if not ok:
				break
			h += 1
		for dy in h:
			for dx in w:
				done[key + Vector3i(dx, -dy, 0)] = true
		var sk := Vector2i(key.z, mat)
		var c := Vector3(key.x + w * 0.5, key.y + 1.0 - h * 0.5, fronts[key.z] - depth * 0.5)
		xs.append(Transform3D(Basis().scaled(Vector3(w, h, depth)), c))
		cs.append((sum[sk] as Color) / float(cnt[sk]))
		cu.append(Color(float(mat), fogs[key.z], float(key.z), depth))
	return {"xs": xs, "cs": cs, "cu": cu, "occ": img, "occ_origin": Vector2(org)}

## The merged slabs as one MultiMesh of unit boxes (instance colour + custom data as merge() returns them).
static func multimesh(res: Dictionary) -> MultiMesh:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = cube
	var xs: Array[Transform3D] = res.xs
	var cs: Array[Color] = res.cs
	var cu: Array[Color] = res.cu
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_color(k, cs[k])
		mm.set_instance_custom_data(k, cu[k])
	return mm

static func _merge_ok(grid: Dictionary, k: Vector3i, mat: int, depth: float, done: Dictionary) -> bool:
	if done.has(k) or not grid.has(k):
		return false
	var e: Array = grid[k]
	return int(e[0]) == mat and is_equal_approx(float(e[1]), depth)
