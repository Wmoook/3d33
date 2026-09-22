extends SceneTree
## Route finder: breadth-first search over the REAL EESim with macro-actions (an input held for
## MACRO ticks), deduplicating coarse states. Finds an input sequence from spawn that touches the
## completion block 121, verifies it by replaying from reset, and writes:
##   res://scripts/physics/route_completion.eerp    (EEReplay of the completing run)
##   res://scripts/physics/route_waypoints.json     (ordered tile waypoints + events)
## Run:  $G --headless --path C:/Users/super/ex-odyssey -s res://tests/physics_route.gd
## env ROUTE_MAX_NODES (default 400000), ROUTE_MACRO (default 8)

const ACTIONS := [
	# left, right, up, down, jump
	[0, 0, 0, 0, 0], [1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 1, 0],
	[0, 0, 0, 0, 1], [1, 0, 0, 0, 1], [0, 1, 0, 0, 1],
]

var sim: EESim
var macro := 8
var events: Array = []
var goal_hit := false

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	sim = EESim.new(lvl)
	macro = int(OS.get_environment("ROUTE_MACRO")) if OS.get_environment("ROUTE_MACRO") != "" else 8
	var max_nodes := int(OS.get_environment("ROUTE_MAX_NODES")) if OS.get_environment("ROUTE_MAX_NODES") != "" else 400000
	sim.sim_event.connect(_on_event)
	var inp := EEInput.new()
	# Search: breadth-first, but children that reach a never-seen (tile, coins) are expanded first
	# (novelty-first; exploration reaches the far end of the map orders of magnitude sooner).
	var parent := PackedInt32Array([-1])
	var act := PackedByteArray([0])
	var novel: Array = [[0, sim.snapshot()]]
	var normal: Array = []
	var nh := 0
	var mh := 0
	var seen := {}
	seen[_key()] = true
	var tiles_seen := {}
	var found := -1
	var best_coins := 0
	var seen_portals := {}
	var depth := 0
	var expanded := 0
	while found < 0 and parent.size() < max_nodes:
		var node: Array
		if nh < novel.size():
			node = novel[nh]; novel[nh] = null; nh += 1
		elif mh < normal.size():
			node = normal[mh]; normal[mh] = null; mh += 1
		else:
			break
		expanded += 1
		for a in ACTIONS.size():
			sim.restore(node[1])
			goal_hit = false
			events.clear()
			var ac: Array = ACTIONS[a]
			inp.left = ac[0] == 1; inp.right = ac[1] == 1; inp.up = ac[2] == 1; inp.down = ac[3] == 1
			for t in macro:
				inp.jump = ac[4] == 1
				inp.jump_pressed = ac[4] == 1 and t == 0
				sim.tick(inp)
			for e in events:
				if e[0] == &"portal":
					var k := str(e[1]["from"]) + "->" + str(e[1]["to"])
					if not seen_portals.has(k):
						seen_portals[k] = true
						print("  portal used: ", k, " (nodes ", parent.size(), ")")
			var key := _key()
			if seen.has(key):
				continue
			seen[key] = true
			parent.append(node[0])
			act.append(a)
			var idx := parent.size() - 1
			if sim.coins > best_coins:
				best_coins = sim.coins
				print("  coin collected, pos ", Vector2i(int(sim.px) >> 4, int(sim.py) >> 4), " (nodes ", parent.size(), ")")
			if goal_hit or sim.has_silver_crown:
				found = idx
				break
			var tk := Vector3i((int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4, sim.coins)
			if not tiles_seen.has(tk):
				tiles_seen[tk] = true
				novel.append([idx, sim.snapshot()])
			elif normal.size() - mh < 150000:
				normal.append([idx, sim.snapshot()])
		if expanded % 5000 == 0:
			print("expanded %d  nodes %d  tiles %d  queues %d/%d  %.1fs" % [expanded, parent.size(), tiles_seen.size(), novel.size() - nh, normal.size() - mh, (Time.get_ticks_msec() - t0) / 1000.0])
			if nh > 100000:
				novel = novel.slice(nh); nh = 0
			if mh > 100000:
				normal = normal.slice(mh); mh = 0
	print("search done: nodes=%d expanded=%d found=%s  %.1fs" % [parent.size(), expanded, found >= 0, (Time.get_ticks_msec() - t0) / 1000.0])
	if found < 0:
		_dump_reached(seen)
		print("portals used: ", seen_portals.keys())
		quit(1)
		return
	# reconstruct
	var chain: Array = []
	var n := found
	while n > 0:
		chain.push_front(act[n])
		n = parent[n]
	var rep := EEReplay.new()
	for a in chain:
		var ac: Array = ACTIONS[a]
		for t in macro:
			inp.left = ac[0] == 1; inp.right = ac[1] == 1; inp.up = ac[2] == 1; inp.down = ac[3] == 1
			inp.jump = ac[4] == 1
			inp.jump_pressed = ac[4] == 1 and t == 0
			inp.god_toggle = false
			rep.record(inp)
	# verify from reset and collect waypoints
	events.clear()
	goal_hit = false
	rep.start(sim)
	var pts: Array = []
	var last := Vector2i(-99, -99)
	var ev_log: Array = []
	while rep.step(sim):
		var tp := Vector2i((int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4)
		for e in events:
			if e[0] in [&"portal", &"coin", &"blue_coin", &"complete"] or (e[0] == &"door_state" and e[1]["kind"] == &"coin"):
				ev_log.append({"tick": sim.ticks(), "event": String(e[0]), "data": var_to_str(e[1]), "tile": [tp.x, tp.y]})
				if e[0] == &"portal":
					pts.append({"tick": sim.ticks(), "tile": [e[1]["from"].x, e[1]["from"].y], "note": "portal in"})
					pts.append({"tick": sim.ticks(), "tile": [e[1]["to"].x, e[1]["to"].y], "note": "portal out"})
					last = e[1]["to"]
				else:
					pts.append({"tick": sim.ticks(), "tile": [tp.x, tp.y], "note": String(e[0])})
					last = tp
		events.clear()
		if sim.ticks() % 50 == 0 and (absi(tp.x - last.x) + absi(tp.y - last.y)) >= 6:
			pts.append({"tick": sim.ticks(), "tile": [tp.x, tp.y], "note": ""})
			last = tp
	var ok := sim.has_silver_crown
	print("replay verification: completed=%s ticks=%d (%.1f s game time) coins=%d" % [ok, rep.tick_count(), rep.tick_count() / 100.0, sim.coins])
	for e in ev_log:
		print("  t=%d %s %s @%s" % [e["tick"], e["event"], e["data"], e["tile"]])
	if ok:
		rep.meta = {"level": "ex_crew_odyssey", "kind": "completion", "ticks": rep.tick_count(), "hash": sim.state_hash()}
		rep.save("res://scripts/physics/route_completion.eerp")
		var f := FileAccess.open("res://scripts/physics/route_waypoints.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"level": "ex_crew_odyssey", "spawn": [65, 11], "goal": [54, 9],
			"replay": "res://scripts/physics/route_completion.eerp", "ticks": rep.tick_count(),
			"waypoints": pts, "events": ev_log}, "  "))
		f.close()
		print("wrote route_completion.eerp and route_waypoints.json")
	quit(0 if ok else 1)


func _key() -> String:
	var k := 0
	for c in [&"red", &"green", &"blue"]:
		var tl := sim.key_time_left(c)
		k = k * 3 + (0 if tl <= 0.0 else (1 if tl < 2.5 else 2))
	var al := (1 if fmod(sim.px, 16.0) == 0.0 else 0) + (2 if fmod(sim.py, 16.0) == 0.0 else 0)
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d" % [int(sim.px) >> 3, int(sim.py) >> 3, int(round(sim.speed_x / 3.0)),
		int(round(sim.speed_y / 3.0)), sim.gravity_dir.x * 3 + sim.gravity_dir.y, sim.coins, k,
		(1 if sim.on_ground else 0), al]


func _on_event(kind: StringName, data: Dictionary) -> void:
	events.append([kind, data])
	if kind == &"complete":
		goal_hit = true


func _dump_reached(seen: Dictionary) -> void:
	var tiles := {}
	for k: String in seen:
		var p := k.split(",")
		tiles[Vector2i(int(p[0]) >> 1, int(p[1]) >> 1)] = true
	var img := Image.create(sim.width, sim.height, false, Image.FORMAT_RGB8)
	for y in sim.height:
		for x in sim.width:
			img.set_pixel(x, y, Color(0.35, 0.35, 0.35) if sim.is_tile_solid_now(x, y) else Color(0, 0, 0))
	for t: Vector2i in tiles:
		img.set_pixel(t.x, t.y, Color(0, 1, 0))
	img.save_png("user://route_reached.png")
	var arr := []
	for t: Vector2i in tiles: arr.append([t.x, t.y])
	var jf := FileAccess.open("user://route_reached.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(arr)); jf.close()
	var reg := OS.get_environment("ROUTE_REGION").split(",")
	if reg.size() == 4:
		for y in range(int(reg[1]), int(reg[3]) + 1):
			var line := "%4d " % y
			for x in range(int(reg[0]), int(reg[2]) + 1):
				var v := sim.get_tile(x, y)
				if tiles.has(Vector2i(x, y)): line += "o"
				elif v == 23: line += "R"
				elif v == 6: line += "k"
				elif sim.is_tile_solid_now(x, y): line += "#"
				else: line += "."
			print(line)
	print("reached-tiles map: user://route_reached.png (%d tiles)" % tiles.size())
