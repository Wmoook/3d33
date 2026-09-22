class_name FxLightMap
extends RefCounted
## Where is it bright / shaded / dark? Per-tile light class for placing ambient life on non-Odyssey levels.
## Uses WorldView's own masks when available (terrain.sky: sky-connected open air, zones.visual: per-tile
## atmosphere preset) so FX agree with the world's backdrops; otherwise falls back to column sky visibility.
##   SUN   = sky-connected open air (birds, butterflies, leaves, dust motes)
##   SHADE = roofed air near daylight (fireflies)
##   DARK  = enclosed air at least DARK_R tiles from any sunlit tile (bats)

enum { SUN, SHADE, DARK }
const DARK_R := 6

var W := 0
var H := 0
var cls := PackedByteArray()

func build(lvl: EELevel, world: Node) -> void:
	W = lvl.width
	H = lvl.height
	cls.resize(W * H)
	var sky := PackedByteArray()
	var terrain = world.get("terrain") if world != null else null
	if terrain != null and (terrain.get("sky") as PackedByteArray).size() == W * H:
		sky = terrain.sky
	else:
		sky.resize(W * H)
		for x in W:
			for y in range(1, H):
				if not FxOverlayMaps.is_open(lvl, x, y):
					break
				sky[y * W + x] = 1
	# distance (Chebyshev, capped) to the nearest sunlit tile: two separable passes of a running min
	var d := PackedInt32Array()
	d.resize(W * H)
	for i in W * H:
		d[i] = 0 if sky[i] == 1 else 99
	for y in H:
		for x in range(1, W):
			d[y * W + x] = mini(d[y * W + x], d[y * W + x - 1] + 1)
		for x in range(W - 2, -1, -1):
			d[y * W + x] = mini(d[y * W + x], d[y * W + x + 1] + 1)
	for x in W:
		for y in range(1, H):
			d[y * W + x] = mini(d[y * W + x], d[(y - 1) * W + x] + 1)
		for y in range(H - 2, -1, -1):
			d[y * W + x] = mini(d[y * W + x], d[(y + 1) * W + x] + 1)
	for i in W * H:
		cls[i] = SUN if sky[i] == 1 else (DARK if d[i] >= DARK_R else SHADE)

func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return SUN
	return cls[y * W + x]
