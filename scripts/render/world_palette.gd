class_name WorldPalette
extends RefCounted
## Block id -> material class + base colour, and the hand-authored ZONE map of EX Crew Odyssey.
## Everything is in EE tile coordinates (x right, y DOWN).

# --- Material classes (index into the terrain shader's material tables) ---
enum { M_AIR, M_EARTH, M_STONE, M_MARBLE, M_ICE, M_WATER, M_CORRUPT, M_FIRE, M_OBSIDIAN, M_GLASS,
	M_GRASS, M_FOLIAGE, M_FLESH, M_WOOD, M_METAL, M_CLOUD, M_SAND, M_GEM, M_SNOW, M_BONE, M_COUNT }

# --- Atmosphere zones ---
enum { Z_SURFACE, Z_EARTH, Z_HELL, Z_CORRUPT, Z_ICE, Z_LAKE, Z_TORNADO, Z_BONES, Z_DEEP, Z_COUNT }
const ZONE_NAMES := ["surface", "earth", "hell", "corrupt", "ice", "lake", "tornado", "bones", "deep"]

## Priority-ordered zone rectangles (x0, y0, x1, y1), inclusive-exclusive. First match wins.
const ZONE_RECTS := [
	[Z_TORNADO, 0, 75, 46, 150],
	[Z_HELL, 100, 80, 182, 134],
	[Z_CORRUPT, 176, 70, 246, 138],
	[Z_LAKE, 266, 168, 400, 200],
	[Z_ICE, 262, 100, 400, 172],
	[Z_DEEP, 0, 150, 80, 200],
	[Z_BONES, 40, 128, 266, 200],
]

## Special art regions for material overrides.
const RECT_SIGN := Rect2i(0, 22, 82, 48)        # "The Devil hath taken thy Soul..." plaque
const RECT_LOGO := Rect2i(88, 32, 40, 32)        # ΣX CREW logo
const RECT_UPPER_LAKE := Rect2i(196, 38, 60, 26) # blue pond inside the earth layer
const RECT_DEMON := Rect2i(290, 126, 64, 64)     # red demon rising from the water

## Base sRGB colours (roughly the perceived colour of each EE sprite, slightly cleaned up).
const COLORS := {
	9: Color8(112, 112, 116), 10: Color8(52, 84, 176), 11: Color8(142, 52, 160), 12: Color8(176, 52, 82),
	13: Color8(140, 160, 52), 14: Color8(66, 160, 56), 15: Color8(56, 164, 176), 16: Color8(160, 72, 16),
	17: Color8(40, 118, 84), 18: Color8(78, 36, 112), 19: Color8(74, 142, 22), 20: Color8(126, 38, 46),
	21: Color8(122, 102, 42), 22: Color8(186, 130, 28), 29: Color8(196, 198, 204), 30: Color8(236, 118, 52),
	31: Color8(250, 182, 44), 32: Color8(214, 150, 38), 33: Color8(14, 14, 16), 34: Color8(72, 118, 24),
	35: Color8(72, 118, 24), 36: Color8(72, 118, 24), 37: Color8(170, 48, 172), 39: Color8(46, 92, 188),
	40: Color8(184, 64, 44), 42: Color8(104, 104, 108), 44: Color8(6, 6, 8), 45: Color8(110, 88, 60),
	46: Color8(124, 124, 128), 47: Color8(168, 134, 88), 48: Color8(146, 76, 32), 49: Color8(118, 130, 140),
	50: Color8(10, 10, 12), 51: Color8(240, 150, 158), 52: Color8(214, 132, 230), 53: Color8(160, 132, 230),
	54: Color8(126, 150, 232), 55: Color8(140, 210, 232), 62: Color8(220, 40, 60), 87: Color8(180, 182, 186),
}

const BG_COLORS := {
	500: Color8(53, 53, 53), 501: Color8(26, 42, 85), 507: Color8(69, 30, 4), 509: Color8(38, 17, 55),
	511: Color8(56, 18, 21), 512: Color8(56, 46, 18), 513: Color8(60, 60, 60), 514: Color8(32, 54, 95),
	517: Color8(82, 90, 30), 519: Color8(36, 103, 100), 520: Color8(53, 53, 53), 521: Color8(28, 50, 93),
	523: Color8(81, 12, 30), 527: Color8(252, 236, 168), 531: Color8(168, 192, 252), 533: Color8(138, 61, 33),
	534: Color8(106, 96, 65), 535: Color8(134, 110, 37), 538: Color8(61, 64, 73), 542: Color8(41, 50, 53),
	645: Color8(6, 6, 6),
}

## True for STATIC foreground solids baked into the terrain height field (EE ItemId.isSolid, minus the
## dynamic key doors/gates, which WorldDoors renders, and the coin door 43, which actors render).
static func is_world_solid(id: int) -> bool:
	if id < 9 or id > 97:
		return false
	if id >= 23 and id <= 28:
		return false
	if id == 43 or id == 77 or id == 83:
		return false
	return true

## Non-solid decorations the world renders as props.
## Key doors (solid until their key is active) and key gates (the inverse).
static func is_key_door(id: int) -> bool:
	return id == 23 or id == 24 or id == 25 or id == 26 or id == 28

static func is_gate(id: int) -> bool:
	return id == 26 or id == 27 or id == 28

static func key_color_of(id: int) -> StringName:
	match id:
		23, 26: return &"red"
		24, 27: return &"green"
	return &"blue"

static func is_world_deco(id: int) -> bool:
	return id >= 227 and id <= 254 and id != 241 and id != 242 and id != 243

static func zone_at(x: int, y: int) -> int:
	for r in ZONE_RECTS:
		if x >= r[1] and y >= r[2] and x < r[3] and y < r[4]:
			return r[0]
	if y < 21:
		return Z_SURFACE
	if y < 76:
		return Z_EARTH
	return Z_BONES

static func base_color(id: int) -> Color:
	return COLORS.get(id, Color8(128, 128, 128))

## Material class for a solid world id at tile (x, y) inside zone z.
static func material_for(id: int, x: int, y: int, z: int) -> int:
	var p := Vector2i(x, y)
	if RECT_LOGO.has_point(p) and id != 20 and id != 16 and id != 12:
		return M_GEM
	if RECT_SIGN.has_point(p):
		if id == 29 or id == 46 or id == 42 or id == 9:
			return M_MARBLE
		if id == 15 or id == 55 or id == 12 or id == 20 or id == 40:
			return M_GEM if y > 26 and y < 68 and x > 3 and x < 79 else M_EARTH
	if RECT_DEMON.has_point(p) and (id == 12 or id == 20 or id == 40 or id == 51):
		return M_FLESH
	match id:
		10, 39, 15:
			if z == Z_LAKE or RECT_UPPER_LAKE.has_point(p):
				return M_WATER
			if z == Z_ICE:
				return M_ICE
			return M_GEM if id == 15 else M_STONE
		54, 55, 53:
			if z == Z_LAKE:
				return M_WATER
			return M_ICE if z == Z_ICE else M_GLASS
		51:
			return M_GLASS
		29:
			if z == Z_TORNADO:
				return M_CLOUD
			if z == Z_BONES or z == Z_DEEP or z == Z_HELL:
				return M_BONE
			return M_SNOW if z == Z_ICE else M_MARBLE
		42, 46, 9:
			if z == Z_TORNADO:
				return M_CLOUD
			if z == Z_HELL or z == Z_BONES:
				return M_BONE
			if z == Z_ICE:
				return M_SNOW
			return M_STONE
		49:
			return M_STONE
		87:
			return M_METAL
		22:
			return M_WOOD
		50:
			return M_OBSIDIAN
		11, 18, 37, 52:
			return M_CORRUPT
		30, 31, 32:
			return M_FIRE
		44, 33:
			return M_OBSIDIAN
		34, 35, 36:
			return M_GRASS
		14, 19, 13, 17:
			return M_FOLIAGE if y < 22 else M_EARTH
		45, 47, 48:
			return M_WOOD
		21:
			return M_SAND
		62:
			return M_GEM
	return M_EARTH
