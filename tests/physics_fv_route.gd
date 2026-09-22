extends SceneTree
## LIGHT topological route survey of Forgotten Veil (no physics search: one BFS over ~80k tiles per
## pass). Air / one-ways / key+switch doors count as passable, coin doors only once enough gold coins
## are reachable (iterated to a fixed point), portals are directed edges (entering a live portal
## teleports; arriving on one lets you walk off it). Prints the portal chain and the doors crossed.
## Run: $G --headless --audio-driver Dummy --path C:/Users/super/ex-odyssey -s res://tests/physics_fv_route.gd
## WRITE=1 also writes res://levels/config/forgotten_veil_route.json (sparse waypoints + notes).

var lvl: EELevel
var sim: EESim
var w := 0
var coin_cap := 0

func _init() -> void:
	lvl = EELevel.load_file("res://levels/forgotten_veil.eelvl")
	sim = EESim.new(lvl)
	w = lvl.width
	var spawn := Vector2i(2, 56)
	var goal: Vector2i = lvl.find_all(121)[0]
	var coins_all := lvl.find_all(100)
	# fixed point: coin doors open as more gold coins become reachable
	var prev := PackedInt32Array()
	while true:
		prev = _bfs(spawn)
		var n := 0
		for c in coins_all:
			if _reached(prev, c): n += 1
		print("coin cap %d -> %d gold coins reachable, goal reachable: %s" % [coin_cap, n, _reached(prev, goal)])
		if n <= coin_cap: break
		coin_cap = n
	var blue := 0
	for c in lvl.find_all(101):
		if _reached(prev, c): blue += 1
	print("blue coins reachable: %d / 8" % blue)
	for id in [113, 409, 6, 8, 5]:
		var r := 0
		var pts := lvl.find_all(id)
		for p in pts:
			if _reached(prev, p): r += 1
		print("id %d reachable %d / %d" % [id, r, pts.size()])
	# greedy tour: nearest reachable gold coin (coin doors open as coins are collected), then 121
	var out: Array = []
	var pos := spawn
	var left := coins_all.duplicate()
	var got := 0
	while true:
		coin_cap = got
		var pv := _bfs(pos)
		var best := -1
		var best_len := 1 << 30
		for k in left.size():
			if _reached(pv, left[k]):
				var pl := _path(pv, left[k]).size()
				if pl < best_len: best_len = pl; best = k
		if best < 0:
			break
		got += 1
		_leg(out, _path(pv, left[best]), "gold coin %d/16" % got)
		pos = left[best]
		left.remove_at(best)
	coin_cap = got
	var pg := _bfs(pos)
	_leg(out, _path(pg, goal), "121 finish")
	print("tour: %d gold coins, %d unreachable, %d path nodes" % [got, left.size(), out.size()])
	if OS.get_environment("WRITE") == "1":
		_write(out, spawn, goal)
	quit(0)


## Appends a path leg with notes for portals, doors, switches, keys and the leg's target.
func _leg(out: Array, path: Array, label: String) -> void:
	var last_door := -1
	for i in range(1 if not out.is_empty() else 0, path.size()):
		var p: Vector2i = path[i]
		var v := lvl.get_fg(p.x, p.y)
		var note := ""
		if i > 0 and absi(p.x - path[i - 1].x) + absi(p.y - path[i - 1].y) > 1:
			var pp: Vector2i = path[i - 1]
			var pr: Vector3i = sim.get_portal(pp.x, pp.y)
			note = "portal %d->%d from (%d,%d)" % [pr.x, pr.y, pp.x, pp.y]
		elif sim._flag(v) & EESim.F_DOOR != 0 and v != last_door:
			note = "door %d #%d" % [v, sim.get_tile_number(p.x, p.y)]
		elif v == EESim.SWITCH_PURPLE:
			note = "purple switch #%d" % sim.get_tile_number(p.x, p.y)
		elif EESim.KEY_COLORS.has(v) and v != 6 and v != 5:
			note = "%s key" % EESim.KEY_COLORS[v]
		elif v == 101:
			note = "blue coin"
		elif v == 77 and last_door != 77:
			note = "piano"
		if i == path.size() - 1:
			note = label + ("; " + note if note != "" else "")
		last_door = v if sim._flag(v) & EESim.F_DOOR != 0 or v == 77 else -1
		if note != "":
			print("  (%d,%d) %s" % [p.x, p.y, note])
		out.append([p, note])


func _reached(prev: PackedInt32Array, p: Vector2i) -> bool:
	var i := p.y * w + p.x
	return prev[i * 2] != -2 or prev[i * 2 + 1] != -2


func _open(i: int) -> bool:
	var v := lvl.fg[i]
	var fl: int = sim._flag(v)
	if fl & EESim.F_SOLID == 0 or fl & EESim.F_JUMPTHRU != 0:
		return true
	if fl & EESim.F_DOOR != 0:
		if v == EESim.COINDOOR: return sim._lookup[i] <= coin_cap
		if v == EESim.BLUECOINDOOR: return sim._lookup[i] <= 8
		return v != 50 and v != 200
	return false


func _live_portal(i: int) -> Variant:
	var p: Variant = sim._portals.get(i, null)
	if p == null or (p as Vector3i).x == (p as Vector3i).y or not sim._portals_by_id.has((p as Vector3i).y):
		return null
	return p


## Node n = tile*2 + arrived (arrived on a portal by teleport: may walk off it).
func _bfs(start: Vector2i) -> PackedInt32Array:
	var prev := PackedInt32Array(); prev.resize(w * lvl.height * 2); prev.fill(-2)
	var s := (start.y * w + start.x) * 2 + 1
	prev[s] = -1
	var q := PackedInt32Array([s])
	var head := 0
	while head < q.size():
		var n := q[head]; head += 1
		var i := n >> 1
		var p: Variant = _live_portal(i)
		if p != null and n & 1 == 0:
			for t: Vector2i in sim._portals_by_id[(p as Vector3i).y]:
				var j := ((t.y >> 4) * w + (t.x >> 4)) * 2 + 1
				if prev[j] == -2:
					prev[j] = n; q.append(j)
			continue
		var cx := i % w; var cy := i / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := cx + d.x; var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= lvl.height: continue
			var k := ny * w + nx
			if not _open(k): continue
			var j := k * 2
			if prev[j] == -2:
				prev[j] = n; q.append(j)
	return prev


func _path(prev: PackedInt32Array, goal: Vector2i) -> Array:
	var gi := goal.y * w + goal.x
	var n := gi * 2 if prev[gi * 2] != -2 else gi * 2 + 1
	if prev[n] == -2: return []
	var out: Array = []
	while n != -1:
		out.push_front(Vector2i((n >> 1) % w, (n >> 1) / w))
		n = prev[n]
	return out


func _write(path: Array, spawn: Vector2i, goal: Vector2i) -> void:
	var pts: Array = []
	var last := Vector2i(-99, -99)
	for k in path.size():
		var p: Vector2i = path[k][0]
		var note: String = path[k][1]
		if note != "" or k == 0 or k == path.size() - 1 or absi(p.x - last.x) + absi(p.y - last.y) >= 10:
			pts.append({"tile": [p.x, p.y], "note": note})
			last = p
	var doc := {"level": "forgotten_veil", "units": "tiles (x right, y down); world = (x+0.5, -(y+0.5))",
		"spawn": [spawn.x, spawn.y], "goal": [goal.x, goal.y],
		"kind": "topological (gravity ignored, key/switch doors assumed open, coin doors gated by coins collected): greedy tour of all 16 gold coins, then 121 behind coin door 16 (349,109); see scripts/physics/LEVEL_ROUTE_FV.md",
		"waypoints": pts}
	var f := FileAccess.open("res://levels/config/forgotten_veil_route.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("wrote res://levels/config/forgotten_veil_route.json (%d waypoints)" % pts.size())
