class_name WorldForest
extends Node3D
## Forgotten Veil forest-depth illusion. Every forest region is detected from the painting: a hollow of forest
## bg (0 black shade, 505/508 dark gaps, 510 undergrowth, 511 far trunks, 512 bark, 534) directly under a
## canopy of tree crowns (WorldGrass.canopy_map). World drops its back wall / depth volume there
## (hollow_image) and each region fills the space behind the play plane with a deep forest seen straight-on:
##   near bark trunks with moss (the painted 512 columns), mid and far trunks dissolving into green-blue haze
##   (511 columns = far trunks), ferns at the base (510), hanging leaves + vines under the canopy, slanted sun
##   shafts from canopy gaps, fireflies + drifting pollen, and a far haze card (black gaps = deepest shade).
## Hard mask: every layer clips to fragments whose camera ray crosses the play plane inside a hollow tile
## (forest_mask.gdshaderinc), so parallax never draws over the painting's sky, halls or solids.
## Fade: a region's illusion fades in only while the focus is inside / near it (update_focus); outside, the
## hollow shows just the painting's deep shade. Everything sits behind the ball (z < -1.9); the pine's needle
## boughs (fg 17) are the only front detail and stay on the pine's own tiles.

## Major forests (read by WorldVoxel for its far canopy band). Detected regions: regions(terrain).
static var RECTS: Array[Rect2i] = [Rect2i(0, 25, 86, 38), Rect2i(366, 82, 34, 30)]
const FOREST_BG := [0, 505, 508, 510, 511, 512, 534]
const LEAFY_IDS := [14, 17, 19, 34, 35, 36]
const TRUNK_IDS := [47, 48]
const PINE_ID := 17
const MIN_REGION := 24
const Z_FAR := -10.5
const Z_NEAR_512 := -2.45
const Z_FAR_511 := -6.2
const MID_BANDS := [-4.0, -5.4, -7.0]
const FAR_BANDS := [-8.2, -9.6]
const DEEP := Color(0.03, 0.05, 0.035)
const FOG_NEAR := Color(0.07, 0.13, 0.08)
const POISSON_R := 1.7          # min trunk spacing at the front (grows with depth)
const HAZE := Color(0.1, 0.2, 0.17)
const BARK_512 := Color(0.47, 0.37, 0.23)
const BARK_511 := Color(0.33, 0.14, 0.13)
const FADE_IN := 2.0      # tiles outside the region where the fade starts
const FADE_OUT := 8.0     # ... and where it reaches 0
const FAR_VIS := 0.6      # the fade's floor: faded regions keep a dim forest

var stats := {}
var region_list: Array[Rect2i] = []
var _regions: Array = []            # [{rect, node, mats: [ShaderMaterial], particles: [GPUParticles3D], vis}]
var _rng := RandomNumberGenerator.new()
var _hollow_tex: ImageTexture
var _pine_mat: ShaderMaterial
var _block_mats: Array[ShaderMaterial] = []
var _canopy_y_hint := 0.0

# ---------------------------------------------------------------------------------------------- detection

## Fg trunk tiles: 47/48 in a narrow column (<= 5 wide) with a leafy crown within 12 rows above.
static func is_trunk_tile(lvl: EELevel, x: int, y: int) -> bool:
	if WorldPalette.is_odyssey():
		return false
	var W := lvl.width
	var id: int = lvl.fg[y * W + x]
	if not TRUNK_IDS.has(id):
		return false
	var l := x
	while l > 0 and TRUNK_IDS.has(int(lvl.fg[y * W + l - 1])) and x - l < 6:
		l -= 1
	var r := x
	while r < W - 1 and TRUNK_IDS.has(int(lvl.fg[y * W + r + 1])) and r - x < 6:
		r += 1
	if r - l + 1 > 5:
		return false
	for d in range(1, 13):
		if y - d < 0:
			break
		if LEAFY_IDS.has(int(lvl.fg[(y - d) * W + x])):
			return true
	return false

## 1 = forest-hollow air: not solid, not a pore, forest bg, its ceiling (first solid above, <= 16 rows) is a
## tree crown or a trunk under a crown, ground within 14 rows below; components < MIN_REGION tiles dropped.
## Earth passages (ceiling = earth/stone) are world's, not forest.
## World's structure-interior tiles (terrain.wall_code >= 5: recessed stone rooms / windows) are never forest.
static func stone_room(terrain: WorldTerrain, i: int) -> bool:
	return terrain.wall_code.size() > i and terrain.wall_code[i] >= 5

static func hollow_mask(terrain: WorldTerrain) -> PackedByteArray:
	if terrain.has_meta(&"forest_hollow"):
		return terrain.get_meta(&"forest_hollow")
	var W := terrain.W
	var H := terrain.H
	var out := PackedByteArray()
	out.resize(W * H)
	if WorldPalette.is_odyssey():
		terrain.set_meta(&"forest_hollow", out)
		return out
	var cm := WorldGrass.canopy_map(terrain)
	var lvl := terrain.level
	for y in range(1, H - 1):
		for x in W:
			var i := y * W + x
			if terrain.solid[i] or terrain.pocket[i] or not FOREST_BG.has(int(lvl.bg[i])):
				continue
			if stone_room(terrain, i):
				continue   # structure interiors are world's recessed stone rooms
			var ceil_ok := false
			var ceil_y := -1
			for d in range(1, 21):
				if y - d < 0:
					break
				var j := (y - d) * W + x
				if terrain.pocket[j]:
					continue   # pores in the crown don't end the search
				if terrain.solid[j]:
					ceil_ok = cm[j] == 1 or lvl.fg[j] == PINE_ID or is_trunk_tile(lvl, x, y - d)
					ceil_y = y - d
					break
			if not ceil_ok:
				continue
			for d in range(1, 15):
				if y + d >= H:
					break
				var j := (y + d) * W + x
				if terrain.solid[j] and not cm[j]:
					# a forest floor is at most 13 rows under the canopy (deeper = a shaft into the earth: world's)
					if y + d - ceil_y <= 13:
						out[i] = 1
					break
	# grow into neighbouring forest-bg air (columns whose ceiling is a pore or a far crown edge), 3 passes
	for pass_i in 3:
		var add := PackedInt32Array()
		for y in range(1, H - 1):
			for x in range(1, W - 1):
				var i := y * W + x
				if out[i] or terrain.solid[i] or stone_room(terrain, i):
					continue
				var nb := int(out[i - 1]) + int(out[i + 1]) + int(out[i + W]) + int(out[i - W])
				# odd-bg holes inside the forest (the spawn tile's bg 547...) join when mostly surrounded
				if not FOREST_BG.has(int(lvl.bg[i])) and nb < 2:
					continue
				if out[i - 1] or out[i + 1] or out[i + W]:   # sideways / upward only (never down a shaft)
					add.append(i)
		for i in add:
			out[i] = 1
	# drop tiny components (stray gaps in crowns / trunks)
	var seen := PackedByteArray()
	seen.resize(W * H)
	var rects: Array[Rect2i] = []
	for i0 in W * H:
		if not out[i0] or seen[i0]:
			continue
		var comp := PackedInt32Array([i0])
		seen[i0] = 1
		var q := 0
		var r := Rect2i(i0 % W, i0 / W, 1, 1)
		while q < comp.size():
			var i := comp[q]
			q += 1
			var x := i % W
			var y := i / W
			r = r.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if out[j] and not seen[j]:
					seen[j] = 1
					comp.append(j)
		if comp.size() < MIN_REGION:
			for i in comp:
				out[i] = 0
		else:
			rects.append(r)
	# pores inside / just under each region (the pine's walkable air pockets, the notches in the floor strip)
	# are forest too: no grey slab may show in any hollow air of a forest
	var merged := _merge_rects(rects)
	var grown: Array[Rect2i] = []
	for r: Rect2i in merged:
		var g := Rect2i(r.position.x - 1, r.position.y - 4, r.size.x + 2, r.size.y + 10).intersection(Rect2i(0, 0, W, H))
		for y in range(g.position.y, g.end.y):
			for x in range(g.position.x, g.end.x):
				var i := y * W + x
				if not terrain.solid[i] and terrain.pocket[i] and FOREST_BG.has(int(lvl.bg[i])) and not stone_room(terrain, i):
					out[i] = 1
					r = r.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
		grown.append(r)
	# crown gaps: painted forest-bg air between / inside the crowns (bg 505/508/510/512...) is forest art, not
	# sky: without this the open sky behind showed through each little gap in the canopy
	for gi in grown.size():
		var r: Rect2i = grown[gi]
		var g := Rect2i(r.position.x - 6, r.position.y - 12, r.size.x + 12, r.size.y + 12).intersection(Rect2i(0, 0, W, H))
		for y in range(maxi(g.position.y, 1), mini(g.end.y, H - 1)):
			for x in range(maxi(g.position.x, 1), mini(g.end.x, W - 1)):
				var i := y * W + x
				if out[i] or terrain.solid[i] or stone_room(terrain, i) or not FOREST_BG.has(int(lvl.bg[i])):
					continue
				var near_crown := false
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var j := (y + dy) * W + x + dx
						if j >= 0 and j < W * H and (cm[j] or lvl.fg[j] == PINE_ID):
							near_crown = true
				if near_crown:
					out[i] = 1
					r = r.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
		grown[gi] = r
	# pores (forest-bg pockets) touching the hollow anywhere, even just past a region's rect (e.g. (231,155)):
	# their back wall is discarded next to the hollow, so they must show forest too
	for pass_i in 2:
		var add := PackedInt32Array()
		for y in range(1, H - 1):
			for x in range(1, W - 1):
				var i := y * W + x
				if out[i] or terrain.solid[i] or not terrain.pocket[i] or stone_room(terrain, i) or not FOREST_BG.has(int(lvl.bg[i])):
					continue
				if out[i - 1] or out[i + 1] or out[i - W] or out[i + W]:
					add.append(i)
		for i in add:
			out[i] = 1
			for gi in grown.size():
				if grown[gi].grow(2).has_point(Vector2i(i % W, i / W)):
					grown[gi] = grown[gi].expand(Vector2i(i % W, i / W)).expand(Vector2i(i % W + 1, i / W + 1))
					break
	terrain.set_meta(&"forest_hollow", out)
	terrain.set_meta(&"forest_regions", grown)
	return out

## Detected forest regions (hollow bounds, nearby ones merged). Tile rects.
static func regions(terrain: WorldTerrain) -> Array[Rect2i]:
	hollow_mask(terrain)
	var r: Array[Rect2i] = []
	if terrain.has_meta(&"forest_regions"):
		r.assign(terrain.get_meta(&"forest_regions"))
	return r

static func _merge_rects(rs: Array[Rect2i]) -> Array[Rect2i]:
	var out: Array[Rect2i] = rs.duplicate()
	var merged := true
	while merged:
		merged = false
		for a in out.size():
			for b in range(a + 1, out.size()):
				if out[a].grow(3).intersects(out[b]):
					out[a] = out[a].merge(out[b])
					out.remove_at(b)
					merged = true
					break
			if merged:
				break
	return out

## The hollow mask dilated one tile into the SOLID tiles around it (R8, 255): world discards its back-wall
## layers there too and my layers draw behind the solids' rounded edges, so no sky / wall sliver can show
## between a solid's silhouette and the forest behind it. Air outside the hollow is never included.
## room_border: also stone-room tiles bordering the hollow (WorldForest's own draw mask only; world keeps the
## plain image so its room faces aren't forest-fogged).
static func hollow_image(terrain: WorldTerrain, room_border := false) -> Image:
	var m := hollow_mask(terrain)
	var W := terrain.W
	var H := terrain.H
	var b := PackedByteArray()
	b.resize(m.size())
	for y in H:
		for x in W:
			var i := y * W + x
			if m[i]:
				b[i] = 255
				continue
			if not terrain.solid[i]:
				# open air right under the hollow (a shaft / cave mouth dropping out of the forest floor): rays
				# through it look back up into the forest, so the backstop must cover it too
				if y > 0 and m[i - W] and not stone_room(terrain, i):
					b[i] = 255
				# a stone-room tile bordering the hollow: rays entering the room at its edge leave it again sideways
				# behind the plane (through the room box's back-faced side wall) into the forest space: the forest
				# must draw there too. The closed room box is nearer and still occludes everything inside it.
				elif room_border and stone_room(terrain, i):
					# any non-solid tile of a stone room within 3 tiles of the hollow (small rooms set inside the
					# forest): far-zoom rays through the room leave it behind the plane into forest space
					for dy in range(-3, 4):
						for dx in range(-3, 4):
							var nx := x + dx
							var ny := y + dy
							if nx >= 0 and ny >= 0 and nx < W and ny < H and m[ny * W + nx]:
								b[i] = 90   # backstop only (forest_visible_deep): nothing may draw in front of the room
				elif room_border and not terrain.solid[i] and not terrain.sky[i]:   # open sky stays sky
					# other non-hollow air next to the hollow (pockets / code-2 slots world recesses): backstop too
					for d: int in [-1, 1, -W, W]:
						var j := i + d
						if j >= 0 and j < W * H and m[j]:
							b[i] = 90
							break
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < W and ny < H and m[ny * W + nx]:
						b[i] = 255
	return Image.create_from_data(W, H, false, Image.FORMAT_R8, b)

## Pine tiles that belong to a forest (the crown mass above a detected region).
static func is_forest_pine(terrain: WorldTerrain, x: int, y: int) -> bool:
	if terrain.level.fg[y * terrain.W + x] != PINE_ID:
		return false
	for r: Rect2i in regions(terrain):
		if Rect2i(r.position.x - 4, r.position.y - 24, r.size.x + 8, r.size.y + 24).has_point(Vector2i(x, y)):
			return true
	return false

## x ranges (tile x0, x1) of the detected forest regions (for far-landscape bands).
static func forest_x_ranges(terrain: WorldTerrain) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: Rect2i in regions(terrain):
		out.append(Vector2i(r.position.x, r.end.x))
	return out

# ---------------------------------------------------------------------------------------------- build

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	if WorldPalette.is_odyssey():
		return
	_rng.seed = 5151
	var hm := hollow_mask(terrain)
	region_list = regions(terrain)
	_hollow_tex = ImageTexture.create_from_image(hollow_image(terrain, true))
	var totals := {"trunks": 0, "ferns": 0, "cards": 0, "shafts": 0}
	for r: Rect2i in region_list:
		var reg := _build_region(lvl, terrain, hm, r)
		_regions.append(reg)
		for k: String in totals:
			totals[k] += int(reg.counts.get(k, 0))
	var nb := _build_pine(lvl, terrain)
	var rl: Array[String] = []
	for r: Rect2i in region_list:
		rl.append("(%d,%d)-(%d,%d)" % [r.position.x, r.position.y, r.end.x - 1, r.end.y - 1])
	var n_tiles := 0
	for i in hm.size():
		n_tiles += hm[i]
	stats = {"regions": region_list.size(), "region_bounds": rl, "hollow_tiles": n_tiles, "pine_boughs": nb}
	stats.merge(totals)
	set_focus_all(0.0)

## Every frame: fade each region's illusion by the focus (ball / camera pivot) distance to its hollow.
func update_focus(world_pos: Vector3, delta: float) -> void:
	var t := Vector2(world_pos.x, -world_pos.y)
	for reg: Dictionary in _regions:
		var r: Rect2i = reg.rect
		var dx := maxf(maxf(r.position.x - t.x, t.x - r.end.x), 0.0)
		var dy := maxf(maxf(r.position.y - t.y, t.y - r.end.y), 0.0)
		var target := 1.0 - smoothstep(FADE_IN, FADE_OUT, Vector2(dx, dy).length())
		var v: float = move_toward(float(reg.vis), target, delta * 1.5)
		_set_vis(reg, v)
	if _pine_mat:
		_pine_mat.set_shader_parameter("ball_pos", world_pos)

## Tests: jump every region's fade to a value (1 = fully in).
func set_focus_all(v: float) -> void:
	for reg: Dictionary in _regions:
		_set_vis(reg, v)

func _set_vis(reg: Dictionary, v: float) -> void:
	if absf(v - float(reg.vis)) < 0.0005 and v != 0.0 and v != 1.0:
		return
	reg.vis = v
	# out of range the forest stays a dim but real forest (never a black hole in the zoomed-out view); only the
	# moving extras (fireflies, pollen) switch off
	var shown := maxf(v, FAR_VIS)
	for m: ShaderMaterial in reg.mats:
		m.set_shader_parameter("vis", shown)
	for p: GPUParticles3D in reg.particles:
		p.emitting = v > 0.05
		p.visible = v > 0.01

func _mat(shader_path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	m.set_shader_parameter("hollow_tex", _hollow_tex)
	m.set_shader_parameter("hollow_size", Vector2(_hollow_tex.get_width(), _hollow_tex.get_height()))
	return m

func _build_region(lvl: EELevel, terrain: WorldTerrain, hm: PackedByteArray, r: Rect2i) -> Dictionary:
	var W := lvl.width
	var H := lvl.height
	var cols := terrain.fgcol_img
	var cm := WorldGrass.canopy_map(terrain)
	var node := Node3D.new()
	node.name = "Forest_%d_%d" % [r.position.x, r.position.y]
	add_child(node)
	var layers := Node3D.new()
	layers.name = "Layers"
	node.add_child(layers)
	var m_far := _mat("res://shaders/world/forest_haze.gdshader")
	m_far.set_shader_parameter("bg_space_tex", WorldBgSpace.texture(terrain))
	m_far.set_shader_parameter("bg_space_on", 1.0)
	var m_trunk := _mat("res://shaders/world/forest_trunk.gdshader")
	WorldPbr.bind(m_trunk, false, 1.0)
	var m_fern := _mat("res://shaders/world/grass_blade.gdshader")
	m_fern.set_shader_parameter("use_mask", 1.0)
	m_fern.set_shader_parameter("day", 0.5)
	var m_card := _mat("res://shaders/world/forest_card.gdshader")
	m_card.set_shader_parameter("leaf_albedo", load("res://assets/world/pbr/leaf_cluster_albedo.png"))
	var m_shaft := _mat("res://shaders/world/forest_shaft.gdshader")
	var m_fly := _mat("res://shaders/world/forest_mote.gdshader")
	var m_pollen := _mat("res://shaders/world/forest_mote.gdshader")
	m_pollen.set_shader_parameter("mote_col", Color(0.95, 0.95, 0.75))
	m_pollen.set_shader_parameter("blink", 0.0)
	m_pollen.set_shader_parameter("strength", 0.35)
	var trunks: Array = []      # [x, y_top, y_bot, z, radius, colour, haze]
	var painted: Array = []     # painted trunk columns [x, y0, y1, bg id]
	var ferns: Array = []       # [pos, scale, colour]
	var cards: Array = []       # [pos, size(Vector2), colour, cell, haze]
	var shafts: Array = []      # [pos, height, lean, width]
	var far_st := SurfaceTool.new()
	far_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_far := 0
	for x in range(r.position.x, r.end.x):
		var y := r.position.y
		while y < r.end.y:
			if not hm[y * W + x]:
				y += 1
				continue
			var y0 := y
			while y < r.end.y and hm[y * W + x]:
				y += 1
			var y1 := y - 1
			var ceil_w := -float(y0) + 1.0
			var floor_w := -float(y1 + 1)
			var crown_col := cols.get_pixel(x, maxi(y0 - 1, 0))
			var n511 := 0
			var n512 := 0
			var n510 := 0
			for yy in range(y0, y1 + 1):
				var b: int = lvl.bg[yy * W + x]
				n511 += 1 if b == 511 else 0
				n512 += 1 if b == 512 else 0
				n510 += 1 if b == 510 else 0
				n_far += _far_quad(far_st, lvl, terrain, hm, x, yy, y0, y1)
			# painted near bark trunks (512) and far trunks (511)
			if n512 >= 2:
				painted.append([x, y0, y1, 512])
			if n511 >= 2:
				painted.append([x, y0, y1, 511])
			# undergrowth: painted 510 = dense ferns near the plane; a receding fern floor behind
			for k in 2 + n510 * 2:
				var zf := _rng.randf_range(-2.8, -2.05) if k < n510 * 2 else -2.2 - pow(_rng.randf(), 1.6) * 8.0
				var c := Color(0.2, 0.36, 0.08).lerp(FOG_NEAR, clampf((-zf - 2.5) / 12.0, 0.0, 0.7))
				ferns.append([Vector3(x + _rng.randf(), floor_w, zf), _rng.randf_range(1.5, 2.4), c])
			# hanging leaves + vines from the canopy underside
			if false:
				var zc := _rng.randf_range(-6.0, -2.2)
				var hz := clampf((-zc - 2.0) / 7.0, 0.0, 0.7)
				var sz := _rng.randf_range(0.7, 1.2)
				cards.append([Vector3(x + _rng.randf(), ceil_w - 1.0 - sz * 0.35, zc), Vector2(sz, sz), crown_col.darkened(0.25), _rng.randi() % 4, hz])
			if _rng.randf() < 0.55 and y1 - y0 >= 2:
				var zv := _rng.randf_range(-5.0, -2.2)
				var ln := _rng.randf_range(1.2, minf(3.2, float(y1 - y0)))
				cards.append([Vector3(x + _rng.randf(), ceil_w - 1.0 - ln * 0.5, zv), Vector2(0.35, ln), crown_col.darkened(0.35), 4, clampf((-zv - 2.0) / 7.0, 0.0, 0.6)])
			# slanted sun shafts from canopy gaps (thin crowns / pores above) or every ~8 columns
			var gap := false
			for d in range(1, 5):
				var j := (y0 - d) * W + x
				if y0 - d >= 0 and (not terrain.solid[j] or terrain.pocket[j]):
					gap = true
					break
			if (gap and _rng.randf() < 0.35) or (x % 8 == 3 and y1 - y0 >= 3):
				shafts.append([Vector3(x + 0.5, (ceil_w + floor_w) * 0.5 + 0.5, float(-3 - _rng.randi() % 4)), ceil_w - floor_w + 2.0, 0.3, float(1 + _rng.randi() % 2)])
	# ---- the deep forest: region floor / canopy heights, a Poisson-disk trunk field to z -58, logs, deep
	# shafts, a receding floor and the opaque backstop (nothing behind a forest hollow can ever show sky)
	var floor_rows: Array[int] = []
	var ceil_rows: Array[int] = []
	for x in range(r.position.x, r.end.x):
		for y in range(maxi(r.position.y, 1), mini(r.end.y, H - 1)):
			var i := y * W + x
			if hm[i] and terrain.solid[i + W]:
				floor_rows.append(y + 1)
			if hm[i] and terrain.solid[i - W]:
				ceil_rows.append(y)
	floor_rows.sort()
	ceil_rows.sort()
	# the deep floor lies at the region's LOWEST forest floor: a median floor floated in mid-air above the lower
	# floors and read as a dark horizontal line across the whole backdrop when seen edge-on
	var floor_y := -float(floor_rows[floor_rows.size() - 1]) if not floor_rows.is_empty() else -float(r.end.y)
	var canopy_y := -float(ceil_rows[ceil_rows.size() / 2]) + 0.5 if not ceil_rows.is_empty() else -float(r.position.y)
	m_trunk.set_shader_parameter("canopy_y", canopy_y)
	_canopy_y_hint = canopy_y
	var m_deep := _mat("res://shaders/world/forest_deep.gdshader")
	m_deep.set_shader_parameter("floor_y", floor_y)
	m_deep.set_shader_parameter("canopy_y", canopy_y)
	var xa := float(r.position.x) - 26.0
	var xb := float(r.end.x) + 26.0
	var nblocks := _build_block_layers(lvl, terrain, hm, r, layers, painted, floor_y)
	for k in int((xb - xa) / 9.0):
		var z := -float(4 + _rng.randi() % 30)
		var d := -z - 1.2
		shafts.append([Vector3(floorf(_rng.randf_range(xa + 20.0, xb - 20.0)) + 0.5, floor_y + (canopy_y - floor_y) * 0.5 + d * 0.2, z), (canopy_y - floor_y) + 4.0 + d * 0.5, 0.3, float(1 + _rng.randi() % 3) * (1.0 + d / 25.0)])
	# receding floor (from the play strip back) + the opaque backstop at -62
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs := [-1.85, -10.0, -25.0, -45.0, -62.0]
	for k in zs.size() - 1:
		var z0: float = zs[k]
		var z1: float = zs[k + 1]
		var y0f := floor_y - (-z0 - 1.2) * 0.035 - 0.03
		var y1f := floor_y - (-z1 - 1.2) * 0.035 - 0.03
		for v: Vector3 in [Vector3(xa - 40.0, y0f, z0), Vector3(xb + 40.0, y0f, z0), Vector3(xb + 40.0, y1f, z1),
				Vector3(xa - 40.0, y0f, z0), Vector3(xb + 40.0, y1f, z1), Vector3(xa - 40.0, y1f, z1)]:
			st.set_color(Color(0, 0, 0, 1))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var by0 := floor_y - 60.0
	var by1 := canopy_y + 80.0
	for v: Vector3 in [Vector3(xa - 80.0, by0, -62.0), Vector3(xb + 80.0, by0, -62.0), Vector3(xb + 80.0, by1, -62.0),
			Vector3(xa - 80.0, by0, -62.0), Vector3(xb + 80.0, by1, -62.0), Vector3(xa - 80.0, by1, -62.0)]:
		st.set_color(Color(0, 0, 0, 0))
		st.set_normal(Vector3.BACK)
		st.add_vertex(v)
	var deep := MeshInstance3D.new()
	deep.name = "Deep"
	deep.mesh = st.commit()
	deep.material_override = m_deep
	deep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deep.extra_cull_margin = 200.0
	node.add_child(deep)
	# the per-column front floor strips
	if n_far > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Far"
		mi.mesh = far_st.commit()
		mi.material_override = m_far
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	_add_pocket_boughs(lvl, terrain, hm, r)
	_add_cards(layers, cards, m_card)
	_add_shafts(layers, shafts, m_shaft)
	var parts: Array[GPUParticles3D] = []
	var area := 0
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			area += hm[y * W + x]
	parts.append(_motes(layers, r, m_fly, clampi(area / 12, 4, 60), 0.09, 5.0, Color(1.0, 0.85, 0.4)))
	parts.append(_motes(layers, r, m_pollen, clampi(area / 5, 8, 150), 0.045, 9.0, Color(1, 1, 1)))
	return {"rect": r, "node": node, "layers": layers, "mats": [m_far, m_deep, m_trunk, m_fern, m_card, m_shaft, m_fly, m_pollen, _block_mats[_block_mats.size() - 1]],
		"particles": parts, "vis": -1.0,
		"counts": {"blocks": nblocks, "trunks": trunks.size(), "ferns": ferns.size(), "cards": cards.size(), "shafts": shafts.size()}}

## One far-card quad per hollow tile (grown toward non-hollow neighbours so no crack shows). Returns 1.
func _far_quad(st: SurfaceTool, lvl: EELevel, terrain: WorldTerrain, hm: PackedByteArray, x: int, y: int, y0: int, y1: int) -> int:
	var W := lvl.width
	var H := lvl.height
	var i := y * W + x
	var gl := 0.0 if x > 0 and hm[i - 1] else 0.7
	var gr := 0.0 if x < W - 1 and hm[i + 1] else 0.7
	var gu := 0.0 if hm[i - W] else 2.5
	var gd := 0.0 if y < H - 1 and hm[i + W] else 1.5
	var b: int = lvl.bg[i]
	var c := (WorldPalette.base_color(b) if b != 0 else DEEP).srgb_to_linear()
	var f := Vector2(y1 + 1, y0)
	# the lowest hollow tile of a span: a continuous forest floor from the play strip back to the far card
	# (mossy, darker with depth), so no sky / pale gap shows at the ground line between trunks
	# only over the real forest floor (ground below, not a crown / pine / trunk / pocket bottom): a strip
	# anywhere higher is a thin horizontal plane that reads as a dark line when seen edge-on at eye height
	var below := i + W
	var ground := y + 1 < H and terrain.solid[below] and not WorldGrass.canopy_map(terrain)[below] 		and lvl.fg[below] != PINE_ID and not is_trunk_tile(lvl, x, y + 1)
	if y == y1 and ground:
		var fy := -float(y1 + 1) - 0.02
		var fc := Color(0.08, 0.13, 0.05).srgb_to_linear()
		var fl := [Vector3(x - 0.6, fy, -1.85), Vector3(x + 1.6, fy, -1.85), Vector3(x + 1.6, fy - 0.3, -10.0),
			Vector3(x - 0.6, fy, -1.85), Vector3(x + 1.6, fy - 0.3, -10.0), Vector3(x - 0.6, fy - 0.3, -10.0)]
		for v: Vector3 in fl:
			st.set_color(fc)
			st.set_uv(Vector2(v.x, float(y1) + 0.9))   # tile-space: right at the floor -> the mist band
			st.set_uv2(f)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return 1

## The level's own forest, repeated as block layers going back into depth. The stamp = this region's painted
## forest blocks: crown tiles (canopy_map), the pine, trunk tiles, the painted 512 / 511 trunk columns and the
## two floor rows under the hollow. Layer 0 = the painted trunk columns themselves just behind the plane;
## deeper layers are the stamp shifted / mirrored and tiled across the widening view, stepping down with depth,
## hazier and darker. Cubes: 1 tile, 1 unit deep (floor blocks run on to the next layer: a continuous floor).
const BLOCK_LAYERS := [-3.5, -6.5, -10.0, -15.0, -22.0, -30.0, -40.0]

func _build_block_layers(lvl: EELevel, terrain: WorldTerrain, hm: PackedByteArray, r: Rect2i, parent: Node3D, painted: Array, floor_y: float) -> int:
	var W := lvl.width
	var H := lvl.height
	var cm := WorldGrass.canopy_map(terrain)
	var cols := terrain.fgcol_img
	# stamp rows: from 14 rows above the hollow's top down to 2 rows under its floor
	var y_top := maxi(r.position.y - 14, 0)
	var y_bot := mini(r.end.y + 2, H)
	var stamp: Array = []    # [dx, y, colour, mat, src]
	for y in range(y_top, y_bot):
		for x in range(r.position.x, r.end.x):
			var i := y * W + x
			var kind := -1
			if terrain.solid[i]:
				var fid: int = lvl.fg[i]
				if cm[i] or fid == PINE_ID:
					kind = WorldPalette.M_FOLIAGE
				elif is_trunk_tile(lvl, x, y):
					kind = WorldPalette.M_WOOD
				else:
					# floor: solid tiles right under hollow air (2 rows)
					for d in range(1, 3):
						if y - d >= 0 and hm[(y - d) * W + x] and not terrain.solid[(y - d) * W + x]:
							kind = int(terrain.mat_ids[i])
							break
					if kind == -1 and y > 0 and not terrain.solid[i - W] and hm[i - W]:
						kind = int(terrain.mat_ids[i])
			if kind == -1:
				continue
			var c: Color
			var m := kind
			if kind >= 100:
				c = BARK_512 if kind == 101 else BARK_511
				m = WorldPalette.M_WOOD
			else:
				c = cols.get_pixel(x, y)
			stamp.append([x - r.position.x, y, c, m, Vector2(x, y)])
	# every crown in the stamp gets a 2-block trunk from its underside to the floor (a whole tree per crown)
	var floor_row := int(-floor_y)
	var low := {}     # dx -> lowest crown row
	for e: Array in stamp:
		if int(e[3]) == WorldPalette.M_FOLIAGE:
			low[int(e[0])] = maxi(int(low.get(int(e[0]), -1)), int(e[1]))
	var dxs := low.keys()
	dxs.sort()
	var k0 := 0
	while k0 < dxs.size():
		var k1 := k0
		while k1 + 1 < dxs.size() and int(dxs[k1 + 1]) == int(dxs[k1]) + 1:
			k1 += 1
		var run := int(dxs[k1]) - int(dxs[k0]) + 1
		var n_tr := maxi(1, run / 9)
		for t in n_tr:
			var cx: int = int(dxs[k0]) + int((t + 0.5) * run / n_tr)
			var yb: int = int(low.get(cx, floor_row - 6))
			for dxw in 2:
				for y in range(yb + 1, floor_row):
					stamp.append([cx + dxw, y, BARK_512.darkened(0.15), WorldPalette.M_WOOD, Vector2(r.position.x + cx, y)])
		k0 = k1 + 1
	var sw := r.size.x
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var cu: Array[Color] = []
	_grid = {}
	# layer 0: the painted trunk columns as block trunks just behind the play plane
	for t: Array in painted:
		var z0 := -2.4 if int(t[3]) == 512 else -4.8
		var bc: Color = BARK_512 if int(t[3]) == 512 else BARK_511
		for y in range(int(t[1]) - 1, int(t[2]) + 1):
			_block(xs, cs, cu, Vector3(int(t[0]) + 0.5, -y - 0.5, z0), 1.0, bc, WorldPalette.M_WOOD, Vector2(int(t[0]), y), 0.05)
	for li in BLOCK_LAYERS.size():
		var z: float = BLOCK_LAYERS[li]
		var d := -z - 1.2
		var fog := clampf(0.12 + d / 40.0, 0.0, 0.95)
		var drop := floorf(d * 0.06)                       # the floor steps down with depth
		var ext := int(ceil(d * 0.9)) + 10                  # the view widens with depth: tile the stamp
		var shift := _rng.randi() % maxi(sw, 1)
		var next_z: float = BLOCK_LAYERS[li + 1] if li + 1 < BLOCK_LAYERS.size() else z - 8.0
		if li >= 3:
			_library_row(terrain, xs, cs, cu, r.position.x - ext, r.end.x + ext, float(int(-floor_y)) + drop, z, fog)
			continue
		var x := r.position.x - ext
		var copy := 0
		while x < r.end.x + ext:
			var mirror := (copy + li) % 2 == 1
			for e: Array in stamp:
				var dx: int = (int(e[0]) + shift) % sw
				if mirror:
					dx = sw - 1 - dx
				var wx := x + dx
				var wy := float(e[1]) + drop
				var is_floor: bool = int(e[3]) != WorldPalette.M_FOLIAGE and int(e[3]) != WorldPalette.M_WOOD
				var depth := (z - next_z) if is_floor else 1.0
				_block(xs, cs, cu, Vector3(wx + 0.5, -wy - 0.5, z - depth * 0.5 + 0.5), depth, e[2], int(e[3]), e[4], fog)
			x += sw
			copy += 1
	_fill_layers(int(floor_y))
	var occ := _merge_block_layers(xs, cs, cu)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = cube
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_color(k, cs[k])
		mm.set_instance_custom_data(k, cu[k])
	var m := _mat("res://shaders/world/forest_block.gdshader")
	WorldPbr.bind(m, false, 1.0, terrain)
	m.set_shader_parameter("floor_y", floor_y)
	m.set_shader_parameter("canopy_y", _canopy_y_hint)
	m.set_shader_parameter("occ_tex", ImageTexture.create_from_image(occ[0]))
	m.set_shader_parameter("occ_origin", occ[1])
	m.set_shader_parameter("leaf_tex", load("res://assets/world/pbr/leaf_cluster_albedo.png"))
	_block_mats.append(m)
	var mi := MultiMeshInstance3D.new()
	mi.name = "BlockTrees"
	print("WorldForest: %d block cells merged into %d slabs, %d duplicate cells skipped" % [_grid.size(), xs.size(), dup_blocks])
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return xs.size()

## The level's crown library: every tree-crown component of canopy_map (all of FV's crowns), each as its tile
## list [dx, dy, colour] relative to its bottom-left, plus its width / height. Cached on the terrain.
static func crown_library(terrain: WorldTerrain) -> Array:
	if terrain.has_meta(&"crown_library"):
		return terrain.get_meta(&"crown_library")
	var W := terrain.W
	var H := terrain.H
	var cm := WorldGrass.canopy_map(terrain)
	var cols := terrain.fgcol_img
	var seen := PackedByteArray()
	seen.resize(W * H)
	var lib: Array = []
	for i0 in W * H:
		if not cm[i0] or seen[i0]:
			continue
		var comp := PackedInt32Array([i0])
		seen[i0] = 1
		var q := 0
		var x0 := W
		var x1 := 0
		var y0 := H
		var y1 := 0
		while q < comp.size():
			var i := comp[q]
			q += 1
			var x := i % W
			var y := i / W
			x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y)
			for d: int in [1, -1, W, -W]:
				var j := i + d
				if j >= 0 and j < W * H and cm[j] and not seen[j] and absi((j % W) - x) <= 1:
					seen[j] = 1
					comp.append(j)
		var w := x1 - x0 + 1
		var h := y1 - y0 + 1
		if w < 4 or h < 3 or w > 26:
			continue
		var tiles: Array = []
		for i in comp:
			tiles.append([i % W - x0, y1 - i / W, cols.get_pixel(i % W, i / W)])
		lib.append({"w": w, "h": h, "tiles": tiles})
	terrain.set_meta(&"crown_library", lib)
	return lib

## One receding row of library trees: random crowns (sometimes mirrored) on 2-block trunks, standing on a
## continuous block floor at row `floor_row`, spread across [xa, xb] at depth z.
func _library_row(terrain: WorldTerrain, xs: Array[Transform3D], cs: Array[Color], cu: Array[Color], xa: int, xb: int, floor_row: float, z: float, fog: float) -> void:
	var lib := crown_library(terrain)
	if lib.is_empty():
		return
	var lawn := Color(0.27, 0.39, 0.07)
	var earth := Color(0.45, 0.32, 0.2)
	for x in range(xa, xb):
		_block(xs, cs, cu, Vector3(x + 0.5, -floor_row - 0.5, z - 3.5), 8.0, lawn, WorldPalette.M_GRASS, Vector2(x, floor_row), fog)
		_block(xs, cs, cu, Vector3(x + 0.5, -floor_row - 1.5, z - 3.5), 8.0, earth, WorldPalette.M_EARTH, Vector2(x, floor_row + 1), fog)
	var x := xa + _rng.randi() % 4
	while x < xb:
		var c: Dictionary = lib[_rng.randi() % lib.size()]
		var w: int = c.w
		var mirror := _rng.randf() < 0.5
		var trunk_h := 3 + _rng.randi() % 5
		var zz := z - float(_rng.randi() % 3)
		var tx := x + w / 2
		for dxw in 2:
			for k in trunk_h:
				_block(xs, cs, cu, Vector3(tx + dxw + 0.5 - 1.0, -(floor_row - 1 - k) - 0.5, zz), 1.0, BARK_512.darkened(0.15), WorldPalette.M_WOOD, Vector2(tx, floor_row - 1 - k), fog)
		var base_row := floor_row - trunk_h
		for t: Array in c.tiles:
			var dx: int = int(t[0])
			if mirror:
				dx = w - 1 - dx
			var wy := base_row - 1 - int(t[1])
			_block(xs, cs, cu, Vector3(x + dx + 0.5, -wy - 0.5, zz), 1.0, t[2], WorldPalette.M_FOLIAGE, Vector2(x + dx, wy), fog)
		x += w + 1 + _rng.randi() % 4

## Cells already holding a cube (x, y, z quantised): two cubes in one cell have coplanar faces in different
## colours, which z-fight as the camera moves (the flickering texture / sawtooth edges). First cube wins.
var _cells := {}
var dup_blocks := 0

## The block trees collapse onto three depth layers (near / mid / far front-face z): each tile-stepped crown
## or trunk then lies in ONE plane and greedy-merges into a few big slabs, instead of a cloud of 1-tile cubes
## at scattered depths that each catch their own fog / light and read as squares.
const LAYER_FRONT: Array[float] = [-1.9, -9.5, -21.5]
const LAYER_FOG: Array[float] = [0.1, 0.3, 0.62]

## (x, world y, layer) -> [mat, depth, colour]: the cells of the layer being built.
var _grid := {}

static func _layer_of(front: float) -> int:
	if front > -5.0:
		return 0
	if front > -17.0:
		return 1
	return 2

func _block(_xs: Array[Transform3D], _cs: Array[Color], _cu: Array[Color], c: Vector3, depth: float, col: Color, mat: int, _src: Vector2, _fog: float) -> void:
	var li := _layer_of(c.z + depth * 0.5)
	var key := Vector3i(int(floor(c.x)), int(floor(c.y)), li)
	var ckey := Vector3i(key.x, key.y, int(round(LAYER_FRONT[li] * 4.0)))
	if _cells.has(ckey):
		dup_blocks += 1
		return
	_cells[ckey] = true
	_grid[key] = [mat, depth, col.srgb_to_linear()]

## Turns the mid / far layers from a mosaic into masses: closes the small holes inside foliage (air with the
## same crown within 3 tiles on all four sides -> crown), then stands 2-wide trunk columns every 3-6 tiles in
## the far layer's remaining gaps (floor to the top of the stamp), so the flat backstop never shows as squares.
func _fill_layers(floor_key: int) -> void:
	if _grid.is_empty():
		return
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for key: Vector3i in _grid:
		lo = Vector2i(mini(lo.x, key.x), mini(lo.y, key.y))
		hi = Vector2i(maxi(hi.x, key.x), maxi(hi.y, key.y))
	var dirs: Array[Vector3i] = [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
	for li in [1, 2]:
		for _pass in 2:
			var add := {}
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var k := Vector3i(x, y, li)
					if _grid.has(k):
						continue
					var found: Array = []
					for d: Vector3i in dirs:
						for step in range(1, 4):
							var e: Variant = _grid.get(k + d * step)
							if e != null:
								if int((e as Array)[0]) == WorldPalette.M_FOLIAGE:
									found = e
								else:
									found = []
								break
						if found.is_empty():
							break
					if not found.is_empty():
						add[k] = [WorldPalette.M_FOLIAGE, 1.0, found[2]]
			for k: Vector3i in add:
				_grid[k] = add[k]
	var bark := BARK_512.darkened(0.3).srgb_to_linear()
	var x := lo.x + _rng.randi() % 3
	while x <= hi.x:
		for dxw in 2:
			for y in range(floor_key - 2, hi.y + 1):
				var k := Vector3i(x + dxw, y, 2)
				if not _grid.has(k):
					_grid[k] = [WorldPalette.M_WOOD, 1.0, bark]
		x += 5 + _rng.randi() % 4

## Greedy-merges each layer's same-material, same-depth cells into boxes (row runs, then stacked while the run
## below matches), one colour per (layer, material) so merged faces never step in tone. Returns
## [occupancy image (R/G/B = material class of the near / mid / far layer per tile), its world origin]
## for the shader's mass-silhouette edges.
func _merge_block_layers(xs: Array[Transform3D], cs: Array[Color], cu: Array[Color]) -> Array:
	var sum := {}
	var cnt := {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for key: Vector3i in _grid:
		var e: Array = _grid[key]
		var sk := Vector2i(key.z, int(e[0]))
		sum[sk] = (sum.get(sk, Color(0, 0, 0)) as Color) + (e[2] as Color)
		cnt[sk] = int(cnt.get(sk, 0)) + 1
		lo = Vector2i(mini(lo.x, key.x), mini(lo.y, key.y))
		hi = Vector2i(maxi(hi.x, key.x), maxi(hi.y, key.y))
	if _grid.is_empty():
		return [Image.create(1, 1, false, Image.FORMAT_RGBA8), Vector2.ZERO]
	var org := lo - Vector2i(1, 1)
	var img := Image.create(hi.x - lo.x + 3, hi.y - lo.y + 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for key: Vector3i in _grid:
		var px := img.get_pixel(key.x - org.x, key.y - org.y)
		px[key.z] = float(_mat_class(int((_grid[key] as Array)[0]))) / 4.0
		img.set_pixel(key.x - org.x, key.y - org.y, px)
	var done := {}
	var keys := _grid.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y > b.y if a.y != b.y else a.x < b.x)
	for key: Vector3i in keys:
		if done.has(key):
			continue
		var e: Array = _grid[key]
		var mat := int(e[0])
		var depth: float = e[1]
		var w := 1
		while _merge_ok(key + Vector3i(w, 0, 0), mat, depth, done):
			w += 1
		var h := 1
		while true:
			var ok := true
			for dx in w:
				if not _merge_ok(key + Vector3i(dx, -h, 0), mat, depth, done):
					ok = false
					break
			if not ok:
				break
			h += 1
		for dy in h:
			for dx in w:
				done[key + Vector3i(dx, -dy, 0)] = true
		var sk := Vector2i(key.z, mat)
		var front: float = LAYER_FRONT[key.z]
		var c := Vector3(key.x + w * 0.5, key.y + 1.0 - h * 0.5, front - depth * 0.5)
		xs.append(Transform3D(Basis().scaled(Vector3(w, h, depth)), c))
		cs.append((sum[sk] as Color) / float(cnt[sk]))
		cu.append(Color(float(mat), LAYER_FOG[key.z], float(key.z), depth))
	return [img, Vector2(org)]

func _merge_ok(k: Vector3i, mat: int, depth: float, done: Dictionary) -> bool:
	if done.has(k) or not _grid.has(k):
		return false
	var e: Array = _grid[k]
	return int(e[0]) == mat and is_equal_approx(float(e[1]), depth)

## Material classes that merge into one mass (leafy / wood / ground).
static func _mat_class(mat: int) -> int:
	if mat == WorldPalette.M_FOLIAGE or mat == WorldPalette.M_GRASS:
		return 1
	if mat == WorldPalette.M_WOOD:
		return 2
	return 3

## Poisson-disk points over x in [xa, xb], z in [z0 (front), z1 (back)]; spacing grows with depth.
func _poisson(xa: float, xb: float, z0: float, z1: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cell := POISSON_R
	var grid := {}
	var tries := int((xb - xa) * (z0 - z1) / (POISSON_R * POISSON_R) * 2.5)
	for k in tries:
		var p := Vector2(_rng.randf_range(xa, xb), lerpf(z0, z1, pow(_rng.randf(), 0.8)))
		var rmin := POISSON_R * (1.0 + (-p.y - 2.0) * 0.045)
		var gi := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
		var ok := true
		var reach := int(ceil(rmin / cell)) + 1
		for gx in range(gi.x - reach, gi.x + reach + 1):
			for gz in range(gi.y - reach, gi.y + reach + 1):
				var key := Vector2i(gx, gz)
				if grid.has(key):
					for q: Vector2 in grid[key]:
						if q.distance_to(p) < rmin:
							ok = false
							break
				if not ok:
					break
			if not ok:
				break
		if ok:
			out.append(p)
			if not grid.has(gi):
				grid[gi] = []
			grid[gi].append(p)
	return out

## Fallen logs: the trunk mesh lying along x on the floor.
func _add_logs(parent: Node3D, logs: Array, mat: ShaderMaterial) -> void:
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for l: Array in logs:
		var rr: float = l[1]
		var ln: float = l[2]
		var b := Basis(Vector3.BACK, PI * 0.5 + _rng.randf_range(-0.08, 0.08)) * Basis(Vector3.UP, _rng.randf() * TAU)
		b = Basis(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * b
		xs.append(Transform3D(b.scaled(Vector3(rr, ln, rr)), (l[0] as Vector3) + Vector3(ln * 0.5, 0, 0)))
		var c := BARK_512.darkened(0.3).srgb_to_linear()
		cs.append(Color(c.r, c.g, c.b, 0.0))
	_mm_node(parent, "Logs", _trunk_mesh(5, false), mat, xs, cs)

## The pine's walkable air pockets: dark bough interiors (needle clumps drooping inside, behind the plane).
func _add_pocket_boughs(lvl: EELevel, terrain: WorldTerrain, hm: PackedByteArray, r: Rect2i) -> void:
	var W := lvl.width
	var helper := WorldGrass.new()
	var bough := helper._clump_mesh(22, 0.34, 0.55, 0.018, 0.03, 0.06, 4, 78)
	helper.free()
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for y in range(maxi(r.position.y, 1), r.end.y):
		for x in range(maxi(r.position.x, 1), mini(r.end.x, W - 1)):
			var i := y * W + x
			if not hm[i] or not terrain.pocket[i]:
				continue
			var pine := 0
			for j: int in [i - 1, i + 1, i - W, i + W]:
				pine += 1 if lvl.fg[j] == PINE_ID else 0
			if pine < 2:
				continue
			for k in 7:
				var up := Vector3(_rng.randf_range(-0.8, 0.8), -0.6, _rng.randf_range(0.1, 0.4)).normalized()
				var p := Vector3(x + _rng.randf_range(0.0, 1.0), -(y + _rng.randf_range(-0.1, 0.4)), _rng.randf_range(-2.8, -1.95))
				xs.append(_bough_xform(p, up, _rng.randf_range(0.9, 1.4)))
				var c := Color(0.05, 0.16, 0.12).lerp(Color(0.1, 0.3, 0.2), _rng.randf() * 0.5).srgb_to_linear()
				cs.append(Color(c.r, c.g, c.b, _rng.randf() * 0.99))
	if xs.is_empty():
		return
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/world/grass_blade.gdshader")
	m.set_shader_parameter("day", 0.3)
	_mm_node(self, "PocketBoughs", bough, m, xs, cs)

func _mm_node(parent: Node3D, nm: String, mesh: Mesh, mat: Material, xs: Array[Transform3D], cs: Array[Color]) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_custom_data(k, cs[k])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _add_trunks(parent: Node3D, trunks: Array, mat: ShaderMaterial) -> void:
	var meshes := [_trunk_mesh(11, false), _trunk_mesh(23, true)]   # plain / forked
	var sets := [[[], []], [[], []]]
	for t: Array in trunks:
		var h: float = t[1] - t[2]
		var rr: float = t[4]
		var hz: float = t[6]
		var lean := _rng.randf_range(-0.05, 0.05) + (_rng.randf_range(-0.07, 0.07) if hz > 0.2 else 0.0)
		var b := Basis(Vector3.FORWARD, lean) * Basis(Vector3.UP, _rng.randf() * TAU)
		b = b.scaled(Vector3(rr, h, rr))
		var fork := 1 if (hz > 0.1 and _rng.randf() < 0.25) else 0
		sets[fork][0].append(Transform3D(b, Vector3(t[0], t[2], t[3])))   # mesh origin = the base
		var c: Color = (t[5] as Color).srgb_to_linear()
		sets[fork][1].append(Color(c.r, c.g, c.b, hz))
	for k in 2:
		var xs: Array[Transform3D] = []
		xs.assign(sets[k][0])
		var cs: Array[Color] = []
		cs.assign(sets[k][1])
		_mm_node(parent, "Trunks%d" % k, meshes[k], mat, xs, cs)

## Unit trunk (base at y 0, top at y 1, radius ~1): 14-sided, tapering to 0.72 at the top, a root flare with
## 5 buttress lobes over the bottom 10%, gentle bulges; forked = a second limb splitting off at 70%.
func _trunk_mesh(seed_v: int, forked: bool) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var SEG := 14
	var RINGS := 14
	var lobe_ph := r.randf() * TAU
	var rings: Array = []
	for j in RINGS + 1:
		var t := float(j) / RINGS
		t = t * t * 0.35 + t * 0.65             # more rings near the base (flare)
		var ring: Array = []
		for k in SEG:
			var a := float(k) / SEG * TAU
			var rad := lerpf(1.0, 0.72, t) * (1.0 + 0.05 * sin(t * 9.0 + a * 2.0))
			var flare := exp(-t * 24.0)
			rad += flare * (0.55 + 0.45 * maxf(sin(a * 5.0 + lobe_ph), 0.0))
			ring.append(Vector3(cos(a) * rad, t, sin(a) * rad))
		rings.append(ring)
	for j in RINGS:
		for k in SEG:
			var k2 := (k + 1) % SEG
			var p00: Vector3 = rings[j][k]
			var p01: Vector3 = rings[j][k2]
			var p10: Vector3 = rings[j + 1][k]
			var p11: Vector3 = rings[j + 1][k2]
			for tri: Array in [[p00, p10, p11], [p00, p11, p01]]:
				for v: Vector3 in tri:
					st.set_normal(Vector3(v.x, 0.0, v.z).normalized())
					st.set_uv(Vector2(0.0, v.y))
					st.add_vertex(v)
	if forked:
		# a limb from 0.62 up and outward (thinner), capped by the canopy above
		var dir := Vector3(0.35, 1.0, 0.0).normalized()
		var base := Vector3(0.2, 0.62, 0.0)
		var side := Vector3(0.0, 0.0, 1.0)
		var right := dir.cross(side).normalized()
		for j in 6:
			var t0 := float(j) / 6.0
			var t1 := float(j + 1) / 6.0
			for k in 8:
				var a0 := float(k) / 8.0 * TAU
				var a1 := float(k + 1) / 8.0 * TAU
				var rr0 := lerpf(0.5, 0.35, t0)
				var rr1 := lerpf(0.5, 0.35, t1)
				var c0 := base + dir * t0 * 0.5
				var c1 := base + dir * t1 * 0.5
				var n0 := right * cos(a0) + side * sin(a0)
				var n1 := right * cos(a1) + side * sin(a1)
				var q00 := c0 + n0 * rr0
				var q01 := c0 + n1 * rr0
				var q10 := c1 + n0 * rr1
				var q11 := c1 + n1 * rr1
				for tri: Array in [[q00, q10, q11, n0, n0, n1], [q00, q11, q01, n0, n1, n1]]:
					for v in 3:
						st.set_normal(tri[3 + v])
						st.set_uv(Vector2(0.0, (tri[v] as Vector3).y))
						st.add_vertex(tri[v])
	return st.commit()

func _add_ferns(parent: Node3D, ferns: Array, mat: ShaderMaterial) -> void:
	var helper := WorldGrass.new()
	var fern := helper._fern_mesh()
	helper.free()
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for f: Array in ferns:
		var s: float = f[1]
		xs.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(-1.2, 1.2)).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s)), f[0]))
		var c: Color = (f[2] as Color).srgb_to_linear()
		cs.append(Color(c.r, c.g, c.b, _rng.randf() * 0.99))
	_mm_node(parent, "Ferns", fern, mat, xs, cs)

func _add_cards(parent: Node3D, cards: Array, mat: ShaderMaterial) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for c: Array in cards:
		var sz: Vector2 = c[1]
		var roll := _rng.randf() * TAU if int(c[3]) < 4 else 0.0
		xs.append(Transform3D(Basis(Vector3.BACK, roll).scaled(Vector3(sz.x, sz.y, 1.0)), c[0]))
		var lc: Color = (c[2] as Color).srgb_to_linear()
		cs.append(Color(lc.r, lc.g, lc.b, float(c[3]) + clampf(c[4], 0.0, 0.95)))
	_mm_node(parent, "Hanging", quad, mat, xs, cs)

func _add_shafts(parent: Node3D, shafts: Array, mat: ShaderMaterial) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for s: Array in shafts:
		xs.append(Transform3D(Basis(Vector3.BACK, s[2]).scaled(Vector3(s[3], s[1], 1.0)), s[0]))
		cs.append(Color(_rng.randf(), 0, 0, 0))
	_mm_node(parent, "Shafts", quad, mat, xs, cs)

## Fireflies / pollen: slow drifting motes in the region's hollow volume (z -2.2 .. -7).
func _motes(parent: Node3D, r: Rect2i, mat: ShaderMaterial, amount: int, size: float, life: float, col: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.position = Vector3(r.position.x + r.size.x * 0.5, -(r.position.y + r.size.y * 0.5), -4.6)
	p.visibility_aabb = AABB(Vector3(-r.size.x * 0.5 - 2, -r.size.y * 0.5 - 2, -4), Vector3(r.size.x + 4, r.size.y + 4, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(r.size.x * 0.5, r.size.y * 0.5, 2.4)
	pm.gravity = Vector3(0, 0.02, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.direction = Vector3(0.3, 0.2, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	pm.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p

# ---------------------------------------------------------------------------------------------- the pine

## Conifer: needle boughs on every forest pine tile (fg 17). Edge tiles sweep outward and down, every second
## row carries a longer tier; boughs lie in the view plane. SNAP onto the sculpted surface (grass shader), so
## they only cover the pine's own tiles (overhang <= ~0.15).
func _build_pine(lvl: EELevel, terrain: WorldTerrain) -> int:
	var W := lvl.width
	var H := lvl.height
	var cols := terrain.fgcol_img
	_pine_mat = ShaderMaterial.new()
	_pine_mat.shader = load("res://shaders/world/grass_blade.gdshader")
	_pine_mat.set_shader_parameter("day", 0.6)
	WorldGrass.bind_height(_pine_mat, terrain)
	var helper := WorldGrass.new()
	var bough := helper._clump_mesh(22, 0.34, 0.55, 0.018, 0.03, 0.06, 4, 77)
	helper.free()
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if lvl.fg[i] != PINE_ID or not is_forest_pine(terrain, x, y):
				continue
			var base := cols.get_pixel(x, y)
			var open_l: bool = lvl.fg[i - 1] != PINE_ID and not terrain.solid[i - 1]
			var open_r: bool = lvl.fg[i + 1] != PINE_ID and not terrain.solid[i + 1]
			var open_d: bool = lvl.fg[i + W] != PINE_ID
			var tier := y % 2 == 0
			for side: int in [-1, 1]:
				if (side < 0 and open_l) or (side > 0 and open_r):
					for k in 3:
						var up := Vector3(side * 0.85, -0.5, 0.15).normalized()
						var p := Vector3(x + (0.45 if side < 0 else 0.55), -(y + _rng.randf_range(0.05, 0.5)), 0.03)
						xs.append(_bough_xform(p, up, _rng.randf_range(0.95, 1.15) * (1.1 if tier else 0.9)))
						cs.append(base.darkened(_rng.randf_range(0.0, 0.2)))
			for k in (8 if tier else 5):
				var up := Vector3(_rng.randf_range(-0.8, 0.8), -0.75 if tier else -0.45, 0.22).normalized()
				var p := Vector3(x + _rng.randf_range(0.1, 0.9), -(y + _rng.randf_range(0.05, 0.4)), 0.03)
				xs.append(_bough_xform(p, up, _rng.randf_range(1.1, 1.6) if tier else _rng.randf_range(0.8, 1.1)))
				var c := base.lightened(0.22) if tier else base.darkened(0.2)
				cs.append(c.lerp(Color(0.04, 0.14, 0.1), _rng.randf_range(0.0, 0.25)))
			if open_d and tier:
				for k in 3:
					var up := Vector3(_rng.randf_range(-0.3, 0.3), -0.95, 0.15).normalized()
					xs.append(_bough_xform(Vector3(x + _rng.randf_range(0.15, 0.85), -(y + 0.55), 0.03), up, _rng.randf_range(0.6, 0.75)))
					cs.append(base.darkened(0.15))
	var cust: Array[Color] = []
	for c: Color in cs:
		var lc := c.srgb_to_linear()
		cust.append(Color(lc.r, lc.g, lc.b, _rng.randf() * 0.99 + 10.0))   # +10 = SNAP
	_mm_node(self, "PineBoughs", bough, _pine_mat, xs, cust)
	return xs.size()

func _bough_xform(p: Vector3, up: Vector3, s: float) -> Transform3D:
	var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, _rng.randf() * TAU)
	return Transform3D(b.scaled(Vector3.ONE * s), p)
