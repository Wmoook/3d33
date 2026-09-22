class_name Zones
## Named areas of EX Crew Odyssey in TILE space (y down), read off assets/ee_ref/level_preview_*.png.
## First match wins, so small/specific regions come before the broad bands.
## bed = music/ambience bed in assets/audio/music, reverb = SFX room size (0..1).

const LIST := [
	{"name": "THE DEMON'S LAKE", "sub": "Go, and Return!", "rect": Rect2i(272, 128, 94, 72), "bed": &"lake", "reverb": 0.9},
	{"name": "FROZEN DEPTHS", "sub": "Colder than death", "rect": Rect2i(258, 108, 142, 92), "bed": &"ice", "reverb": 0.85},
	{"name": "THE BRIMSTONE HALLS", "sub": "Pillars of ember and ash", "rect": Rect2i(275, 74, 125, 34), "bed": &"hell", "reverb": 0.6},
	{"name": "INFERNO", "sub": "Abandon all hope", "rect": Rect2i(95, 76, 88, 52), "bed": &"hell", "reverb": 0.7},
	{"name": "THE CORRUPTION", "sub": "Where the earth rots", "rect": Rect2i(180, 72, 66, 56), "bed": &"corruption", "reverb": 0.8},
	{"name": "THE MAELSTROM", "sub": "Winds that never rest", "rect": Rect2i(0, 74, 60, 76), "bed": &"cave", "reverb": 0.5},
	{"name": "THE ROOTWORKS", "sub": "The world's gnarled veins", "rect": Rect2i(195, 100, 68, 66), "bed": &"cave", "reverb": 0.65},
	{"name": "THE BONE HOLLOWS", "sub": "Remains of those who came before", "rect": Rect2i(60, 128, 150, 36), "bed": &"cave", "reverb": 0.7},
	{"name": "THE DROWNED FORGE", "sub": "Where the lost ships sleep", "rect": Rect2i(60, 164, 205, 36), "bed": &"cave", "reverb": 0.75},
	{"name": "THE DEVIL'S TUNNELS", "sub": "The Devil hath taken thy Soul...", "rect": Rect2i(0, 17, 400, 57), "bed": &"cave", "reverb": 0.6},
	{"name": "THE SURFACE", "sub": "Where the journey begins", "rect": Rect2i(0, 0, 400, 17), "bed": &"surface", "reverb": 0.15},
]
const DEFAULT := {"name": "THE UNDERWORLD", "sub": "", "rect": Rect2i(0, 0, 400, 200), "bed": &"cave", "reverb": 0.6}

## Returns the zone index for a tile, or -1 for DEFAULT.
static func index_at(tile: Vector2i) -> int:
	for i in LIST.size():
		if (LIST[i]["rect"] as Rect2i).has_point(tile):
			return i
	return -1

static func get_zone(i: int) -> Dictionary:
	return LIST[i] if i >= 0 and i < LIST.size() else DEFAULT
