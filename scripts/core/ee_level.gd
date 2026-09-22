class_name EELevel
extends RefCounted
## Loads an Everybody Edits .eelvl level (compressed-with-header or raw block-data variant).
## Coordinates: tile (x, y), y DOWN, 16 px per tile, exactly as in EE.

const ROTATION_IDS := [375,376,377,378,379,380,438,439,1001,1002,1003,1004,1052,1053,1054,1055,1056,1092,
	275,327,328,273,329,440,338,339,340,276,277,279,280,447,448,449,450,451,452,1041,1042,1043,456,457,458,
	464,465,1075,1076,1077,1078,471,475,476,477,481,482,483,497,492,493,494,499,1502,1500,1506,1507,
	1116,1117,1118,1119,1120,1121,1122,1123,1124,1125,1535,1135,1134,1536,1537,1538,1140,1141,1581,1587,
	1588,1155,1592,1593,1160,1594,1595,1596,1605,1606,1607,1609,1610,1611,1612,1614,1615,1616,1617,1597,
	1101,1102,1103,1104,1105,
	43,213,165,214,113,467,184,185,1619,1079,1080,1620,1011,1012,1027,1028,423,421,418,1517,417,453,461,
	1584,420,419,422,1582,
	1520,83,77,361,1625,1627,1629,1631,1633,1635]
const PORTAL_IDS := [242, 381]

var width := 0
var height := 0
var gravity := 1.0
var background_color := 0
var world_name := ""
var owner := ""
## Layer 0 = foreground/action/decoration, layer 1 = background. Index = y * width + x.
var fg := PackedInt32Array()
var bg := PackedInt32Array()
## Extra per-tile data (layer 0 only): index -> {"rotation": int, "id": int, "target": int, ...}
## Portals: rotation, id, target. Numbered blocks (coin doors etc): "rotation" holds the number.
var extra := {}

var _d: PackedByteArray
var _p := 0

static func load_file(path: String) -> EELevel:
	var lvl := EELevel.new()
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		push_error("EELevel: cannot read " + path)
		return null
	lvl._parse(raw)
	return lvl

func index(x: int, y: int) -> int:
	return y * width + x

func get_fg(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return fg[y * width + x]

func get_bg(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return bg[y * width + x]

func get_extra(x: int, y: int) -> Dictionary:
	return extra.get(y * width + x, {})

## Returns all tile positions (Vector2i) on layer 0 holding the given id.
func find_all(id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in fg.size():
		if fg[i] == id:
			out.append(Vector2i(i % width, i / width))
	return out

func _parse(raw: PackedByteArray) -> void:
	var has_header := true
	# Raw (headerless) files start with a big-endian block id int -> leading 0x00 0x00.
	var inflated := PackedByteArray()
	if not (raw[0] == 0 and raw[1] == 0):
		inflated = raw.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if inflated.is_empty():
		has_header = false
		_d = raw
	else:
		_d = inflated
	_p = 0
	var blocks: Array = []
	if has_header:
		owner = _utf(); world_name = _utf()
		width = _int(); height = _int()
		gravity = _float(); background_color = _uint()
		_utf(); _p += 1; _utf(); _utf(); _int(); _p += 1; _utf()  # desc, campaign, crew id/name/status, minimap, ownerID
	var max_x := 0
	var max_y := 0
	while _p + 8 <= _d.size():
		var t := _int()
		var l := _int()
		var xs := _ushorts()
		var ys := _ushorts()
		var ex := {}
		if t in ROTATION_IDS:
			ex["rotation"] = _int()
		elif t in PORTAL_IDS:
			ex["rotation"] = _int(); ex["id"] = _int(); ex["target"] = _int()
		elif t == 385:
			ex["text"] = _utf(); ex["sign_type"] = _int()
		elif t == 374:
			ex["target_world"] = _utf(); ex["target"] = _int()
		elif t == 1000:
			ex["text"] = _utf(); ex["color"] = _utf(); ex["wrap"] = _int()
		elif (t >= 1550 and t <= 1559) or (t >= 1569 and t <= 1579):
			ex["name"] = _utf(); ex["m1"] = _utf(); ex["m2"] = _utf(); ex["m3"] = _utf()
		for k in xs.size():
			max_x = maxi(max_x, xs[k]); max_y = maxi(max_y, ys[k])
		blocks.append([t, l, xs, ys, ex])
	if not has_header:
		width = max_x + 1
		height = max_y + 1
		world_name = "EX Crew Odyssey"
	fg.resize(width * height); fg.fill(0)
	bg.resize(width * height); bg.fill(0)
	for b in blocks:
		var t: int = b[0]
		var xs: PackedInt32Array = b[2]
		var ys: PackedInt32Array = b[3]
		for k in xs.size():
			if xs[k] >= width or ys[k] >= height:
				continue
			var i: int = ys[k] * width + xs[k]
			if b[1] == 1:
				bg[i] = t
			else:
				fg[i] = t
				if not b[4].is_empty():
					extra[i] = b[4]
	_d = PackedByteArray()

func _int() -> int:
	var v := (_d[_p] << 24) | (_d[_p + 1] << 16) | (_d[_p + 2] << 8) | _d[_p + 3]
	_p += 4
	if v >= 0x80000000:
		v -= 0x100000000
	return v

func _uint() -> int:
	var v := (_d[_p] << 24) | (_d[_p + 1] << 16) | (_d[_p + 2] << 8) | _d[_p + 3]
	_p += 4
	return v

func _float() -> float:
	var b := PackedByteArray([_d[_p + 3], _d[_p + 2], _d[_p + 1], _d[_p]])
	_p += 4
	return b.decode_float(0)

func _utf() -> String:
	var n := (_d[_p] << 8) | _d[_p + 1]
	_p += 2
	var s := _d.slice(_p, _p + n).get_string_from_utf8()
	_p += n
	return s

func _ushorts() -> PackedInt32Array:
	var n := _uint()
	if n > _d.size() - _p:   # corrupt / misdetected data: stop instead of looping forever
		_p = _d.size()
		return PackedInt32Array()
	var out := PackedInt32Array()
	out.resize(n / 2)
	for i in n / 2:
		out[i] = (_d[_p + 2 * i] << 8) | _d[_p + 2 * i + 1]
	_p += n
	return out
