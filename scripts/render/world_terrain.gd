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
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ee_ref/minimap_colors.json"))
		if j is Dictionary:
			for k in j:
				if j[k] != null:
					_mm_ids[int(k)] = true
		_mm_ids[-1] = true
	return _mm_ids.has(id)

func _load_minimap() -> Image:
	var buf := FileAccess.get_file_as_bytes("res://assets/ee_ref/minimap_ee.png")
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
			if nx < 0 or ny < 1 or nx >= W or ny > SKY_MAX_Y:
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

static func _has_bg(id: int) -> bool:
	return id >= 500 and id != 645

## Key-door tiles used as ART: door regions (same id, 8-connected) larger than ART_DOOR_MIN tiles, and
## every door tile inside the demon. Value = key colour 1 red / 2 green / 3 blue, 0 = normal door.
const ART_DOOR_MIN := 30
var art_door := PackedByteArray()

func _find_art_doors() -> void:
	art_door.resize(W * H)
	art_door.fill(0)
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

func _classify() -> void:
	_find_art_doors()
	var n := W * H
	solid.resize(n); mat_ids.resize(n); zones.resize(n); sky.resize(n); backwall.resize(n)
	solid.fill(0); sky.fill(0); backwall.fill(0)
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
				var am := WorldPalette.M_WATER if WorldPalette.RECT_UPPER_LAKE.has_point(Vector2i(x, y)) else WorldPalette.M_FLESH
				mat_ids[i] = am
				fgb[i * 4] = mc.r8; fgb[i * 4 + 1] = mc.g8; fgb[i * 4 + 2] = mc.b8; fgb[i * 4 + 3] = am
				has_fg[i] = 1
				continue
			if WorldPalette.is_world_solid(id):
				solid[i] = 1
				var m := WorldPalette.material_for(id, x, y, z)
				mat_ids[i] = m
				var c := mc
				if id == 50 or (c.get_luminance() < 0.02 and m != WorldPalette.M_OBSIDIAN):
					c = Color8(22, 20, 26)
				fgb[i * 4] = c.r8; fgb[i * 4 + 1] = c.g8; fgb[i * 4 + 2] = c.b8; fgb[i * 4 + 3] = m
				has_fg[i] = 1
				continue
			var b: int = level.bg[i]
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

func _field_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var b := PackedByteArray(); b.resize(W * H * 4)
	for i in W * H:
		b[i * 4] = 255 if sky[i] else 0
		b[i * 4 + 1] = 255 if pocket[i] else 0
		b[i * 4 + 2] = 255 if speck[i] else 0
		b[i * 4 + 3] = 255
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
	WorldPalette.M_BONE: [0.1, 0.9],
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
	WorldPalette.M_ICE: [0.3, 0.3, 0.0, 0.0],
}

func _pattern_image() -> Image:
	var b := PackedByteArray(); b.resize(W * H * 4)
	var data := fgcol_img.get_data()
	for i in W * H:
		var m: int = data[i * 4 + 3]
		var pw: Array = PATTERN.get(m, [1.0, 0.0, 0.0, 0.0])
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
		Color(0.6, 0.8, 1.0), Color(0.45, 0.6, 1.0), Color(0.7, 0.7, 0.8), Color(0.85, 0.7, 0.55), Color(0.9, 0.5, 0.5)]
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
	material.set_shader_parameter("bgcol_tex", ImageTexture.create_from_image(bgcol_img))
	material.set_shader_parameter("info_tex", ImageTexture.create_from_image(info_img))
	material.set_shader_parameter("tint_tex", ImageTexture.create_from_image(_tint_image()))
	material.set_shader_parameter("detail_nrm", _noise_tex(0.025, 11, 5, 5.0))
	material.set_shader_parameter("detail_nrm2", _noise_tex(0.03, 23, 4, 4.0))
	material.set_shader_parameter("detail_hgt", _noise_tex(0.015, 37, 4, 0.0))

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
	for k in ["sdf_tex", "field_tex", "relief_tex", "pattern_tex", "level_size"]:
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

func _make_chunks() -> void:
	var mesh := _grid_mesh()
	var smesh := _grid_mesh(SHADOW_VPT)
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = load("res://shaders/world/terrain_shadow.gdshader")
	for k in ["sdf_tex", "field_tex", "level_size", "height_tex", "height_margin"]:
		shadow_material.set_shader_parameter(k, material.get_shader_parameter(k))
	var x0 := -MARGIN
	while x0 < W + MARGIN:
		var y0 := -MARGIN
		while y0 < H + MARGIN:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = material
			mi.position = Vector3(x0, -y0, 0.0)
			mi.custom_aabb = AABB(Vector3(0, -CHUNK, -14.5), Vector3(CHUNK, CHUNK, 16.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Chunk_%d_%d" % [x0, y0]
			add_child(mi)
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
