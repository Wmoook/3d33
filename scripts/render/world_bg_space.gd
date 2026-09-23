class_name WorldBgSpace
extends RefCounted
## Forgotten Veil backgrounds as SPACES, not colour squares. The EE painting's bg blocks carry intent
## (darker = deeper, brick = hall interior, dirt = earth cave, green = undergrowth), but it dithers them
## per tile with bg 0 and neighbouring ids. This builds per-tile maps that WorldDepth's recessed back walls
## (and anything else behind the gameplay plane) sample instead of the raw per-tile bg colour:
##   class   majority vote of the bg class over a window (dither and bg-0 speckle merge into their region)
##   tone    the region's painted colour, blurred over ~4 tiles (no per-tile colour steps)
##   deep    0..1 recess weight: darker regional tone and deeper inside a region = further back
## Texture layout (RGBA8, one texel per tile): rgb = regional tone (sRGB), a = class * 16 + deep * 15.

enum { C_NONE, C_EARTH, C_FOREST, C_STONE, C_SANDSTONE, C_WATER, C_DEEP }

const CLASS_OF := {
	512: C_EARTH, 507: C_EARTH, 511: C_EARTH, 554: C_EARTH, 584: C_EARTH,
	510: C_FOREST, 505: C_FOREST, 518: C_FOREST, 508: C_FOREST, 506: C_FOREST, 549: C_FOREST, 536: C_FOREST,
	500: C_STONE, 513: C_STONE, 550: C_STONE, 552: C_STONE, 553: C_STONE, 601: C_STONE,
	534: C_SANDSTONE,
	537: C_WATER, 514: C_WATER, 521: C_WATER,
	522: C_DEEP, 523: C_DEEP, 526: C_DEEP, 543: C_DEEP, 544: C_DEEP, 647: C_DEEP,
}
const SKY_IDS := [530, 531, 540, 541, 542]
const VOTE_R := 2          # 5x5 majority window
const TONE_R := 4          # blur radius (tiles) of the regional tone

var W := 0
var H := 0
var cls := PackedByteArray()      # per tile class (air tiles only; solid tiles inherit their neighbours')
var tone := PackedColorArray()    # per tile regional tone (sRGB)
var deep := PackedFloat32Array()  # per tile 0..1

func build(lvl: EELevel, minimap_colors: Dictionary, solid: PackedByteArray) -> void:
	W = lvl.width
	H = lvl.height
	var n := W * H
	var raw := PackedByteArray()
	raw.resize(n)
	var col := PackedColorArray()
	col.resize(n)
	var has := PackedByteArray()
	has.resize(n)
	for i in n:
		var b := lvl.bg[i]
		if b in SKY_IDS:
			continue
		raw[i] = CLASS_OF.get(b, C_DEEP if b == 0 else C_STONE)
		if b != 0 and minimap_colors.has(b):
			col[i] = minimap_colors[b]
			has[i] = 1
	# ---- class: majority vote, bg-0 (C_DEEP from raw) only wins where it really dominates ----
	cls.resize(n)
	for y in H:
		for x in W:
			var i := y * W + x
			if raw[i] == C_NONE:
				continue
			var votes := PackedInt32Array()
			votes.resize(7)
			for dy in range(-VOTE_R, VOTE_R + 1):
				for dx in range(-VOTE_R, VOTE_R + 1):
					var nx := clampi(x + dx, 0, W - 1)
					var ny := clampi(y + dy, 0, H - 1)
					var c := raw[ny * W + nx]
					if c != C_NONE:
						votes[c] += 1 if c == C_DEEP and lvl.bg[ny * W + nx] == 0 else 2
			var best := C_DEEP
			var bv := 0
			for c in range(1, 7):
				if votes[c] > bv:
					bv = votes[c]
					best = c
			cls[i] = best
	# ---- regional tone: separable box blur of the painted colours (weights = has colour) ----
	var acc := PackedColorArray()
	acc.resize(n)
	var wsum := PackedFloat32Array()
	wsum.resize(n)
	for y in H:
		for x in W:
			var c := Color(0, 0, 0, 0)
			var s := 0.0
			for dx in range(-TONE_R, TONE_R + 1):
				var j := y * W + clampi(x + dx, 0, W - 1)
				if has[j]:
					c += col[j]
					s += 1.0
			acc[y * W + x] = c
			wsum[y * W + x] = s
	tone.resize(n)
	deep.resize(n)
	for y in H:
		for x in W:
			var c := Color(0, 0, 0, 0)
			var s := 0.0
			for dy in range(-TONE_R, TONE_R + 1):
				var j := clampi(y + dy, 0, H - 1) * W + x
				c += acc[j]
				s += wsum[j]
			var i := y * W + x
			var t := Color(0.12, 0.1, 0.09) if s < 0.5 else Color(c.r / s, c.g / s, c.b / s)
			# bg-0 share darkens the region (the painter's "deeper here")
			tone[i] = t
			var lum := t.get_luminance()
			var dark := 1.0 - clampf(s / float((2 * TONE_R + 1) * (2 * TONE_R + 1)), 0.0, 1.0)
			deep[i] = clampf(0.55 * (1.0 - smoothstep(0.08, 0.3, lum)) + 0.45 * dark, 0.0, 1.0)

func image() -> Image:
	var buf := PackedByteArray()
	buf.resize(W * H * 4)
	for i in W * H:
		var t := tone[i]
		buf[i * 4] = int(clampf(t.r, 0.0, 1.0) * 255.0)
		buf[i * 4 + 1] = int(clampf(t.g, 0.0, 1.0) * 255.0)
		buf[i * 4 + 2] = int(clampf(t.b, 0.0, 1.0) * 255.0)
		buf[i * 4 + 3] = cls[i] * 16 + int(round(deep[i] * 15.0))
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, buf)

## Recess of a back wall: by class, deeper where darker (room_r range 3..6).
func recess(i: int, base: float) -> float:
	var c := cls[i]
	var k: float = [0.0, 0.8, 1.0, 0.3, 0.2, 0.6, 1.4][c]
	return base + k * deep[i] * 1.6

## Light / occlusion field for interior air (aux texture, RG8): r = distance to the nearest solid tile
## (0..8 tiles), g = distance to the nearest open sky / window tile (0..24): interiors glow near their
## openings and fall into shadow deep inside and in the corners.
var d_solid := PackedFloat32Array()
var d_open := PackedFloat32Array()

func build_light(solid: PackedByteArray, open_mask: PackedByteArray) -> void:
	d_solid = _bfs(solid, 8)
	d_open = _bfs(open_mask, 24)

func _bfs(seed_mask: PackedByteArray, cap: int) -> PackedFloat32Array:
	var n := W * H
	var d := PackedFloat32Array()
	d.resize(n)
	d.fill(float(cap))
	var q := PackedInt32Array()
	for i in n:
		if seed_mask[i]:
			d[i] = 0.0
			q.append(i)
	var qi := 0
	while qi < q.size():
		var i := q[qi]; qi += 1
		var x := i % W
		var y := i / W
		for k in 8:
			var dx: int = [1, -1, 0, 0, 1, 1, -1, -1][k]
			var dy: int = [0, 0, 1, -1, 1, -1, 1, -1][k]
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			var nd := d[i] + (1.0 if k < 4 else 1.414)
			if nd < d[j] and nd < float(cap):
				d[j] = nd
				q.append(j)
	return d

func aux_image() -> Image:
	var buf := PackedByteArray()
	buf.resize(W * H * 2)
	for i in W * H:
		buf[i * 2] = int(clampf(d_solid[i] / 8.0, 0.0, 1.0) * 255.0)
		buf[i * 2 + 1] = int(clampf(d_open[i] / 24.0, 0.0, 1.0) * 255.0)
	return Image.create_from_data(W, H, false, Image.FORMAT_RG8, buf)

## Shared per level: built once from the terrain's level (every module reads the same maps).
static var _cache: WorldBgSpace
static var _cache_level: EELevel
static var _cache_tex: ImageTexture
static var _cache_aux: ImageTexture

static func for_terrain(terrain: WorldTerrain) -> WorldBgSpace:
	if _cache == null or _cache_level != terrain.level:
		_cache = WorldBgSpace.new()
		_cache.build(terrain.level, load_colors(terrain.ref_dir), terrain.solid)
		var open := PackedByteArray()
		open.resize(terrain.W * terrain.H)
		for i in open.size():
			open[i] = 1 if (terrain.sky[i] and not terrain.solid[i]) or (terrain.window.size() == open.size() and terrain.window[i] > 0) else 0
		_cache.build_light(terrain.solid, open)
		_cache_level = terrain.level
		_cache_tex = ImageTexture.create_from_image(_cache.image())
		_cache_aux = ImageTexture.create_from_image(_cache.aux_image())
	return _cache

## Extra light openings (e.g. WorldDepth's room windows): rebuilds the light field + aux texture.
static func add_openings(terrain: WorldTerrain, extra: PackedByteArray) -> void:
	var bs := for_terrain(terrain)
	var open := PackedByteArray()
	open.resize(terrain.W * terrain.H)
	for i in open.size():
		open[i] = 1 if (terrain.sky[i] and not terrain.solid[i]) or (terrain.window.size() == open.size() and terrain.window[i] > 0) or extra[i] > 0 else 0
	bs.build_light(terrain.solid, open)
	_cache_aux.update(bs.aux_image())

## bg_space_aux (RG8): distance to solid / to open sky (see build_light).
static func aux_texture(terrain: WorldTerrain) -> ImageTexture:
	for_terrain(terrain)
	return _cache_aux

## The bg_space_tex texture for shaders (bg_space.gdshaderinc).
static func texture(terrain: WorldTerrain) -> ImageTexture:
	for_terrain(terrain)
	return _cache_tex

static func load_colors(ref_dir: String) -> Dictionary:
	return WorldVistaBlocks.load_colors(ref_dir)
