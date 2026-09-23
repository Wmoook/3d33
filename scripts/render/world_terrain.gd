class_name WorldTerrain
extends Node3D
## Sculpted terrain: one continuous GPU-displaced height field (foreground mass, recessed background wall,
## deep cave back wall) driven by baked sub-tile SDFs. Chunked (32x32 tiles) for culling; every chunk
## shares one grid mesh and one ShaderMaterial.

const CHUNK := 16
const VPT := 8          # vertices per tile (= the SDF bake density; solidity check stays at 0)
const MARGIN := 16      # extra tiles of terrain around the level

var level: EELevel
var W := 0
var H := 0
var material: ShaderMaterial
var shadow_material: ShaderMaterial
var fgcol_img: Image
var orig_img: Image
var info_img: Image
var bgcol_img: Image
var sdf_img: Image
## Per-tile material class (PackedByteArray W*H), zone ids and sky mask, shared with other world modules.
var mat_ids := PackedByteArray()
var zones := PackedByteArray()
var sky := PackedByteArray()
var solid := PackedByteArray()
## Air tiles with a recessed back wall behind them (bg blocks, minimap-coloured air such as the key dither).
var backwall := PackedByteArray()
## Tiny isolated solid islands (<= 3 tiles: sparks, debris, drips) are removed from the height field
## and rendered as floating 3D props by WorldDecor (their collision is unchanged). Index -> tile colour.
var floaters := {}
## Tiny enclosed air pockets (the key "dither" holes in the rock): drawn as shallow pits, not deep holes.
var pocket := PackedByteArray()
## Tiny solid islands (<= 3 tiles, 8-connected): sculpted as organic pebbles / crystals / embers.
var speck := PackedByteArray()
var timings := {}
## Per-level reference art directory (minimap_ee.png, minimap_colors.json) and time of day.
var ref_dir := "res://assets/ee_ref"
var day := false
## Backdrop instance (sky's distant block-built islands): no margin ring, no shadow meshes, low VPT, placed
## by set_placement(), hazed by set_haze(). Build with WorldTerrain.build_backdrop().
var backdrop := false
var backdrop_vpt := 3
var minimap_override: Image
## Day levels: air tiles whose back wall is decided after the sky flood (sky-painted bg, minimap-coloured air).
var _deferred := PackedByteArray()
var _deferred_col := PackedColorArray()

func build(lvl: EELevel) -> void:
	level = lvl
	W = lvl.width
	H = lvl.height
	var t0 := Time.get_ticks_msec()
	_classify()
	timings["classify"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var mask := PackedByteArray()
	mask.resize(W * H)
	for i in W * H:
		var m := 0
		if solid[i]:
			m = 3
		elif backwall[i] or pocket[i]:
			m = 2
		mask[i] = m
	sdf_img = WorldSdfBaker.bake(mask, W, H)
	timings["sdf_bake"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_material()
	_bake_height()
	timings["material"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_chunks()
	timings["chunks"] = Time.get_ticks_msec() - t0

func _is_border(x: int, y: int) -> bool:
	return x == 0 or y == 0 or x == W - 1 or y == H - 1

## Air components (4-connected over non-solid tiles) of <= 8 tiles, not touching the sky and holding
## no spawn/portal: unreachable in play, so they only exist as texture in the painting.
func _find_pockets() -> void:
	var n := W * H
	pocket.resize(n)
	pocket.fill(0)
	var seen := PackedByteArray()
	seen.resize(n)
	var comp := PackedInt32Array()
	for start in n:
		if seen[start] or solid[start]:
			continue
		comp.clear()
		comp.append(start)
		seen[start] = 1
		var qi := 0
		var ok := true
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var id: int = level.fg[i]
			if sky[i] or id == 255 or id == 242 or id == 381:
				ok = false
			var x := i % W
			var y := i / W
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if seen[j] or solid[j]:
					continue
				seen[j] = 1
				comp.append(j)
		if ok and comp.size() <= 8:
			for i in comp:
				pocket[i] = 1
	# thin burrows: enclosed air (not sky) with >= 5 solid 8-neighbours also reads as pores in the rock
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if solid[i] or sky[i] or pocket[i]:
				continue
			var c := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and solid[i + dy * W + dx]:
						c += 1
			if c >= 5:
				pocket[i] = 2
	var cnt := 0
	for i in n:
		cnt += 1 if pocket[i] else 0
	timings["pocket_tiles"] = cnt

func _find_floaters(fgb: PackedByteArray, has_fg: PackedByteArray) -> void:
	var seen := PackedByteArray()
	seen.resize(W * H)
	var comp := PackedInt32Array()
	for start in W * H:
		if seen[start] or not solid[start]:
			continue
		comp.clear()
		comp.append(start)
		seen[start] = 1
		var qi := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					if seen[j] or not solid[j]:
						continue
					seen[j] = 1
					comp.append(j)
		if comp.size() <= 3:
			for i in comp:
				if _is_border(i % W, i / W):
					continue
				floaters[i] = [Color8(fgb[i * 4], fgb[i * 4 + 1], fgb[i * 4 + 2]), int(mat_ids[i]), comp.size()]
				solid[i] = 0
				has_fg[i] = 0
				fgb[i * 4 + 3] = 0
	# a floater that hung in the open sky leaves sky behind it
	for i in floaters:
		var x: int = i % W
		var y: int = i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx >= 0 and ny >= 0 and nx < W and ny < H and sky[ny * W + nx]:
				sky[i] = 1
				break

var _mm_ids := {}
## Non-solid fg ids that paint the minimap (keys 6/7/8, crowns 5, portals...): their tiles get a back wall.
func _fg_has_minimap_colour(id: int) -> bool:
	if id <= 0:
		return false
	if _mm_ids.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(ref_dir + "/minimap_colors.json"))
		if j is Dictionary:
			for k in j:
				if j[k] != null:
					_mm_ids[int(k)] = true
		_mm_ids[-1] = true
	return _mm_ids.has(id)

func _load_minimap() -> Image:
	if minimap_override:
		var o := minimap_override.duplicate() as Image
		o.convert(Image.FORMAT_RGB8)
		return o
	if backdrop:
		return null
	var buf := FileAccess.get_file_as_bytes(ref_dir + "/minimap_ee.png")
	if buf.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(buf) != OK:
		return null
	img.convert(Image.FORMAT_RGB8)
	return img

## Sky visibility = flood fill from the top open row (y = 1, below the solid 44 border) through air that
## is not solid, not a key door/gate and has no back wall (bg block / minimap-coloured air), staying in
## the surface band (y <= SKY_MAX_Y) so tunnel mouths don't leak the sky underground.
const SKY_MAX_Y := 22

func _compute_sky() -> void:
	var q := PackedInt32Array()
	for x in W:
		var i0 := W + x
		if _sky_passable(i0):
			sky[i0] = 1
			q.append(i0)
	var qi := 0
	while qi < q.size():
		var i := q[qi]; qi += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 1 or nx >= W or ny > (H - 1 if day else SKY_MAX_Y):
				continue
			var j := ny * W + nx
			if sky[j] or not _sky_passable(j):
				continue
			sky[j] = 1
			q.append(j)

func _sky_passable(i: int) -> bool:
	return not solid[i] and not backwall[i] and not WorldPalette.is_key_door(level.fg[i])

func _find_specks() -> void:
	var n := W * H
	speck.resize(n)
	speck.fill(0)
	var seen := PackedByteArray()
	seen.resize(n)
	for start in n:
		if seen[start] or not solid[start]:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		while qi < comp.size() and comp.size() <= 4:
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					if seen[j] or not solid[j]:
						continue
					seen[j] = 1
					comp.append(j)
		if comp.size() <= 3:
			for i in comp:
				speck[i] = 1

## Day levels: the painting's sky (minimap colours of every sky tile) extended behind the terrain by
## nearest-colour fill and softened, for the far sky backdrop.
func sky_paint_image() -> Image:
	var mm := _load_minimap()
	if mm == null or mm.get_width() != W:
		return null
	var src := mm.get_data()
	var buf := PackedByteArray()
	buf.resize(W * H * 4)
	var filled := PackedByteArray()
	filled.resize(W * H)
	for i in W * H:
		# the black world border and minimap-coloured gameplay tiles in the sky (portal paths...) are not sky art
		if sky[i] and not _is_border(i % W, i / W) and not _fg_has_minimap_colour(level.fg[i]):
			buf[i * 4] = src[i * 3]; buf[i * 4 + 1] = src[i * 3 + 1]; buf[i * 4 + 2] = src[i * 3 + 2]; buf[i * 4 + 3] = 255
			filled[i] = 1
	_dilate(buf, filled)
	# border tiles never seeded: give them their inner neighbour's sky colour
	for x in W:
		for k in 4:
			buf[x * 4 + k] = buf[(W + x) * 4 + k]
			buf[((H - 1) * W + x) * 4 + k] = buf[((H - 2) * W + x) * 4 + k]
	for y in H:
		for k in 4:
			buf[(y * W) * 4 + k] = buf[(y * W + 1) * 4 + k]
			buf[(y * W + W - 1) * 4 + k] = buf[(y * W + W - 2) * 4 + k]
	# alpha = 1 where the painting really is sky (not fill behind the terrain)
	for i in W * H:
		buf[i * 4 + 3] = 255 if filled[i] else 0
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, buf)

## Day levels: the level's own masses as seen by the sky backdrop (so every silhouette continues into
## depth). R = grounded solid mass (floating art - scroll, logo, V-birds, specks - excluded), G = "fall-away"
## below every mass (1 right under it, fading over FALL tiles), so masses sit on rock falling into mist.
const FALL := 28.0

func sky_depth_image() -> Image:
	# R = grounded solid mass (floating art excluded); G = wide soft "backing shell" field (the mass dilated
	# and blurred over ~8 tiles): cliff / ruin walls stepping back behind every structure
	var buf := PackedByteArray()
	buf.resize(W * H)
	var logo := Rect2i(300, 14, 46, 29)
	for i in W * H:
		var p := Vector2i(i % W, i / W)
		var m := solid[i] == 1 and level.fg[i] != 87 and not WorldPalette.FV_RECT_SCROLL.has_point(p) and not logo.has_point(p)
		buf[i] = 255 if m else 0
	var r := Image.create_from_data(W, H, false, Image.FORMAT_L8, buf)
	var g := r.duplicate() as Image
	g.resize(W / 8, H / 8, Image.INTERPOLATE_BILINEAR)
	g.resize(W, H, Image.INTERPOLATE_CUBIC)
	r.resize(W / 2, H / 2, Image.INTERPOLATE_BILINEAR)
	r.resize(W, H, Image.INTERPOLATE_CUBIC)
	var rd := r.get_data()
	var gd := g.get_data()
	var out := PackedByteArray()
	out.resize(W * H * 2)
	for i in W * H:
		out[i * 2] = rd[i]
		out[i * 2 + 1] = mini(255, int(gd[i] * 2.2))
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RG8, out)
	img.resize(W * 2, H * 2, Image.INTERPOLATE_BILINEAR)
	return img

## Day levels: soft density masks of the painted sky features, R = clouds (flat pale components),
## G = distant mountain ranges (tall pale components). Upsampled 4x and blurred so no pixel steps remain.
func sky_mask_image() -> Image:
	var mm := _load_minimap()
	if mm == null or mm.get_width() != W:
		return null
	var src := mm.get_data()
	var pale := PackedByteArray()
	pale.resize(W * H)
	for i in W * H:
		if not sky[i] or _is_border(i % W, i / W):
			continue
		var r: int = src[i * 3]; var g: int = src[i * 3 + 1]; var b: int = src[i * 3 + 2]
		if absi(r - 199) + absi(g - 217) + absi(b - 255) < 12:
			pale[i] = 1
	var clouds := PackedByteArray(); clouds.resize(W * H)
	var mounts := PackedByteArray(); mounts.resize(W * H)
	var seen := PackedByteArray(); seen.resize(W * H)
	for start in W * H:
		if not pale[start] or seen[start]:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var y0 := start / W
		var y1 := y0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			y0 = mini(y0, y); y1 = maxi(y1, y)
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if pale[j] and not seen[j]:
					seen[j] = 1
					comp.append(j)
		var tall := y1 - y0 >= 12
		for i in comp:
			if tall:
				mounts[i] = 255
			else:
				clouds[i] = 255
	var ci := Image.create_from_data(W, H, false, Image.FORMAT_L8, clouds)
	var mi := Image.create_from_data(W, H, false, Image.FORMAT_L8, mounts)
	ci.resize(W / 2, H / 2, Image.INTERPOLATE_BILINEAR)
	ci.resize(W * 4, H * 4, Image.INTERPOLATE_CUBIC)
	mi.resize(W * 4, H * 4, Image.INTERPOLATE_CUBIC)
	var out := Image.create(W * 4, H * 4, false, Image.FORMAT_RG8)
	var cd := ci.get_data()
	var md := mi.get_data()
	var od := PackedByteArray(); od.resize(W * H * 32)
	for i in W * H * 16:
		od[i * 2] = cd[i]
		od[i * 2 + 1] = md[i]
	out.set_data(W * 4, H * 4, false, Image.FORMAT_RG8, od)
	return out

## Day levels: bare earth near open sky with no grass or foliage on top (the painted mountain peaks)
## becomes layered rocky crag instead of soil.
func _mark_crags(fgb: PackedByteArray) -> void:
	# a tile is mountain crag when the column above it, up to open sky, is only bare earth (no grass,
	# foliage or stone cap) - i.e. the painted peaks, not hills under a grass top
	for x in W:
		var run := true
		for y in range(1, mini(H, 70)):
			var i := y * W + x
			if sky[i]:
				run = true
				continue
			if not run:
				continue
			if solid[i] and mat_ids[i] == WorldPalette.M_EARTH:
				mat_ids[i] = WorldPalette.M_CRAG
				fgb[i * 4 + 3] = WorldPalette.M_CRAG
			else:
				run = false

## Day levels: a lone bg tile whose colour none of its 8 neighbours share (e.g. the pink 547 at the FV
## spawn) takes the most common neighbour colour, so it can't read as an object on the back wall.
func _despeckle_bg(bgb: PackedByteArray, has_bgc: PackedByteArray) -> void:
	var src := bgb.duplicate()
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if not has_bgc[i]:
				continue
			var mine := Vector3i(src[i * 4], src[i * 4 + 1], src[i * 4 + 2])
			var counts := {}
			var same := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var j := i + dy * W + dx
					if not has_bgc[j]:
						continue
					var c := Vector3i(src[j * 4], src[j * 4 + 1], src[j * 4 + 2])
					if c == mine:
						same = true
					counts[c] = counts.get(c, 0) + 1
			if same or counts.is_empty():
				continue
			var best: Vector3i = counts.keys()[0]
			for c in counts:
				if counts[c] > counts[best]:
					best = c
			bgb[i * 4] = best.x; bgb[i * 4 + 1] = best.y; bgb[i * 4 + 2] = best.z

## Day levels: soft neighbourhood masks for material transitions (RGBA8, blurred over ~1 tile):
## r = foliage, g = grass, b = water, a = stone/ruin. The shader blends pair-specific transitions
## (leaf spill onto trunks / litter, grass fringe + roots, wet band + algae, soil in joints / moss creep).
func transition_image() -> Image:
	var buf := PackedByteArray()
	buf.resize(W * H * 4)
	for i in W * H:
		if not solid[i]:
			continue
		var m: int = mat_ids[i]
		if m == WorldPalette.M_FOLIAGE: buf[i * 4] = 255
		elif m == WorldPalette.M_GRASS: buf[i * 4 + 1] = 255
		elif m == WorldPalette.M_WATER: buf[i * 4 + 2] = 255
		elif m == WorldPalette.M_RUIN or m == WorldPalette.M_STONE or m == WorldPalette.M_CRAG: buf[i * 4 + 3] = 255
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, buf)
	img.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	img.resize(W, H, Image.INTERPOLATE_BILINEAR)   # ~1 tile soft band
	return img

## For the sky backdrop: blurred solid mask (L8, W x H, 1 texel per tile, blurred over ~3 tiles). Use it to
## darken the backdrop just below masses (sample at p + (0, 1..2) tiles).
func contact_mask_image() -> Image:
	var b := PackedByteArray()
	b.resize(W * H)
	for i in W * H:
		b[i] = 255 if solid[i] else 0
	var img := Image.create_from_data(W, H, false, Image.FORMAT_L8, b)
	img.resize(W / 3, H / 3, Image.INTERPOLATE_BILINEAR)
	img.resize(W, H, Image.INTERPOLATE_CUBIC)
	return img

static func _has_bg(id: int) -> bool:
	return id >= 500 and id != 645

## Key-door tiles used as ART: door regions (same id, 8-connected) larger than ART_DOOR_MIN tiles, and
## every door tile inside the demon. Value = key colour 1 red / 2 green / 3 blue, 0 = normal door.
const ART_DOOR_MIN := 30
var art_door := PackedByteArray()

func _find_art_doors() -> void:
	art_door.resize(W * H)
	art_door.fill(0)
	if not WorldPalette.is_odyssey():
		return
	var seen := PackedByteArray()
	seen.resize(W * H)
	for start in W * H:
		var id: int = level.fg[start]
		if seen[start] or not WorldPalette.is_key_door(id):
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var in_demon := false
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			if WorldPalette.RECT_DEMON.has_point(Vector2i(x, y)):
				in_demon = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					if seen[j] or level.fg[j] != id:
						continue
					seen[j] = 1
					comp.append(j)
		if comp.size() >= ART_DOOR_MIN or (in_demon and not WorldPalette.is_gate(id)):
			var c: StringName = WorldPalette.key_color_of(id)
			var v := 1 if c == &"red" else (2 if c == &"green" else 3)
			for i in comp:
				art_door[i] = v

## Day levels: painted "distant mountain" bg (541-544) regions that never touch the real sky art (bg 0 /
## 530 / 531 / 540) are interior walls in the painting (e.g. the Great Hall), not sky.
var enclosed_sky_bg := PackedByteArray()

## Day levels: which painted "sky" bg belongs to a STRUCTURE. 541-544 are the painter's grey/dark stone
## interior walls (halloween2011 bgs) - walls, except a region lying outside every structure and bordered by
## 531/540 sky paint (the open-sky mountain art). 530/531/540 stay sky, except inside a structure (walled
## left + right and roofed over most of the region): there they become framed WINDOWS in the stone wall.
## enclosed_sky_bg = 1 -> recessed wall; window = 1 -> a window opening in that wall.
const STRUCT_SIDE := 24         # tiles: solid within this distance left AND right ...
const STRUCT_ROOF := 30         # ... and a roof above -> the tile is inside a structure (open sky above = outside)
const WINDOW_MAX := 600         # painted sky patches bigger than this are open sky, never a window
const WINDOW_SIDE := 10         # a window patch is walled within this distance left and right ...
const WINDOW_ROOF := 14         # ... and roofed within this distance
var window := PackedByteArray()
var wall_code := PackedByteArray()   # window_image() codes per tile (0 / 2 earth / 6 stone / >= 40 window)

func _world_solid_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return true
	return WorldPalette.is_world_solid(level.fg[y * W + x])

func _inside_structure(x: int, y: int, side: int = STRUCT_SIDE, roof: int = STRUCT_ROOF) -> bool:
	var l := false
	var r := false
	var u := false
	for k in range(1, side + 1):
		if not l and _world_solid_at(x - k, y):
			l = true
		if not r and _world_solid_at(x + k, y):
			r = true
	for k in range(1, roof + 1):
		if y - k >= 0 and WorldPalette.is_world_solid(level.fg[(y - k) * W + x]):
			u = true
			break
	return l and r and u

func _inside_fraction(comp: PackedInt32Array, side: int = STRUCT_SIDE, roof: int = STRUCT_ROOF) -> float:
	var n := 0
	for i in comp:
		if _inside_structure(i % W, i / W, side, roof):
			n += 1
	return float(n) / maxf(1.0, comp.size())

func _find_enclosed_sky_bg() -> void:
	enclosed_sky_bg.resize(W * H)
	enclosed_sky_bg.fill(0)
	window.resize(W * H)
	window.fill(0)
	if not day:
		return
	var paint := func(b: int) -> bool: return b == 530 or b == 531 or b == 540
	var stone := func(b: int) -> bool: return b == 541 or b == 542 or b == 543 or b == 544
	var seen := PackedByteArray()
	seen.resize(W * H)
	for start in W * H:
		var b0: int = level.bg[start]
		if seen[start] or WorldPalette.is_world_solid(level.fg[start]) or not (paint.call(b0) or stone.call(b0)):
			continue
		var is_stone: bool = stone.call(b0)
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var touches_paint := false
		var edges := 0
		var wall_edges := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				var bj: int = level.bg[j]
				var in_comp: bool = not WorldPalette.is_world_solid(level.fg[j]) and (stone.call(bj) if is_stone else paint.call(bj))
				if not in_comp:
					edges += 1
					if not WorldPalette.is_world_solid(level.fg[j]) and bj != 0 and not paint.call(bj):
						wall_edges += 1   # a painted wall (stone / brick bg) next to the patch
				if WorldPalette.is_world_solid(level.fg[j]):
					continue
				if is_stone and (paint.call(bj) or bj == 0):
					touches_paint = true
				if not seen[j] and (stone.call(bj) if is_stone else paint.call(bj)):
					seen[j] = 1
					comp.append(j)
		var inside := _inside_fraction(comp)
		if is_stone:
			# a tiny speck of the painted mountains inside cloud / sky paint is sky, not a floating stone block
			var speck_sky := comp.size() <= 6 and touches_paint and edges > 0 and (edges - wall_edges) * 4 >= edges * 3
			if speck_sky:
				continue
			if inside >= 0.5 or not touches_paint:
				for i in comp:
					enclosed_sky_bg[i] = 1
		elif comp.size() <= WINDOW_MAX and wall_edges * 8 >= edges and _inside_fraction(comp, WINDOW_SIDE, WINDOW_ROOF) >= 0.7:
			# a window is a hole in a wall: at least an eighth of its outline is painted wall, not just rock
			for i in comp:
				enclosed_sky_bg[i] = 1
				window[i] = 1

## Earth cave wall: an earthy painted bg (512/510/511/505/508/534) whose surrounding solids (radius 5) are
## mostly natural ground (earth, grass, stone, crag...) rather than built ruin stone.
const EARTH_BG := [512, 510, 511, 505, 508, 534]

func _earth_wall(i: int) -> bool:
	if not (level.bg[i] in EARTH_BG):
		return false
	var x := i % W
	var y := i / W
	var nat := 0
	var tot := 0
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if not solid[j]:
				continue
			tot += 1
			if WorldDepth._natural(mat_ids[j]) or mat_ids[j] == WorldPalette.M_WOOD:
				nat += 1
	return tot == 0 or nat * 2 >= tot

## R8 per tile: 0 = nothing, 2 = earth cave wall, 6 = structure stone wall, 6 + 34 * (tiles to the nearest non-window tile) for
## windows. The terrain shader carves the opening deep inside a window and draws the stone frame around it.
func window_image() -> Image:
	var d := PackedInt32Array(); d.resize(W * H)
	var q := PackedInt32Array()
	for i in W * H:
		if window[i]:
			d[i] = 1 << 20
		else:
			d[i] = 0
			q.append(i)
	var qi := 0
	while qi < q.size():
		var i := q[qi]; qi += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if d[j] > d[i] + 1:
				d[j] = d[i] + 1
				q.append(j)
	var b := PackedByteArray(); b.resize(W * H)
	for i in W * H:
		# 6 = a structure's stone interior wall (ashlar in the shader), >= 40 = window (6 + 34 per tile inward)
		if window[i]:
			b[i] = mini(6 + d[i] * 34, 255)
		elif backwall[i] and not solid[i]:
			b[i] = 2 if _earth_wall(i) else 6
		elif not solid[i] and not sky[i]:
			b[i] = 2   # enclosed air without a painted bg (caves, pores): an earth cave room, never a floating slab
		else:
			b[i] = 0
	# a 1-3 tile "stone interior" speck (e.g. FV's spawn tile, bg 547 inside the grove) is not a room: it
	# kept a stone room block + backdrop hole in the middle of the forest hollow
	var seen := PackedByteArray(); seen.resize(W * H)
	for start in W * H:
		if seen[start] or b[start] < 5:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var ci := 0
		while ci < comp.size():
			var i := comp[ci]; ci += 1
			for k in 4:
				var nx := i % W + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := i / W + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if b[j] >= 5 and not seen[j]:
					seen[j] = 1
					comp.append(j)
		if comp.size() <= 3:
			for i in comp:
				b[i] = 2   # not a stone room: plain earth / cave (a forest hollow still owns it where it has one)
	wall_code = b
	return Image.create_from_data(W, H, false, Image.FORMAT_L8, b)

## Day levels: air that may show the sky - a clear column of air up to the level top, or within SKY_REACH
## tiles (through air) of such a column. The flood alone also reached underground halls via long corridors.
const SKY_REACH := 10

## Big sky paint (sky / cloud bg 530/531/540) walled in by the spires or bridged over (the Hanging Gardens gap
## between the Great and Twin Spires, user report): the EE minimap shows it as open sky, so it is sky (with the
## vista behind), not a sealed painted wall. Small patches keep the window / notch rules.
const PAINTED_SKY_MIN := 150

func _open_painted_sky(open: PackedByteArray) -> void:
	var n := W * H
	var opened := PackedByteArray(); opened.resize(n)
	var seen := PackedByteArray(); seen.resize(n)
	for s0 in n:
		var b0: int = level.bg[s0]
		if seen[s0] or solid[s0] or not (b0 == 530 or b0 == 531 or b0 == 540) or enclosed_sky_bg[s0]:
			continue
		var comp := PackedInt32Array([s0]); seen[s0] = 1
		var qi := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			for o in [-1, 1, -W, W]:
				var j: int = i + o
				if j < 0 or j >= n or seen[j] or solid[j]:
					continue
				var bj: int = level.bg[j]
				if (bj == 530 or bj == 531 or bj == 540) and not enclosed_sky_bg[j]:
					seen[j] = 1
					comp.append(j)
		if comp.size() >= PAINTED_SKY_MIN:
			for i in comp:
				open[i] = 1
				opened[i] = 1
	# thin (<= 2 wide) strips of the darker stone-sky paint (541-544) along an opened region's edge are part of
	# that sky too - left as a 1-tile wall they show the new sky around them (keep (286,93-95))
	var seen2 := PackedByteArray(); seen2.resize(n)
	for s0 in n:
		var b0: int = level.bg[s0]
		if seen2[s0] or solid[s0] or opened[s0] or b0 < 541 or b0 > 544:
			continue
		var comp := PackedInt32Array([s0]); seen2[s0] = 1
		var qi := 0
		var touches := false
		var x0 := W; var x1 := -1; var y0 := H; var y1 := -1
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			x0 = mini(x0, i % W); x1 = maxi(x1, i % W); y0 = mini(y0, i / W); y1 = maxi(y1, i / W)
			for o in [-1, 1, -W, W]:
				var j: int = i + o
				if j < 0 or j >= n or solid[j]:
					continue
				if opened[j]:
					touches = true
				var bj: int = level.bg[j]
				if not seen2[j] and not opened[j] and bj >= 541 and bj <= 544:
					seen2[j] = 1
					comp.append(j)
		if touches and comp.size() <= 24 and mini(x1 - x0, y1 - y0) <= 1:
			for i in comp:
				open[i] = 1
				enclosed_sky_bg[i] = 0
				backwall[i] = 0
				_deferred[i] = 1   # joins the sky below (painted sky -> sky where open)

func _open_sky_mask() -> PackedByteArray:
	var n := W * H
	var o := PackedByteArray(); o.resize(n)
	var dist := PackedInt32Array(); dist.resize(n); dist.fill(1 << 20)
	var q := PackedInt32Array()
	for x in W:
		for y in H:
			var i := y * W + x
			if solid[i]:
				break
			o[i] = 1
			dist[i] = 0
			q.append(i)
	# open air continues through WIDE air (>= 20 of the 25 tiles around it are air) without a distance limit:
	# the space under floating features (scroll, logo, islands, bridges) stays sky, while narrow corridors
	# into underground halls stop the flood (the reach below then fades it out)
	var wide := PackedByteArray(); wide.resize(n)
	for y in H:
		for x in W:
			var i := y * W + x
			if solid[i]:
				continue
			var c := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := clampi(x + dx, 0, W - 1)
					var ny := clampi(y + dy, 0, H - 1)
					if not solid[ny * W + nx]:
						c += 1
			wide[i] = 1 if c >= 20 else 0
	var wq := q.duplicate()
	var wi := 0
	while wi < wq.size():
		var i := wq[wi]; wi += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if o[j] or not wide[j]:
				continue
			o[j] = 1
			dist[j] = 0
			wq.append(j)
			q.append(j)
	var qi := 0
	while qi < q.size():
		var i := q[qi]; qi += 1
		if dist[i] >= SKY_REACH:
			continue
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if solid[j] or dist[j] <= dist[i] + 1:
				continue
			dist[j] = dist[i] + 1
			o[j] = 1
			q.append(j)
	return o

## Day levels: tiny (<= 6 tile) back-wall specks of SKY paint (530/531/540) or painted mountains (541-544) whose
## outline is mostly open sky are sky, not small stone blocks floating in the air.
func hol_ok(comp: PackedInt32Array) -> bool:
	# painted specks the forest hollow owns stay with the forest
	var h: PackedByteArray = get_meta(&"forest_hollow") if has_meta(&"forest_hollow") else PackedByteArray()
	for i in comp:
		if h.size() == W * H and h[i]:
			return true
	return false

func _sky_specks(has_bgc: PackedByteArray) -> void:
	var n := W * H
	var seen := PackedByteArray(); seen.resize(n)
	var changed := false
	for s0 in n:
		if seen[s0] or not backwall[s0] or solid[s0]:
			continue
		var sky_paint: bool = level.bg[s0] in WorldPalette.FV_SKY_BG
		var comp := PackedInt32Array([s0]); seen[s0] = 1
		var qi := 0
		var edges := 0
		var skye := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			for o in [-1, 1, -W, W]:
				var j: int = i + o
				if j < 0 or j >= n:
					continue
				if backwall[j] and not solid[j] and ((level.bg[j] in WorldPalette.FV_SKY_BG) == sky_paint):
					if not seen[j]:
						seen[j] = 1
						comp.append(j)
				else:
					edges += 1
					if sky[j] and not solid[j]:
						skye += 1
		# sky / mountain paint: <= 6 tiles, >= 50% open-sky outline. Other painted bg (a 1-2 tile forest / earth
		# speck hanging under a crown with sky on 3 sides) would render as a floating dark block: sky too
		var is_speck := comp.size() <= 6 and skye * 2 >= edges if sky_paint else comp.size() <= 2 and skye * 4 >= edges * 3
		if edges > 0 and is_speck and not (hol_ok(comp)):
			for i in comp:
				backwall[i] = 0
				has_bgc[i] = 0
				sky[i] = 1
				zones[i] = WorldPalette.Z_DAY
				enclosed_sky_bg[i] = 0
			changed = true

func _classify() -> void:
	_find_art_doors()
	_find_enclosed_sky_bg()
	var n := W * H
	solid.resize(n); mat_ids.resize(n); zones.resize(n); sky.resize(n); backwall.resize(n)
	solid.fill(0); sky.fill(0); backwall.fill(0)
	_deferred.resize(n); _deferred.fill(0)
	_deferred_col.resize(n)
	fgcol_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	bgcol_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	info_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	var fgb := PackedByteArray(); fgb.resize(n * 4)
	var bgb := PackedByteArray(); bgb.resize(n * 4)
	var has_fg := PackedByteArray(); has_fg.resize(n)
	var has_bgc := PackedByteArray(); has_bgc.resize(n)
	var mm := _load_minimap()
	var mmd := mm.get_data() if mm else PackedByteArray()
	var mm_ok := mm != null and mm.get_width() == W and mm.get_height() == H
	for y in H:
		for x in W:
			var i := y * W + x
			var id: int = level.fg[i]
			var z := WorldPalette.zone_at(x, y)
			zones[i] = z
			var border_rock := false
			if _is_border(x, y):
				# EE world border (always solid in physics). Visually: the top row above open air is not
				# drawn at all (the sky continues); elsewhere it continues its inner neighbour's rock, or
				# is plain dark bedrock.
				var inner: int = level.fg[clampi(y, 1, H - 2) * W + clampi(x, 1, W - 2)]
				if y == 0 and not WorldPalette.is_world_solid(inner):
					continue
				if day and not WorldPalette.is_world_solid(inner):
					continue   # day levels: no border slab beside/under open air either (the sky continues)
				if WorldPalette.is_world_solid(inner):
					id = inner
				else:
					id = 44
					border_rock = true
			# THE canonical colour of every tile = the EE minimap (CONTRACTS "canonical art")
			var mc := Color8(mmd[i * 3], mmd[i * 3 + 1], mmd[i * 3 + 2]) if mm_ok else WorldPalette.base_color(id)
			if _is_border(x, y):
				var ii := clampi(y, 1, H - 2) * W + clampi(x, 1, W - 2)
				mc = Color8(mmd[ii * 3], mmd[ii * 3 + 1], mmd[ii * 3 + 2]) if mm_ok else mc
			if border_rock:
				solid[i] = 1
				mat_ids[i] = WorldPalette.M_STONE
				fgb[i * 4] = 42; fgb[i * 4 + 1] = 36; fgb[i * 4 + 2] = 34; fgb[i * 4 + 3] = WorldPalette.M_STONE
				has_fg[i] = 1
				continue
			if art_door[i]:
				# key-door tiles that are part of the painting (demon body, pink flesh tube, upper pond):
				# sculpted as the surrounding terrain mass; hidden while their key is active
				solid[i] = 1
				# blue door pond: frozen glassy crystal (reads SOLID, unlike lake water); others: sculpted flesh
				var am := WorldPalette.M_ICE if art_door[i] == 3 else WorldPalette.M_FLESH
				mat_ids[i] = am
				fgb[i * 4] = mc.r8; fgb[i * 4 + 1] = mc.g8; fgb[i * 4 + 2] = mc.b8; fgb[i * 4 + 3] = am
				has_fg[i] = 1
				continue
			if WorldPalette.is_world_solid(id):
				solid[i] = 1
				var m := WorldPalette.material_for(id, x, y, z)
				if day and WorldForest.is_trunk_tile(level, x, y):
					m = WorldPalette.M_WOOD   # forest trunk columns (fg 47/48 under a crown): bark
				mat_ids[i] = m
				var c := mc
				if id == 50 or (c.get_luminance() < 0.02 and m != WorldPalette.M_OBSIDIAN):
					c = Color8(22, 20, 26)
				fgb[i * 4] = c.r8; fgb[i * 4 + 1] = c.g8; fgb[i * 4 + 2] = c.b8; fgb[i * 4 + 3] = m
				has_fg[i] = 1
				continue
			var b: int = level.bg[i]
			if day and (b == 0 or (b in WorldPalette.FV_SKY_BG and not enclosed_sky_bg[i]) or (_fg_has_minimap_colour(id) and not _has_bg(b))):
				# day level: the painted sky (and anything floating in it) is decided by the sky flood
				if b != 0 or (mm_ok and _fg_has_minimap_colour(id)):
					_deferred[i] = 1
					_deferred_col[i] = mc
				continue
			if _has_bg(b) or (mm_ok and _fg_has_minimap_colour(id) and not WorldPalette.is_key_door(id)):
				# bg block, or minimap-coloured air (key dither, crowns, portals): recessed back wall
				var bc: Color = mc if mm_ok else WorldPalette.BG_COLORS.get(b, Color8(40, 40, 40))
				bgb[i * 4] = bc.r8; bgb[i * 4 + 1] = bc.g8; bgb[i * 4 + 2] = bc.b8; bgb[i * 4 + 3] = 255
				has_bgc[i] = 1
				backwall[i] = 1
	_compute_sky()
	for x in W:
		if not solid[x] and sky[W + x]:
			sky[x] = 1
	_sky_flood = sky.duplicate()   # open air reached from the top (before painted-sky windows join the sky)
	if day:
		_mark_crags(fgb)
		var open := _open_sky_mask()
		_open_painted_sky(open)
		for i in n:
			if not sky[i] and _deferred[i] and level.bg[i] in WorldPalette.FV_SKY_BG and not enclosed_sky_bg[i]:
				sky[i] = 1   # painted sky seen through windows / behind the falls is real sky, not a wall
			if sky[i] and not open[i] and not solid[i]:
				sky[i] = 0   # deep underground air the flood reached through corridors: never see-through
				if not _deferred[i] and level.bg[i] == 0:
					continue
				if not _deferred[i]:
					continue
			if sky[i]:
				zones[i] = WorldPalette.Z_DAY
			elif _deferred[i]:
				# sky-painted bg sealed inside the ruins (windows...): a recessed painted wall
				var bc := _deferred_col[i]
				bgb[i * 4] = bc.r8; bgb[i * 4 + 1] = bc.g8; bgb[i * 4 + 2] = bc.b8; bgb[i * 4 + 3] = 255
				has_bgc[i] = 1
				backwall[i] = 1
		_classify_bg_regions(has_bgc)
		# the region pass re-floods the sky: keep it inside the open-sky mask, and give painted bg that ended
		# up neither sky nor wall (an "exterior" region the sky cannot reach) its recessed wall back
		for i in n:
			if sky[i] and not open[i] and not solid[i] and not _deferred[i]:
				sky[i] = 0
			if not sky[i] and not solid[i] and not backwall[i] and level.bg[i] != 0 and not (level.bg[i] in WorldPalette.FV_SKY_BG):
				backwall[i] = 1
				has_bgc[i] = 1
				bg_region[i] = 1
		_sky_specks(has_bgc)
	var orig := fgb.duplicate()
	fgb = WorldSdfBaker.merge_colors(fgb, W, H)
	_dilate(fgb, has_fg)
	for i in n:
		if not has_fg[i]:
			orig[i * 4] = fgb[i * 4]; orig[i * 4 + 1] = fgb[i * 4 + 1]; orig[i * 4 + 2] = fgb[i * 4 + 2]; orig[i * 4 + 3] = fgb[i * 4 + 3]
	orig_img = Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, orig)
	_find_pockets()
	_find_specks()
	for i in n:
		if pocket[i] == 1 and not has_bgc[i]:
			bgb[i * 4] = int(fgb[i * 4] * 0.5); bgb[i * 4 + 1] = int(fgb[i * 4 + 1] * 0.5)
			bgb[i * 4 + 2] = int(fgb[i * 4 + 2] * 0.5); bgb[i * 4 + 3] = 255
			has_bgc[i] = 1
	if day:
		_despeckle_bg(bgb, has_bgc)
	_dilate(bgb, has_bgc)
	# bg alpha: 255 present, else 0 (colour stays dilated)
	for i in n:
		if not has_bgc[i]:
			bgb[i * 4 + 3] = 0
	fgcol_img.set_data(W, H, false, Image.FORMAT_RGBA8, fgb)
	bgcol_img.set_data(W, H, false, Image.FORMAT_RGBA8, bgb)
	var inf := PackedByteArray(); inf.resize(n * 4)
	for i in n:
		inf[i * 4] = (80 + art_door[i] * 40) if art_door[i] else (255 if solid[i] else 0)
		inf[i * 4 + 1] = 255 if backwall[i] else 0
		inf[i * 4 + 2] = zones[i]
		inf[i * 4 + 3] = 255 if sky[i] else 0
	info_img.set_data(W, H, false, Image.FORMAT_RGBA8, inf)

## Day levels: the painter put bg blocks behind floating structures for the 2D image; in 3D they would hang
## in the open sky as recessed walls. Every connected back-wall region is classified by its perimeter:
## INTERIOR (enclosed: < 30% of its boundary edges open to sky air) keeps the recessed wall, EXTERIOR
## (decorative, open to the sky) becomes plain sky. bg_region: 0 none, 1 interior, 2 exterior.
const BG_OPEN_MAX := 0.3
var bg_region := PackedByteArray()
var _sky_flood := PackedByteArray()

func _classify_bg_regions(has_bgc: PackedByteArray) -> void:
	var n := W * H
	bg_region.resize(n)
	bg_region.fill(0)
	var seen := PackedByteArray(); seen.resize(n)
	var converted := false
	for start in n:
		if seen[start] or not backwall[start] or solid[start]:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var perim := 0
		var open := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					perim += 1   # the EE border is solid
					continue
				var j := ny * W + nx
				if backwall[j] and not solid[j]:
					if not seen[j]:
						seen[j] = 1
						comp.append(j)
					continue
				perim += 1
				if _sky_flood[j]:
					open += 1
		var exterior := perim > 0 and float(open) / perim >= BG_OPEN_MAX and _inside_fraction(comp) < 0.5
		for i in comp:
			bg_region[i] = 2 if exterior else 1
			if exterior:
				backwall[i] = 0
				has_bgc[i] = 0
				converted = true
	if converted:
		_compute_sky()
		for i in n:
			if sky[i]:
				zones[i] = WorldPalette.Z_DAY

## Overview for the lead: solid grey, interior walls green (structure stone walls dark green), windows cyan,
## exterior bg (now sky) red, enclosed air blue, sky black. 1 px / tile.
func bg_region_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var i := y * W + x
			var c := Color(0, 0, 0)
			if solid[i]:
				c = Color(0.35, 0.35, 0.35)
			elif window.size() == W * H and window[i]:
				c = Color(0.2, 0.9, 1.0)   # window in a structure wall
			elif enclosed_sky_bg.size() == W * H and enclosed_sky_bg[i]:
				c = Color(0.05, 0.45, 0.12)   # structure stone wall (541-544 / enclosed sky paint)
			elif bg_region[i] == 1:
				c = Color(0.1, 0.8, 0.2)
			elif bg_region[i] == 2:
				c = Color(0.9, 0.15, 0.1)
			elif not sky[i]:
				c = Color(0.1, 0.2, 0.5)
			img.set_pixel(x, y, c)
	return img

## Multi-source BFS: copies the nearest filled tile's rgba into unfilled tiles (keeps colour sampling
## at solid boundaries free of "air" colour).
func _dilate(buf: PackedByteArray, filled: PackedByteArray) -> void:
	var q := PackedInt32Array()
	var done := filled.duplicate()
	for i in W * H:
		if done[i]:
			q.append(i)
	var qi := 0
	while qi < q.size():
		var i := q[qi]; qi += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if done[j]:
				continue
			done[j] = 1
			buf[j * 4] = buf[i * 4]; buf[j * 4 + 1] = buf[i * 4 + 1]; buf[j * 4 + 2] = buf[i * 4 + 2]; buf[j * 4 + 3] = buf[i * 4 + 3]
			q.append(j)

var flat_pocket := PackedByteArray()

func _field_image() -> Image:
	flat_pocket.resize(W * H)
	flat_pocket.fill(0)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var b := PackedByteArray(); b.resize(W * H * 4)
	for i in W * H:
		b[i * 4] = 255 if sky[i] else 0
		b[i * 4 + 1] = 255 if pocket[i] else 0
		b[i * 4 + 2] = 255 if speck[i] else 0
		# a = 0: shallow inscription pocket (non-solid letter tiles in the FV scroll / ΣX logo) -> floor z -0.85
		var pt := Vector2i(i % W, i / W)
		var inscr := day and not solid[i] and (WorldPalette.FV_RECT_SCROLL.has_point(pt) or Rect2i(300, 14, 46, 29).has_point(pt))
		b[i * 4 + 3] = 0 if inscr else 255
	# a = 128: a tiny (<= 3 tile) wall pocket right beside open sky -> near-flat floor (z -0.9, normal shading):
	# a deep recess there shows the neighbouring sky through it at an angle (parallax)
	if day:
		var seen := PackedByteArray(); seen.resize(W * H)
		for s0 in W * H:
			if seen[s0] or solid[s0] or sky[s0] or b[s0 * 4 + 3] == 0:
				continue
			var comp := PackedInt32Array([s0]); seen[s0] = 1
			var qi := 0
			var touches := false
			while qi < comp.size() and comp.size() <= 4:
				var i := comp[qi]; qi += 1
				for o in [-1, 1, -W, W]:
					var j: int = i + o
					if j < 0 or j >= W * H:
						continue
					if sky[j] and not solid[j]:
						touches = true
					elif not solid[j] and not sky[j] and not seen[j]:
						seen[j] = 1
						comp.append(j)
			if touches and comp.size() <= 3:
				for i in comp:
					b[i * 4 + 3] = 128
					flat_pocket[i] = 1
	img.set_data(W, H, false, Image.FORMAT_RGBA8, b)
	return img

## Per material: sculpted height offset (tiles) and surface relief amplitude.
const RELIEF := {
	WorldPalette.M_EARTH: [0.0, 1.0], WorldPalette.M_STONE: [0.05, 1.2], WorldPalette.M_MARBLE: [0.0, 0.2],
	WorldPalette.M_ICE: [0.1, 0.4], WorldPalette.M_WATER: [-0.1, 0.05], WorldPalette.M_CORRUPT: [0.06, 1.0],
	WorldPalette.M_FIRE: [0.1, 0.7], WorldPalette.M_OBSIDIAN: [0.0, 0.5], WorldPalette.M_GLASS: [0.08, 0.1],
	WorldPalette.M_GRASS: [0.06, 0.15], WorldPalette.M_FOLIAGE: [0.2, 2.0], WorldPalette.M_FLESH: [0.2, 0.7],
	WorldPalette.M_WOOD: [0.05, 0.5], WorldPalette.M_METAL: [0.05, 0.2], WorldPalette.M_CLOUD: [0.1, 0.25],
	WorldPalette.M_SAND: [0.0, 0.6], WorldPalette.M_GEM: [0.2, 0.08], WorldPalette.M_SNOW: [0.05, 0.9],
	WorldPalette.M_BONE: [0.1, 0.9], WorldPalette.M_RUIN: [0.04, 1.1], WorldPalette.M_CRAG: [0.08, 1.6],
}

## Surface pattern weights per material: [cobbles, domes, grain, strata].
const PATTERN := {
	WorldPalette.M_EARTH: [0.35, 0.0, 0.0, 0.8], WorldPalette.M_SAND: [0.1, 0.0, 0.3, 0.8],
	WorldPalette.M_FOLIAGE: [0.0, 1.0, 0.0, 0.0], WorldPalette.M_GRASS: [0.0, 0.5, 0.0, 0.3],
	WorldPalette.M_WOOD: [0.0, 0.0, 1.0, 0.0], WorldPalette.M_CLOUD: [0.0, 0.3, 0.6, 0.0],
	WorldPalette.M_FLESH: [0.0, 0.4, 0.5, 0.0], WorldPalette.M_FIRE: [0.3, 0.3, 0.0, 0.0],
	WorldPalette.M_SNOW: [0.6, 0.4, 0.0, 0.0], WorldPalette.M_BONE: [0.4, 0.3, 0.3, 0.0],
	WorldPalette.M_CORRUPT: [0.5, 0.3, 0.0, 0.2],
	WorldPalette.M_MARBLE: [0.0, 0.0, 0.0, 0.0], WorldPalette.M_GEM: [0.0, 0.0, 0.0, 0.0],
	WorldPalette.M_GLASS: [0.0, 0.0, 0.0, 0.0], WorldPalette.M_WATER: [0.0, 0.0, 0.0, 0.0],
	WorldPalette.M_METAL: [0.0, 0.0, 0.0, 0.0], WorldPalette.M_OBSIDIAN: [0.2, 0.0, 0.0, 0.0],
	WorldPalette.M_ICE: [0.3, 0.3, 0.0, 0.0], WorldPalette.M_RUIN: [0.9, 0.0, 0.0, 0.25], WorldPalette.M_CRAG: [0.15, 0.0, 0.0, 1.0],
}

func _pattern_image() -> Image:
	var b := PackedByteArray(); b.resize(W * H * 4)
	var data := fgcol_img.get_data()
	var canopy: PackedByteArray = WorldGrass.canopy_map(self) if day else PackedByteArray()
	for i in W * H:
		var m: int = data[i * 4 + 3]
		var pw: Array = PATTERN.get(m, [1.0, 0.0, 0.0, 0.0])
		if day and (m == WorldPalette.M_FOLIAGE or m == WorldPalette.M_GRASS) and canopy.size() == W * H and canopy[i] == 0:
			pw = [0.0, 0.0, 0.0, 0.2]
		for k in 4:
			b[i * 4 + k] = int(clampf(pw[k], 0.0, 1.0) * 255.0)
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, b)

func _relief_image() -> Image:
	var b := PackedByteArray(); b.resize(W * H * 2)
	var data := fgcol_img.get_data()   # alpha = material (dilated into air)
	for i in W * H:
		var m: int = data[i * 4 + 3]
		var r: Array = RELIEF.get(m, [0.0, 1.0])
		b[i * 2] = clampi(int((r[0] + 0.5) * 255.0), 0, 255)
		b[i * 2 + 1] = clampi(int(r[1] / 2.0 * 255.0), 0, 255)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RG8, b)
	return img

## Cave back-wall tint: heavily blurred foreground colours, darkened, nudged per zone.
func _tint_image() -> Image:
	var small := fgcol_img.duplicate() as Image
	small.resize(W / 8, H / 8, Image.INTERPOLATE_CUBIC)
	small.resize(W / 4, H / 4, Image.INTERPOLATE_BILINEAR)
	var zone_tint := [Color(0.5, 0.55, 0.7), Color(0.9, 0.6, 0.5), Color(1.0, 0.45, 0.25), Color(0.75, 0.45, 1.0),
		Color(0.6, 0.8, 1.0), Color(0.45, 0.6, 1.0), Color(0.7, 0.7, 0.8), Color(0.85, 0.7, 0.55), Color(0.9, 0.5, 0.5),
		Color(0.85, 0.9, 1.0), Color(0.75, 0.8, 0.8), Color(0.6, 0.75, 0.85)]
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			var z: int = zones[clampi(y * 4 + 2, 0, H - 1) * W + clampi(x * 4 + 2, 0, W - 1)]
			var zt: Color = zone_tint[z]
			var l := c.get_luminance()
			var d := c.lerp(Color(l, l, l), 0.35) * zt
			small.set_pixel(x, y, Color(d.r * 0.85, d.g * 0.85, d.b * 0.85))
	return small

func _noise_tex(freq: float, seed_v: int, octaves: int, normal_strength: float, ntype := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> ImageTexture:
	var fn := FastNoiseLite.new()
	fn.noise_type = ntype
	fn.frequency = freq
	fn.seed = seed_v
	fn.fractal_octaves = octaves
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	var img := fn.get_seamless_image(512, 512)
	img.convert(Image.FORMAT_RGBA8)
	if normal_strength > 0.0:
		img.bump_map_to_normal_map(normal_strength)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_material() -> void:
	var sdf_tex := ImageTexture.create_from_image(sdf_img)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/world/terrain.gdshader")
	material.set_shader_parameter("sdf_tex", sdf_tex)
	material.set_shader_parameter("field_tex", ImageTexture.create_from_image(_field_image()))
	material.set_shader_parameter("relief_tex", ImageTexture.create_from_image(_relief_image()))
	material.set_shader_parameter("pattern_tex", ImageTexture.create_from_image(_pattern_image()))
	material.set_shader_parameter("level_size", Vector2(W, H))
	material.set_shader_parameter("fgcol_tex", ImageTexture.create_from_image(fgcol_img))
	material.set_shader_parameter("orig_tex", ImageTexture.create_from_image(orig_img))
	if day:
		material.set_shader_parameter("mottle", 0.12)
		material.set_shader_parameter("bg_bevel", 0.12)   # day: back walls recessed and flat (readability)
		material.set_shader_parameter("bottom_cut", 1.0)
		var r := WorldPalette.FV_RECT_SCROLL
		material.set_shader_parameter("scroll_rect", Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		material.set_shader_parameter("trans_tex", ImageTexture.create_from_image(transition_image()))
		var sr := WorldPalette.FV_RECT_SHRINE
		material.set_shader_parameter("shrine_rect", Vector4(sr.position.x, sr.position.y + 2, sr.end.x, sr.end.y))
		material.set_shader_parameter("shrine_trophy", Vector2(WorldPalette.FV_SHRINE))
	material.set_shader_parameter("bgcol_tex", ImageTexture.create_from_image(bgcol_img))
	material.set_shader_parameter("info_tex", ImageTexture.create_from_image(info_img))
	if day:
		material.set_shader_parameter("window_tex", ImageTexture.create_from_image(window_image()))
		material.set_shader_parameter("forest_tex", ImageTexture.create_from_image(WorldForest.hollow_image(self)))
	material.set_shader_parameter("tint_tex", ImageTexture.create_from_image(_tint_image()))
	material.set_shader_parameter("detail_nrm", _noise_tex(0.025, 11, 5, 5.0))
	material.set_shader_parameter("detail_nrm2", _noise_tex(0.03, 23, 4, 4.0))
	material.set_shader_parameter("detail_hgt", _noise_tex(0.015, 37, 4, 0.0))
	WorldPbr.bind(material, WorldPalette.is_odyssey(), 1.0, self)

const HTPT := 16         # baked height texels per tile
const HMARGIN := 16      # tiles of margin in the height bake

## Renders the full height field once into an HDR SubViewport (GPU, reuses terrain_common include);
## the terrain samples it instead of evaluating the procedural height per vertex / shadow pass.
func _bake_height() -> void:
	var vp := SubViewport.new()
	vp.name = "HeightBake"
	vp.size = Vector2i((W + 2 * HMARGIN) * HTPT, (H + 2 * HMARGIN) * HTPT)
	vp.disable_3d = true
	vp.use_hdr_2d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/world/height_bake.gdshader")
	for k in ["sdf_tex", "field_tex", "relief_tex", "pattern_tex", "level_size", "bg_bevel"]:
		m.set_shader_parameter(k, material.get_shader_parameter(k))
	m.set_shader_parameter("margin", float(HMARGIN))
	rect.material = m
	vp.add_child(rect)
	add_child(vp)
	material.set_shader_parameter("height_tex", vp.get_texture())
	material.set_shader_parameter("height_margin", float(HMARGIN))
	material.set_shader_parameter("htpt", float(HTPT))

func _grid_mesh(vpt: int = VPT) -> ArrayMesh:
	var n := CHUNK * vpt
	var verts := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	var inv := 1.0 / vpt
	var k := 0
	for j in n + 1:
		var y := -j * inv
		for i in n + 1:
			verts[k] = Vector3(i * inv, y, 0.0)
			k += 1
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	k = 0
	var row := n + 1
	for j in n:
		for i in n:
			var a := j * row + i
			var b := a + 1
			var c := a + row
			var d := c + 1
			# alternate diagonals to avoid directional bias
			if (i + j) & 1:
				idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
				idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			else:
				idx[k] = a; idx[k + 1] = b; idx[k + 2] = d
				idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

const SHADOW_VPT := 4

## A distant, non-gameplay copy of the terrain pipeline for a synthetic level (EELevel with width/height/fg/bg;
## colours come from WorldPalette.base_color(id) since there is no minimap). Day styling. Returns the node;
## the caller adds it to the tree (under an identity-transform parent). origin = world position of tile
## (0, 0)'s top-left corner, scale = world units per tile.
## ref: the level's ref_dir (block-id minimap colour table); colours: optional W x H RGB8 image of per-tile
## colours (the "minimap" of the synthetic level) - without it each block uses WorldPalette.base_color(id).
static func build_backdrop(lvl: EELevel, origin: Vector3, scale: float, haze: float = 0.3,
		haze_color := Color(0.74, 0.82, 0.92), vpt := 3, ref := "res://assets/ee_ref_fv", colors: Image = null) -> WorldTerrain:
	var t := WorldTerrain.new()
	t.name = "BackdropTerrain"
	t.day = true
	t.backdrop = true
	t.backdrop_vpt = vpt
	t.ref_dir = ref
	t.minimap_override = colors
	t.build(lvl)
	t.set_placement(origin, scale)
	t.set_haze(haze, haze_color)
	return t

func set_placement(origin: Vector3, scale: float) -> void:
	transform = Transform3D(Basis.from_scale(Vector3.ONE * scale), origin)
	material.set_shader_parameter("level_inv", Projection(transform.affine_inverse()))

func set_haze(amount: float, color: Color) -> void:
	material.set_shader_parameter("backdrop_haze", amount)
	material.set_shader_parameter("backdrop_haze_color", color)

func _make_chunks() -> void:
	if backdrop:
		material.set_shader_parameter("backdrop_mode", 1.0)
	var mesh := _grid_mesh(backdrop_vpt if backdrop else VPT)
	var smesh := _grid_mesh(SHADOW_VPT)
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = load("res://shaders/world/terrain_shadow.gdshader")
	for k in ["sdf_tex", "field_tex", "level_size", "height_tex", "height_margin"]:
		shadow_material.set_shader_parameter(k, material.get_shader_parameter(k))
	var mg := 0 if backdrop else MARGIN
	var x0 := -mg
	while x0 < W + mg:
		var y0 := -mg
		while y0 < H + mg:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = material
			mi.position = Vector3(x0, -y0, 0.0)
			mi.custom_aabb = AABB(Vector3(0, -CHUNK, -14.5), Vector3(CHUNK, CHUNK, 16.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Chunk_%d_%d" % [x0, y0]
			add_child(mi)
			if backdrop:
				y0 += CHUNK
				continue
			var sh := MeshInstance3D.new()
			sh.mesh = smesh
			sh.material_override = shadow_material
			sh.position = mi.position
			sh.custom_aabb = mi.custom_aabb
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.name = "Shadow_%d_%d" % [x0, y0]
			add_child(sh)
			y0 += CHUNK
		x0 += CHUNK

## Which keys are active (art-door tiles of that colour are hidden from the terrain while true).
func set_keys_open(red: bool, green: bool, blue: bool) -> void:
	material.set_shader_parameter("keys_open", Vector3(1.0 if red else 0.0, 1.0 if green else 0.0, 1.0 if blue else 0.0))

## 0 off, 1 collision grid overlay, 2 zone map overlay, 3 solidity mask (white = rendered solid).
func set_debug_mode(mode: int) -> void:
	material.set_shader_parameter("debug_mode", mode)

func set_visual_map(visual: PackedByteArray) -> void:
	var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, visual)
	material.set_shader_parameter("visual_tex", ImageTexture.create_from_image(img))

func set_zone_map(tile_zone: PackedByteArray) -> void:
	var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, tile_zone)
	material.set_shader_parameter("zone_tex", ImageTexture.create_from_image(img))
