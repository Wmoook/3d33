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

## Forgotten Veil (daytime ruins). Same row layout; visual preset is decided per tile (sky -> Z_DAY).
const TABLE_FV := [
	[&"summit_shrine", "THE SUMMIT SHRINE", "The end of every trial", "day sky surface mountain", WorldPalette.Z_DAY, 0.1, Rect2i(385, 70, 15, 16)],
	[&"winners", "THE WINNERS' SCROLL", "Names carved for the ages", "day sky surface", WorldPalette.Z_DAY, 0.1, Rect2i(350, 0, 48, 72)],
	[&"sx_logo", "THE MARK OF THE CREW", "EXPro", "day sky surface", WorldPalette.Z_DAY, 0.1, Rect2i(300, 14, 46, 29)],
	[&"veiled_falls", "THE VEILED FALLS", "Behind the water, a door", "falls waterfall pool", WorldPalette.Z_WATERWAY, 0.5, Rect2i(122, 125, 50, 55)],
	[&"sunken_aqueducts", "THE SUNKEN AQUEDUCTS", "Still water remembers", "channel underground", WorldPalette.Z_WATERWAY, 0.8, Rect2i(140, 165, 260, 35)],
	[&"great_spire", "THE GREAT SPIRE", "It reached for the gods", "temple hall ruin", WorldPalette.Z_RUINS, 0.7, Rect2i(175, 20, 44, 150)],
	[&"hanging_gardens", "THE HANGING GARDENS", "Vines where bridges once stood", "day surface garden", WorldPalette.Z_DAY, 0.2, Rect2i(219, 55, 10, 45)],
	[&"twin_spire", "THE TWIN SPIRE", "Its sister never fell", "temple hall ruin", WorldPalette.Z_RUINS, 0.7, Rect2i(229, 45, 40, 125)],
	[&"ruined_keep", "THE RUINED KEEP", "The last watch was never relieved", "keep day", WorldPalette.Z_RUINS, 0.6, Rect2i(285, 70, 40, 42)],
	[&"great_hall", "THE GREAT HALL", "Where the crew once gathered", "temple hall", WorldPalette.Z_RUINS, 0.7, Rect2i(325, 76, 45, 37)],
	[&"eastern_wood", "THE EASTERN WOOD", "The forest remembers the path", "forest day surface", WorldPalette.Z_DAY, 0.2, Rect2i(370, 86, 30, 26)],
	[&"lower_sanctum", "THE LOWER SANCTUM", "Deeper than the roots go", "temple underground", WorldPalette.Z_RUINS, 0.8, Rect2i(140, 100, 260, 65)],
	[&"elder_grove", "THE ELDER GROVE", "Where the old trees keep watch", "forest day surface", WorldPalette.Z_DAY, 0.1, Rect2i(0, 8, 86, 55)],
	[&"hollow_halls", "THE HOLLOW HALLS", "Stone halls beneath the grove", "hall temple underground", WorldPalette.Z_RUINS, 0.7, Rect2i(0, 60, 112, 50)],
	[&"sunken_west_halls", "THE SUNKEN WEST HALLS", "The roots drink from forgotten water", "corridor underground", WorldPalette.Z_RUINS, 0.8, Rect2i(0, 110, 140, 90)],
	[&"open_sky", "THE FORGOTTEN VEIL", "Where the journey begins", "day sky surface", WorldPalette.Z_DAY, 0.05, Rect2i()],
	[&"underhalls", "THE UNDERHALLS", "Forgotten by all but stone", "corridor underground", WorldPalette.Z_RUINS, 0.7, Rect2i()],
]

var table: Array = TABLE
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
	if not WorldPalette.is_odyssey():
		_build_day(terrain)
		return
	table = TABLE
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

func _build_day(terrain: WorldTerrain) -> void:
	table = TABLE_FV
	for k in table.size():
		_by_name[table[k][0]] = k
	var sky_z: int = _by_name[&"open_sky"]
	var under_z: int = _by_name[&"underhalls"]
	for y in H:
		for x in W:
			var i := y * W + x
			var z := -1
			for k in table.size() - 2:
				if (table[k][6] as Rect2i).has_point(Vector2i(x, y)):
					z = k
					break
			if z < 0:
				z = sky_z if terrain.sky[i] else under_z
			tile_zone[i] = z
			# the look follows the tile itself: open sky is daylight, enclosed stone is the ruins' shade
			visual[i] = WorldPalette.Z_DAY if terrain.sky[i] else WorldPalette.zone_at(x, y)

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
	return table[tile_zone[y * W + x]][0]

func info(zone: StringName) -> Dictionary:
	var k: int = _by_name.get(zone, table.size() - 1)
	var e: Array = table[k]
	return {"name": e[0], "title": e[1], "subtitle": e[2], "music_mood": e[3], "reverb": e[5],
		"visual": WorldPalette.ZONE_NAMES[e[4]]}
