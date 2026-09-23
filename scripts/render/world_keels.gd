class_name WorldKeels
extends Node3D
## Day levels (Forgotten Veil's story: ancient ruins held in the sky by old magic): every FLOATING solid
## cluster (not connected to the level border / ground, with open sky below it) grows a tapered inverted
## rock-and-earth KEEL beneath it, strictly behind the gameplay plane (z -1.2 at the top edge receding to
## ~-3.6 at the tip), darker and hazed with depth, with faint pulsing levitation-rune cracks on its
## underside. Small clusters (V-birds, ledges) get a mini keel. Exposes keel_sites for FX.

const MAX_CLUSTER := 1500      # bigger components count as ground masses
const MAX_WIDTH := 14.0        # wider clusters get no keel
const Z_TOP := -1.2
const Z_TIP := -3.6

## [{tip: Vector3 (world), width: float (tiles), depth: float (tiles below the cluster bottom), rune: Vector3}]
var keel_sites: Array = []

## dep (optional, WorldDepth): the island's extruded depth; the keel then spans the whole underside
## (front sheet from z Z_TOP and back sheet from the volume's back edge, meeting at a mid-depth tip).
func build(lvl: EELevel, terrain: WorldTerrain, dep: WorldDepth = null) -> void:
	var W := lvl.width
	var H := lvl.height
	var seen := PackedByteArray()
	seen.resize(W * H)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vb := WorldDepth.Bucket.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for start in W * H:
		if seen[start] or not _in_mass(start, terrain, dep):
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var grounded := false
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			if x <= 1 or x >= W - 2 or y >= H - 2:
				grounded = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					if seen[j] or not _in_mass(j, terrain, dep):
						continue
					seen[j] = 1
					comp.append(j)
		if grounded or comp.size() > MAX_CLUSTER:
			continue
		# per column: lowest tile of the cluster that has open sky directly below
		var bottom := {}
		var x0 := W
		var x1 := -1
		for i in comp:
			var x := i % W
			var y := i / W
			if y + 1 < H and terrain.sky[(y + 1) * W + x] and not _in_mass((y + 1) * W + x, terrain, dep):
				bottom[x] = maxi(bottom.get(x, -1), y)
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
		if bottom.is_empty():
			continue
		var width := float(x1 - x0 + 1)
		if width < 2.0:
			continue   # a lone floating block with a dark spike under it reads as a hazard
		if width > MAX_WIDTH:
			continue   # big floating ruins: one keel fan would sweep across their play rooms; the depth volume's own underside carries them
		if not _isolated(comp, terrain, dep, W, H):
			continue   # a platform inside a tower room / beside a structure is not a sky island: no keel
		# pale marble sculptures (the V-birds) get only a tiny weathered-stone stub
		var marble := 0
		for i in comp:
			if terrain.mat_ids[i] == WorldPalette.M_MARBLE:
				marble += 1
		var pale := marble * 2 > comp.size()
		var depth := minf(clampf(sqrt(width) * rng.randf_range(1.1, 1.6), 1.0, 4.0), 1.2 * width)
		if pale:
			depth = minf(depth, 0.45 * width)
		var cx := (x0 + x1 + 1) * 0.5
		var tip_x := cx + rng.randf_range(-0.2, 0.2) * width
		var ext := 0.0
		if dep:
			for x in bottom:
				ext = maxf(ext, dep.depth[bottom[x] * W + x])
		# the tip sits under the middle of the extruded island (the volume's own underside closes the rest)
		var z_tip := Z_TIP if ext <= 0.0 else Z_TOP - clampf(ext * 0.5, 1.0, 1.8)
		var ybot := 0
		for x in bottom:
			ybot = maxi(ybot, bottom[x])
		if dep:
			# blocky world: a stepped voxel keel in the island's own underside rock (depth-volume material)
			depth = float(maxi(1, int(round(depth))))
			_voxel_keel(vb, x0, x1, ybot, int(depth), tip_x, maxf(ext, 1.0), bottom)
		else:
			_keel(st, bottom, x0, x1, depth, tip_x, rng, Z_TOP, z_tip, 1.0, 1.0 if pale else 0.0)
		keel_sites.append({"tip": Vector3(tip_x, -(ybot + 1) - depth, z_tip), "width": width, "depth": depth,
			"rune": Vector3(cx, -(ybot + 1) - depth * 0.35, (Z_TOP + z_tip) * 0.5)})
	if keel_sites.is_empty():
		return
	if dep:
		if vb.v.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vb.v
		arr[Mesh.ARRAY_NORMAL] = vb.n
		arr[Mesh.ARRAY_TEX_UV] = vb.uv
		arr[Mesh.ARRAY_TEX_UV2] = vb.uv2
		var vm := ArrayMesh.new()
		vm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var vmi := MeshInstance3D.new()
		vmi.name = "Keels"
		vmi.mesh = vm
		vmi.material_override = dep.material
		vmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(vmi)
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Keels"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/world/keel.gdshader")
	m.set_shader_parameter("detail_nrm", terrain.material.get_shader_parameter("detail_nrm"))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Stepped keel: `rows` tile-high slabs under the island, each narrower (in x) and shallower (in z) than the
## one above, ending in a blunt 1-tile-wide stub. Faces carry the source tile of the island's underside
## (so the colour / material match its rock) and kind 13 (no voxel bevel lookup).
func _voxel_keel(b: WorldDepth.Bucket, x0: int, x1: int, ybot: int, rows: int, tip_x: float, ext: float, bottom: Dictionary) -> void:
	var w0 := float(x1 - x0 + 1)
	for k in rows:
		var t := float(k + 1) / float(rows + 1)
		var w := maxf(1.0, round(w0 * pow(1.0 - t, 0.85)))
		var cx := lerpf((x0 + x1 + 1) * 0.5, tip_x, t)
		var a := int(round(cx - w * 0.5))
		a = clampi(a, x0, maxi(x0, x1 + 1 - int(w)))
		var e := maxf(0.8, ext * (1.0 - t * 0.7))
		var y := ybot + 1 + k
		var src_x := clampi(int(cx), x0, x1)
		var src_y: int = bottom.get(src_x, ybot)
		_box(b, float(a), float(a) + w, -float(y), -float(y) - 1.0, Z_TOP - 0.05, Z_TOP - 0.05 - e, Vector2(src_x + 0.5, src_y + 0.5))

func _box(b: WorldDepth.Bucket, xa: float, xb: float, ya: float, yb: float, za: float, zb: float, uv: Vector2) -> void:
	var c := [Vector3(xa, yb, zb), Vector3(xb, yb, zb), Vector3(xb, ya, zb), Vector3(xa, ya, zb),
		Vector3(xa, yb, za), Vector3(xb, yb, za), Vector3(xb, ya, za), Vector3(xa, ya, za)]
	# faces: +z (front), -x, +x, -y (under), +y (top, hidden under the island but closes the box)
	var faces := [[[4, 5, 6, 7], Vector3(0, 0, 1)], [[0, 4, 7, 3], Vector3(-1, 0, 0)], [[5, 1, 2, 6], Vector3(1, 0, 0)],
		[[0, 1, 5, 4], Vector3(0, -1, 0)], [[3, 7, 6, 2], Vector3(0, 1, 0)]]
	for f in faces:
		var idx: Array = f[0]
		var out: Vector3 = f[1]
		var p := [c[idx[0]], c[idx[1]], c[idx[2]], c[idx[3]]]
		var nrm: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
		if nrm.dot(out) > 0.0:
			p = [p[0], p[3], p[2], p[1]]
		for j in [0, 1, 2, 0, 2, 3]:
			b.v.append(p[j])
			b.n.append(out)
			b.uv.append(uv)
			b.uv2.append(Vector2(1.0, 13.0))

const ISLAND_CLEAR := 4        # a keeled island has no other mass within this many tiles (sides and below)

## True for a genuinely free-floating island: nothing else within ISLAND_CLEAR tiles left, right or below.
static func _isolated(comp: PackedInt32Array, terrain: WorldTerrain, dep: WorldDepth, W: int, H: int) -> bool:
	var own := {}
	var x0 := W
	var x1 := -1
	var y0 := H
	var y1 := -1
	for i in comp:
		own[i] = true
		x0 = mini(x0, i % W); x1 = maxi(x1, i % W)
		y0 = mini(y0, i / W); y1 = maxi(y1, i / W)
	for y in range(y0, mini(H, y1 + ISLAND_CLEAR + 1)):
		for x in range(maxi(0, x0 - ISLAND_CLEAR), mini(W, x1 + ISLAND_CLEAR + 1)):
			var j := y * W + x
			if not own.has(j) and _in_mass(j, terrain, dep):
				return false
	return true

## Connectivity uses the whole mass (solid + back walls + pockets) when the depth field is known, so wings,
## bridges and ledges attached to a tower through its back wall are NOT free-floating islands.
static func _in_mass(i: int, terrain: WorldTerrain, dep: WorldDepth) -> bool:
	return dep.mass[i] == 1 if dep else terrain.solid[i] == 1

## Tapered keel: a smooth hull from the cluster's bottom edge (z Z_TOP) down to one tip point (z Z_TIP).
## Vertex colour: r = v (0 at the top edge, 1 at the tip), g = random per keel (rune seed).
## z0 = z of the sheet's top edge, z1 = tip z; bulge -1 = a back-facing sheet (reversed winding).
func _keel(st: SurfaceTool, bottom: Dictionary, x0: int, x1: int, depth: float, tip_x: float, rng: RandomNumberGenerator,
		z0: float = Z_TOP, z1: float = Z_TIP, bulge: float = 0.0, pale: float = 0.0) -> void:
	var rows := 10
	var seed := rng.randf()
	var cols: Array[float] = []
	var tops: Array[float] = []
	var last := -1
	for x in range(x0, x1 + 2):
		var bx: int = bottom.get(mini(x, x1), -1)
		if bx < 0:
			bx = last
		if bx < 0:
			continue
		last = bx
		cols.append(float(x))
		tops.append(-(bx + 1.0) + 0.15)   # tuck slightly up under the cluster
	if cols.size() < 2:
		return
	var grid := []
	for r in rows + 1:
		var v := float(r) / rows
		var row := []
		for k in cols.size():
			var x0f: float = cols[k]
			# narrow toward the tip with a rounded (not linear) taper, slightly lumpy
			var t := pow(v, 0.8)
			var px := lerpf(x0f, tip_x, t) + sin(v * 7.0 + k * 1.7 + seed * 10.0) * 0.12 * (1.0 - v)
			var py := lerpf(tops[k], tops[k] - depth, pow(v, 1.15)) - (1.0 - absf(float(k) / (cols.size() - 1) * 2.0 - 1.0)) * depth * 0.15 * v * (1.0 - v) * 4.0
			var bow := 0.5 * sin(v * PI) * (1.0 - absf(float(k) / (cols.size() - 1) * 2.0 - 1.0))
			var pz := lerpf(z0, z1, v) + (bow if bulge < -0.5 else -bow)
			row.append(Vector3(px, py, pz))
		grid.append(row)
	for r in rows:
		for k in cols.size() - 1:
			var a: Vector3 = grid[r][k]
			var b: Vector3 = grid[r][k + 1]
			var c: Vector3 = grid[r + 1][k]
			var d: Vector3 = grid[r + 1][k + 1]
			var va := float(r) / rows
			var vb := float(r + 1) / rows
			var order := [[a, va], [c, vb], [b, va], [b, va], [c, vb], [d, vb]]
			if bulge < -0.5:
				order = [[a, va], [b, va], [c, vb], [b, va], [d, vb], [c, vb]]
			for pv in order:
				st.set_color(Color(pv[1], seed, pale))
				st.set_uv(Vector2((pv[0] as Vector3).x, (pv[0] as Vector3).y))
				st.add_vertex(pv[0])
