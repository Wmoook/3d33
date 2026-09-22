class_name FxOverlayMaps
extends RefCounted
## Analyses the canonical EE minimap (assets/ee_ref/minimap_ee.png, 1 px per tile) plus the level grid to
## find where hero FX belong: painted fire, water bodies and their surfaces, splash streams, ice glints.
## All coordinates are EE tiles (y down).

const MINIMAP := "res://assets/ee_ref/minimap_ee.png"
const FIRE_Y := Color8(240, 169, 39)
const FIRE_O := Color8(223, 122, 65)
const WATER := [Color8(77, 132, 198), Color8(53, 82, 168), Color8(45, 68, 156), Color8(126, 153, 246),
	Color8(149, 220, 246), Color8(123, 167, 199)]
const CHUNK := 12

var W := 0
var H := 0
var img: Image
## RGBA8 mask for the overlay field shader: R = fire (1 yellow, .6 orange), G = caustic weight,
## B = ice glint weight, A = splash/stream.
var mask: Image
var fire := PackedByteArray()      # 0 none, 1 orange, 2 yellow
var water := PackedByteArray()     # 1 = still water body tile
var stream := PackedByteArray()    # 1 = splash / falling-water streak tile
var fire_tops: Array[Vector2i] = []            # fire tiles with open air above (flame tongues)
var fire_chunks: Array = []                    # [{center: Vector2, count, tiles: Array[Vector2i], min, max}]
var water_surface: Array[Vector2i] = []        # water tiles with open air above
var stream_tiles: Array[Vector2i] = []

func build(lvl: EELevel) -> void:
	W = lvl.width
	H = lvl.height
	var tex := load(MINIMAP) as Texture2D
	img = tex.get_image() if tex else Image.create(W, H, false, Image.FORMAT_RGB8)
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	fire.resize(W * H); water.resize(W * H); stream.resize(W * H)
	for y in H:
		for x in W:
			var c := img.get_pixel(x, y)
			var i := y * W + x
			if _same(c, FIRE_Y):
				fire[i] = 2
			elif _same(c, FIRE_O):
				fire[i] = 1
			elif _is_water(c):
				_classify_water(x, y, i)
	_find_fire(lvl)
	_find_water(lvl)
	_make_mask(lvl)

func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func _is_water(c: Color) -> bool:
	for w in WATER:
		if _same(c, w):
			return true
	return false

## Blue minimap pixels are water only inside the lakes; the logo/sign text and icicle tips are not.
func _classify_water(x: int, y: int, i: int) -> void:
	var p := Vector2i(x, y)
	if WorldPalette.RECT_UPPER_LAKE.has_point(p):
		water[i] = 1
		return
	var z := WorldPalette.zone_at(x, y)
	if z == WorldPalette.Z_LAKE:
		water[i] = 1
	elif z == WorldPalette.Z_ICE and x < 306 and y > 132:
		stream[i] = 1   # the demon's rising splash sheets
	elif y > 185 and x > 180 and x < 200:
		water[i] = 1    # little pool under the ship's wheel

static func is_open(lvl: EELevel, x: int, y: int) -> bool:
	var id := lvl.get_fg(x, y)
	if id < 0:
		return false
	if (id >= 23 and id <= 28) or id == 43:
		return false
	return not WorldPalette.is_world_solid(id)

func _find_fire(lvl: EELevel) -> void:
	var bins := {}
	for y in H:
		for x in W:
			var i := y * W + x
			if fire[i] == 0:
				continue
			if y > 0 and fire[i - W] == 0 and is_open(lvl, x, y - 1):
				fire_tops.append(Vector2i(x, y))
			var key := Vector2i(x / CHUNK, y / CHUNK)
			if not bins.has(key):
				bins[key] = {"tiles": [] as Array[Vector2i], "sum": Vector2.ZERO}
			bins[key].tiles.append(Vector2i(x, y))
			bins[key].sum += Vector2(x + 0.5, y + 0.5)
	for key in bins:
		var b: Dictionary = bins[key]
		var n: int = b.tiles.size()
		if n < 3:
			continue
		var mn := Vector2i(9999, 9999)
		var mx := Vector2i(-1, -1)
		for t: Vector2i in b.tiles:
			mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
			mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
		fire_chunks.append({"center": b.sum / n, "count": n, "tiles": b.tiles, "min": mn, "max": mx})

func _find_water(lvl: EELevel) -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			if water[i] == 1 and y > 0 and water[i - W] == 0 and stream[i - W] == 0 and is_open(lvl, x, y - 1):
				water_surface.append(Vector2i(x, y))
			if stream[i] == 1:
				stream_tiles.append(Vector2i(x, y))

func _make_mask(lvl: EELevel) -> void:
	mask = Image.create(W, H, false, Image.FORMAT_RGBA8)
	# caustic weight: water tiles + solid walls within 6 tiles (Chebyshev) of water, falling off
	var caus := PackedFloat32Array()
	caus.resize(W * H)
	var R := 4
	for y in H:
		for x in W:
			if water[y * W + x] == 0:
				continue
			for dy in range(-R, 2):
				for dx in range(-R, R + 1):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					var d := maxf(absf(dx), absf(dy))
					var w := 1.0 - d / (R + 1.0)
					if water[j] == 1:
						w = 1.0
					if w > caus[j]:
						caus[j] = w
	for y in H:
		for x in W:
			var i := y * W + x
			var r := 0.0
			if fire[i] == 2:
				r = 1.0
			elif fire[i] == 1:
				r = 0.6
			var g := caus[i] if not is_open(lvl, x, y) else 0.0
			var b := 0.0
			if WorldPalette.zone_at(x, y) == WorldPalette.Z_ICE and not is_open(lvl, x, y):
				var c := img.get_pixel(x, y)
				var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
				b = clampf((lum - 0.45) * 3.0, 0.0, 1.0)
				if _is_water(c) and stream[i] == 0:
					b = 1.0   # icicle tips glint hardest
			var a := 1.0 if stream[i] == 1 else 0.0
			mask.set_pixel(x, y, Color(r, g, b, a))
