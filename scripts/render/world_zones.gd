class_name WorldZones
extends RefCounted
## "Where am I": per-tile named zone map (cheap O(1) lookup) + zone info + the visual atmosphere preset
## each zone uses. Derived from the level: true sky visibility (WorldTerrain.sky) makes the SURFACE,
## hand-authored region rects (shared with the shell) name the caves, and anything left underground falls
## back to the dominant minimap colour around it (fire -> inferno, violet -> corruption, pale -> frozen,
## blue -> lake), else THE UNDERWORLD.

## [name, title, subtitle, mood, visual preset, reverb, Rect2i (tile space, y down)] — first match wins.
const TABLE := [
	[&"lake", "THE DEMON'S LAKE", "Go, and Return!", "lake", WorldPalette.Z_LAKE, 0.7, Rect2i(272, 128, 94, 72)],
	[&"frozen", "FROZEN DEPTHS", "Colder than death", "ice", WorldPalette.Z_ICE, 0.8, Rect2i(258, 108, 142, 92)],
	[&"brimstone", "THE BRIMSTONE HALLS", "Pillars of ember and ash", "fire", WorldPalette.Z_HELL, 0.6, Rect2i(275, 74, 125, 34)],
	[&"inferno", "INFERNO", "Abandon all hope", "fire", WorldPalette.Z_HELL, 0.6, Rect2i(95, 76, 88, 52)],
	[&"corruption", "THE CORRUPTION", "Where the earth rots", "corruption", WorldPalette.Z_CORRUPT, 0.7, Rect2i(180, 72, 66, 56)],
	[&"maelstrom", "THE MAELSTROM", "Winds that never rest", "cave", WorldPalette.Z_TORNADO, 0.5, Rect2i(0, 74, 60, 76)],
	[&"rootworks", "THE ROOTWORKS", "The world's gnarled veins", "cave", WorldPalette.Z_EARTH, 0.5, Rect2i(195, 100, 68, 66)],
	[&"bone_hollows", "THE BONE HOLLOWS", "Remains of those who came before", "cave", WorldPalette.Z_BONES, 0.7, Rect2i(60, 128, 150, 36)],
	[&"drowned_forge", "THE DROWNED FORGE", "Where the lost ships sleep", "cave", WorldPalette.Z_DEEP, 0.7, Rect2i(60, 164, 205, 36)],
	[&"tunnels", "THE DEVIL'S TUNNELS", "The Devil hath taken thy Soul...", "tunnel", WorldPalette.Z_EARTH, 0.4, Rect2i(0, 17, 400, 57)],
	[&"surface", "THE SURFACE", "Where the journey begins", "surface night sky", WorldPalette.Z_SURFACE, 0.05, Rect2i(0, 0, 400, 17)],
	[&"underworld", "THE UNDERWORLD", "Deeper than any map", "cave", WorldPalette.Z_BONES, 0.6, Rect2i()],
]

var W := 0
var H := 0
var tile_zone := PackedByteArray()     # index into TABLE
var visual := PackedByteArray()        # WorldPalette.Z_* preset per tile
var _by_name := {}

func build(terrain: WorldTerrain) -> void:
	W = terrain.W
	H = terrain.H
	tile_zone.resize(W * H)
	visual.resize(W * H)
	for k in TABLE.size():
		_by_name[TABLE[k][0]] = k
	var fallback := TABLE.size() - 1
	var surface: int = _by_name[&"surface"]
	var col := terrain.fgcol_img
	for y in H:
		for x in W:
			var i := y * W + x
			var z := fallback
			if terrain.sky[i]:
				z = surface
			else:
				for k in TABLE.size() - 1:
					var r: Rect2i = TABLE[k][6]
					if r.has_point(Vector2i(x, y)):
						z = k
						break
				if z == fallback:
					z = _by_colour(col.get_pixel(x, y))
			tile_zone[i] = z
			visual[i] = TABLE[z][4]

func _by_colour(c: Color) -> int:
	var h := c.h
	if c.s > 0.35 and (h < 0.13 or h > 0.97) and c.v > 0.6:
		return _by_name[&"inferno"]
	if c.s > 0.3 and h > 0.7 and h < 0.9:
		return _by_name[&"corruption"]
	if c.s < 0.15 and c.v > 0.6:
		return _by_name[&"frozen"]
	if c.s > 0.35 and h > 0.55 and h < 0.7:
		return _by_name[&"lake"]
	return TABLE.size() - 1

func zone_at(tile: Vector2i) -> StringName:
	var x := clampi(tile.x, 0, W - 1)
	var y := clampi(tile.y, 0, H - 1)
	return TABLE[tile_zone[y * W + x]][0]

func info(zone: StringName) -> Dictionary:
	var k: int = _by_name.get(zone, TABLE.size() - 1)
	var e: Array = TABLE[k]
	return {"name": e[0], "title": e[1], "subtitle": e[2], "music_mood": e[3], "reverb": e[5],
		"visual": WorldPalette.ZONE_NAMES[e[4]]}
