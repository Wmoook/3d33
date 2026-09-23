class_name WorldVistaBlocks
extends RefCounted
## Distant scenery painted with the level's OWN blocks (user idea: "manual art with real blocks far away so
## it looks really there"). Each piece is a small hand-designed tile map, authored like an EE level artist
## paints (Forgotten Veil's palette: grey temple stone 9/42/46/86 with black 44 window slots, earth
## 45/47/48/88, grass 35, leaves 19/14, pine 17, trunks 16, water 10), then rendered far behind the level.
## Maps: 0 ruin island (broken tower, trees), 1 second great spire, 2 aqueduct isle with a waterfall,
## 3 far keep. make_level(kind) returns an EELevel (fg/bg filled) so world's WorldTerrain can render it in
## backdrop mode; until then build_standin() renders the same map with vista_blocks.gdshader.

const STONE := 9
const STONE_LIT := 42
const STONE_DARK := 46
const LEDGE := 86
const HOLE := 44
const EARTH := 47
const EARTH_DARK := 45
const EARTH_RED := 48
const EARTH_DEEP := 88
const GRASS := 35
const LEAF := 19
const LEAF_LIT := 14
const PINE := 17
const TRUNK := 16
const WATER := 10

var w := 0
var h := 0
var fg := PackedInt32Array()
var rng := RandomNumberGenerator.new()

static func make(kind: int, seed_v: int = 1) -> WorldVistaBlocks:
	var m := WorldVistaBlocks.new()
	m.rng.seed = seed_v * 131 + kind
	match kind:
		0:
			m._ruin_island()
		1:
			m._great_spire()
		2:
			m._aqueduct_isle()
		_:
			m._far_keep()
	return m

## The map as an EELevel with a 1-tile empty border (WorldTerrain's sky flood needs it): tile (x, y) of
## the map is tile (x + 1, y + 1) of the level.
func make_level() -> EELevel:
	var lvl := EELevel.new()
	lvl.width = w + 2
	lvl.height = h + 2
	lvl.fg = PackedInt32Array()
	lvl.fg.resize(lvl.width * lvl.height)
	lvl.bg = PackedInt32Array()
	lvl.bg.resize(lvl.width * lvl.height)
	for y in h:
		for x in w:
			lvl.fg[(y + 1) * lvl.width + x + 1] = fg[y * w + x]
	return lvl

# ------------------------------------------------------------------ painting primitives (tile coords, y down)
func _init_map(mw: int, mh: int) -> void:
	w = mw
	h = mh
	fg.resize(w * h)
	fg.fill(0)

func put(x: int, y: int, id: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		fg[y * w + x] = id

func get_id(x: int, y: int) -> int:
	return fg[y * w + x] if x >= 0 and y >= 0 and x < w and y < h else 0

func rect(x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			put(x, y, id)

## A floating earth island: grassy top at top_y, rounded ends, a jagged keel tapering down `depth` rows.
## Returns the per-column surface row (so props can stand on it).
func island(cx: int, top_y: int, hw: int, depth: int) -> Dictionary:
	var surf := {}
	for x in range(cx - hw, cx + hw + 1):
		var t := absf(x - cx) / float(hw)
		var top := top_y + int(round(pow(t, 4.0) * 3.0 + rng.randf_range(-0.4, 0.4)))
		var d := int(depth * pow(maxf(1.0 - pow(t, 1.5), 0.0), 0.8)) + rng.randi_range(-1, 1) + 2
		surf[x] = top
		for y in range(top, top + d):
			var k := float(y - top) / maxf(d, 1)
			var id := EARTH
			var r := rng.randf()
			if k > 0.7:
				id = STONE_DARK if r < 0.6 else EARTH_DEEP
			elif k > 0.4:
				id = EARTH_DARK if r < 0.55 else (EARTH_DEEP if r < 0.7 else EARTH)
			elif r < 0.18:
				id = EARTH_RED
			elif r < 0.3:
				id = EARTH_DARK
			put(x, y, id)
		put(x, top, GRASS)
		if rng.randf() < 0.6:
			put(x, top + 1, GRASS if rng.randf() < 0.5 else LEAF)
		# hanging roots under the rim
		if t > 0.55 and rng.randf() < 0.25:
			for y in range(top + d, top + d + rng.randi_range(1, 3)):
				put(x, y, EARTH_DEEP)
	return surf

## A temple tower: lit left edge, shaded right edge, black window slots, ledges, a broken crown.
func tower(x0: int, base_y: int, tw: int, th: int, broken := true) -> void:
	var top := base_y - th
	for x in range(x0, x0 + tw):
		var col_top := top
		if broken:
			col_top += int(absf(sin(x * 1.7 + rng.randf())) * 4.0) + (3 if rng.randf() < 0.25 else 0)
		for y in range(col_top, base_y + 1):
			var id := STONE
			if x == x0:
				id = STONE_LIT
			elif x == x0 + tw - 1:
				id = STONE_DARK
			put(x, y, id)
	# ledges every ~9 rows
	var y := base_y - 8
	while y > top + 3:
		for x in range(x0 - 1, x0 + tw + 1):
			put(x, y, LEDGE)
		# vines hanging from the ledge
		for x in range(x0 - 1, x0 + tw + 1):
			if rng.randf() < 0.22:
				for k in rng.randi_range(1, 4):
					if get_id(x, y + 1 + k) == 0 or x == x0 - 1 or x == x0 + tw:
						put(x, y + 1 + k, GRASS)
		y -= 9
	# window slots (2 wide, 3 tall) with arched tops
	var wy := base_y - 5
	while wy > top + 4:
		var wx := x0 + 2
		while wx + 1 < x0 + tw - 2:
			rect(wx, wy - 2, wx + 1, wy, HOLE)
			wx += 4
		wy -= 9

func tree(cx: int, ground_y: int, r: int) -> void:
	for y in range(ground_y - r - 1, ground_y):
		put(cx, y, TRUNK)
		if r > 3:
			put(cx + 1, y, TRUNK)
	var cy := ground_y - r - 2
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r - 1, cx + r + 2):
			var dx := (x - cx) / (r + 0.8)
			var dy := (y - cy) / float(r)
			var dd := dx * dx + dy * dy
			if dd < 1.0 - rng.randf() * 0.15:
				var id := LEAF
				if dx + dy < -0.5 and rng.randf() < 0.7:
					id = LEAF_LIT
				elif dx + dy > 0.6 and rng.randf() < 0.6:
					id = GRASS
				put(x, y, id)

func pine(cx: int, ground_y: int, ph: int) -> void:
	put(cx, ground_y - 1, TRUNK)
	for k in ph:
		var y := ground_y - 2 - k
		var half := int((ph - k) * 0.4)
		for x in range(cx - half, cx + half + 1):
			put(x, y, PINE)

## A semicircular stone arch between columns x0 and x1, springing at row y.
func arch(x0: int, x1: int, y: int, thick: int = 2) -> void:
	var cx := (x0 + x1) * 0.5
	var r := (x1 - x0) * 0.5
	for x in range(x0 - thick, x1 + thick + 1):
		var dx := x - cx
		for yy in range(y - int(r) - thick - 1, y + 1):
			var dy := y - yy
			var d := sqrt(dx * dx + dy * dy)
			if d >= r and d < r + thick and dy >= 0:
				put(x, yy, STONE_LIT if dx < 0 else STONE)

# ------------------------------------------------------------------ the four maps
## A mid-size island with a broken temple tower, a round tree and a pine.
func _ruin_island() -> void:
	_init_map(64, 70)
	var surf := island(32, 40, 26, 26)
	tower(24, surf[27] + 1, 9, 30)
	tree(44, surf[44], 5)
	tree(12, surf[12], 3)
	pine(52, surf[52], 9)
	# tumbled blocks on the grass
	put(36, surf[36] - 1, STONE)
	put(37, surf[37] - 1, STONE_LIT)

## The Great Spire's twin: a tall tower on a small island, a crown block wider than the shaft, a tree on top.
func _great_spire() -> void:
	_init_map(48, 110)
	var surf := island(24, 86, 17, 20)
	var base_y: int = surf[24] + 1
	tower(19, base_y, 11, 56, false)
	# wider crown block with windows and a broken parapet
	var ctop := base_y - 72
	for x in range(14, 35):
		for y in range(ctop + int(absf(sin(x * 2.1)) * 3.0), base_y - 55):
			put(x, y, STONE_LIT if x == 14 else (STONE_DARK if x == 34 else STONE))
	for x in range(13, 36):
		put(x, base_y - 55, LEDGE)
	for wx in [16, 21, 26, 31]:
		rect(wx, base_y - 64, wx + 1, base_y - 60, HOLE)
	tree(26, ctop + 1, 5)
	# vines draped over the crown ledge
	for x in range(13, 36):
		if rng.randf() < 0.35:
			for k in rng.randi_range(2, 7):
				put(x, base_y - 54 + k, GRASS)

## Two islands joined by an arched aqueduct with a water channel pouring off the end as a waterfall.
func _aqueduct_isle() -> void:
	_init_map(96, 64)
	var sa := island(18, 30, 15, 18)
	var sb := island(80, 34, 13, 16)
	var deck := 20
	# piers and arches
	for px in [30, 44, 58, 72]:
		rect(px, deck, px + 2, (sa[18] if px < 40 else sb[80]) + 2, STONE)
		put(px, deck, STONE_LIT)
	arch(33, 43, deck + 8)
	arch(47, 57, deck + 8)
	arch(61, 71, deck + 8)
	for x in range(28, 76):
		put(x, deck, LEDGE)
		put(x, deck - 1, STONE)
		put(x, deck - 2, WATER)
	# the channel spills off the far end: a waterfall down past the island's keel
	for y in range(deck - 2, 64):
		put(76, y, WATER)
		if y > deck + 4 and rng.randf() < 0.6:
			put(77, y, WATER)
	tree(12, sa[12], 4)
	pine(84, sb[84], 8)
	tower(6, sa[7] + 1, 5, 12)

## A far keep: crenellated walls and two broken towers on a broad island, trees in the courtyard.
func _far_keep() -> void:
	_init_map(90, 72)
	var surf := island(45, 44, 40, 24)
	var g: int = surf[45] + 1
	tower(14, g, 10, 34)
	tower(66, g, 11, 26)
	# curtain wall with crenellations and a gate arch
	for x in range(24, 66):
		for y in range(g - 14, g + 1):
			put(x, y, STONE)
		if x % 3 != 0:
			put(x, g - 15, STONE_LIT)
	for x in range(40, 50):
		for y in range(g - 8, g + 1):
			put(x, y, HOLE)
	arch(40, 49, g - 8, 2)
	# a collapsed stretch of wall
	for x in range(55, 61):
		for y in range(g - 14, g - 14 + rng.randi_range(4, 9)):
			put(x, y, 0)
	tree(30, g - 14, 4)
	tree(58, g - 12, 3)
	pine(80, surf[80], 9)

# ------------------------------------------------------------------ stand-in render (until WorldTerrain backdrop mode)
## Colour field (per tile, minimap colours of the level's ref_dir) + a smooth 4x mask, for vista_blocks.
func textures(colors: Dictionary) -> Array:
	var col := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var id := fg[y * w + x]
			if id != 0:
				var c: Color = colors.get(id, Color(0.5, 0.5, 0.5))
				if id == HOLE:
					c = Color(0.17, 0.21, 0.3)   # recessed window: dark blue haze, not flat black
				col.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	# dilate colours one tile outward so bilinear edges never pull in black
	var dil := col.duplicate()
	for y in h:
		for x in w:
			if col.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and col.get_pixel(q.x, q.y).a > 0.5:
					var c := col.get_pixel(q.x, q.y)
					dil.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
					break
	var S := 4
	var mask := Image.create(w * S, h * S, false, Image.FORMAT_L8)
	for y in h * S:
		for x in w * S:
			mask.set_pixel(x, y, Color(1, 1, 1) if fg[(y / S) * w + (x / S)] != 0 else Color(0, 0, 0))
	# soften a little: shrink to 2x + regrow = corners rounded by ~half a tile (crisp crenellations survive)
	mask.resize(w * 2, h * 2, Image.INTERPOLATE_BILINEAR)
	mask.resize(w * S, h * S, Image.INTERPOLATE_CUBIC)
	return [dil, mask]

static func load_colors(ref_dir: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(ref_dir.path_join("minimap_colors.json"), FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in data:
			if data[k] is String:
				out[int(k)] = Color.html(data[k])
	return out

# ------------------------------------------------------------------ far floating islands as block maps
## A far floating island painted in FV blocks (so world's terrain renders it with the level's own
## materials): half width hw and keel depth in tiles, an optional ruined tower (tower_h tiles) and a
## waterfall off the front rim. Returns the map; `anchor` = the tile at the island's top centre.
var anchor := Vector2i.ZERO

static func make_island(hw: int, depth: int, tower_h: int, falls: bool, seed_v: int) -> WorldVistaBlocks:
	var m := WorldVistaBlocks.new()
	m.rng.seed = seed_v * 977 + 13
	var top := tower_h + 8
	m._init_map(hw * 2 + 8, top + depth + 12)
	var cx := hw + 4
	var surf := m.island(cx, top, hw, depth)
	m.anchor = Vector2i(cx, top)
	if tower_h > 0:
		var tx := cx - int(hw * 0.3)
		m.tower(tx, surf[tx + 3] + 1, maxi(int(hw * 0.35), 6), tower_h)
		m.tree(cx + int(hw * 0.45), surf[cx + int(hw * 0.45)], 3)
	else:
		for k in maxi(int(hw / 6.0), 2):
			var x := cx + m.rng.randi_range(-int(hw * 0.7), int(hw * 0.7))
			if m.rng.randf() < 0.5:
				m.tree(x, surf[x], m.rng.randi_range(3, 5))
			else:
				m.pine(x, surf[x], m.rng.randi_range(6, 10))
	if falls:
		# a water channel spilling off the rim and falling past the keel
		var fx := cx + int(hw * 0.55)
		for y in range(surf[fx], m.h):
			m.put(fx, y, WATER)
			if y > surf[fx] + 2 and m.rng.randf() < 0.5:
				m.put(fx + 1, y, WATER)
	return m
