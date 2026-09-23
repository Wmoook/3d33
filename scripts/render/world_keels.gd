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
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for start in W * H:
		if seen[start] or not terrain.solid[start]:
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
					if seen[j] or not terrain.solid[j]:
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
			if y + 1 < H and terrain.sky[(y + 1) * W + x] and not terrain.solid[(y + 1) * W + x]:
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
		# pale marble sculptures (the V-birds) get only a tiny weathered-stone stub
		var marble := 0
		for i in comp:
			if terrain.mat_ids[i] == WorldPalette.M_MARBLE:
				marble += 1
		var pale := marble * 2 > comp.size()
		var depth := minf(clampf(sqrt(width) * rng.randf_range(1.3, 2.0), 1.0, 6.0), 1.2 * width)
		if pale:
			depth = minf(depth, 0.45 * width)
		var cx := (x0 + x1 + 1) * 0.5
		var tip_x := cx + rng.randf_range(-0.2, 0.2) * width
		var ext := 0.0
		if dep:
			for x in bottom:
				ext = maxf(ext, dep.depth[bottom[x] * W + x])
		# the tip sits under the middle of the extruded island (the volume's own underside closes the rest)
		var z_tip := Z_TIP if ext <= 0.0 else Z_TOP - clampf(ext * 0.5, 1.2, 4.0)
		_keel(st, bottom, x0, x1, depth, tip_x, rng, Z_TOP, z_tip, 1.0, 1.0 if pale else 0.0)
		var ybot := 0
		for x in bottom:
			ybot = maxi(ybot, bottom[x])
		keel_sites.append({"tip": Vector3(tip_x, -(ybot + 1) - depth, z_tip), "width": width, "depth": depth,
			"rune": Vector3(cx, -(ybot + 1) - depth * 0.35, (Z_TOP + z_tip) * 0.5)})
	if keel_sites.is_empty():
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
