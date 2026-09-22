extends SceneTree
## Topological route (physics-agnostic): shortest 4-connected tile paths through air, with key
## doors counted open (their keys sit next to them) and coin doors closed until the coin is taken,
## chained through portals. Used for the camera flyover waypoints; the physics-verified part of
## the route comes from tests/physics_route.gd.
## Writes res://scripts/physics/route_waypoints.json
## Run: $G --headless --path C:/Users/super/ex-odyssey -s res://tests/physics_route_topo.gd

## [label, from tile, to tile, coin doors open?, teleport-after: tile we arrive at after the portal]
const SEGMENTS := [
	["surface east: red doors (80,9), tree trunks (156,11) and (281,11)", Vector2i(65, 11), Vector2i(394, 20), false],
	["purple tentacle chute down to the cave", Vector2i(394, 20), Vector2i(387, 44), false],
	["upper earth cave west: red-door band, arrow valve shaft, dot bridge, blue pond", Vector2i(387, 44), Vector2i(7, 75), false],
	["portal 53 (7,75) -> hub portal 52 (16,10); hub -> left sky -> portal 60 (52,1)", Vector2i(16, 10), Vector2i(52, 1), false],
	["portal 60 (52,1) -> 61 (321,137); blue keys + blue doors -> gold coin", Vector2i(321, 137), Vector2i(331, 141), false],
	["back to portal 61 (321,137)", Vector2i(331, 141), Vector2i(321, 137), true],
	["portal 61 -> (52,1): left sky -> x=42 elevator -> attic -> 121", Vector2i(52, 1), Vector2i(54, 9), true],
]

var lvl: EELevel
var sim: EESim

func _init() -> void:
	lvl = EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	sim = EESim.new(lvl)
	var pts: Array = []
	var total := 0
	for seg in SEGMENTS:
		var path := _path(seg[1], seg[2], seg[3])
		if path.is_empty():
			print("NO TOPOLOGICAL PATH for: ", seg[0])
			quit(1)
			return
		total += path.size()
		print("%-90s %4d tiles" % [seg[0], path.size()])
		var simp := _simplify(path)
		for i in simp.size():
			var p: Vector2i = simp[i]
			var note := ""
			if i == 0: note = seg[0]
			pts.append({"tile": [p.x, p.y], "note": note})
	print("total path length: %d tiles, %d waypoints" % [total, pts.size()])
	var out := {"level": "ex_crew_odyssey", "units": "tiles (x right, y down); world = (x+0.5, -(y+0.5))",
		"spawn": [65, 11], "goal": [54, 9],
		"kind": "topological designer route (doors open, coin door after the coin); see LEVEL_ROUTE.md",
		"waypoints": pts}
	var f := FileAccess.open("res://scripts/physics/route_waypoints.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote res://scripts/physics/route_waypoints.json")
	quit(0)


func _open(i: int, coin_open: bool) -> bool:
	var v := lvl.fg[i]
	var fl: int = sim._flag(v)
	if fl & EESim.F_SOLID == 0 or fl & EESim.F_JUMPTHRU != 0:
		return true
	if fl & EESim.F_DOOR != 0 and v != 50:
		return coin_open or v != EESim.COINDOOR
	return false


## BFS shortest path (tiles), portals NOT followed (segments are split at portals).
func _path(a: Vector2i, b: Vector2i, coin_open: bool) -> Array:
	var w := lvl.width
	var prev := PackedInt32Array(); prev.resize(w * lvl.height); prev.fill(-2)
	var q := PackedInt32Array([a.y * w + a.x])
	prev[q[0]] = -1
	var head := 0
	var goal := b.y * w + b.x
	while head < q.size():
		var c := q[head]; head += 1
		if c == goal:
			break
		var cx := c % w; var cy := c / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x; var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= lvl.height: continue
			var j := ny * w + nx
			if prev[j] == -2 and _open(j, coin_open):
				prev[j] = c; q.append(j)
	if prev[goal] == -2:
		return []
	var out: Array = []
	var n := goal
	while n != -1:
		out.push_front(Vector2i(n % w, n / w))
		n = prev[n]
	return out


## Keep turning points spaced >= 6 tiles apart (plus both ends): a smooth camera spline input.
func _simplify(path: Array) -> Array:
	var out: Array = [path[0]]
	for i in range(1, path.size() - 1):
		var p: Vector2i = path[i]
		var last: Vector2i = out[-1]
		if absi(p.x - last.x) + absi(p.y - last.y) >= 10:
			out.append(p)
	out.append(path[-1])
	return out
