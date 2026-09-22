extends SceneTree
## Route finder for EX Crew Odyssey on the REAL EESim.
## The route is split into legs (goal predicates). Each leg runs a best-first search over macro
## actions (an input held for MACRO ticks), ordered by a tile-level geodesic distance field to the
## leg's target (computed through air/doors and portal links), with coarse state deduplication.
## The winning input sequences are concatenated into one EEReplay, re-verified from sim.reset(),
## and written to:
##   res://scripts/physics/route_completion.eerp   (EEReplay of a full completion run)
##   res://scripts/physics/route_waypoints.json    (ordered waypoint tiles + events, for the shell)
## Run:  $G --headless --path C:/Users/super/ex-odyssey -s res://tests/physics_route.gd
## (takes a few minutes). env ROUTE_LEG_NODES = node budget per leg (default 400000).

const ACTIONS := [
	# left, right, up, down, jump
	[0, 0, 0, 0, 0], [1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 1, 0],
	[0, 0, 0, 0, 1], [1, 0, 0, 0, 1], [0, 1, 0, 0, 1],
]
const ACTION_NAMES := ["-", "L", "R", "U", "D", "J", "LJ", "RJ"]

## Legs: [name, heuristic target tile, predicate, predicate arg, macro ticks, state-key resolution]
const LEGS := [
	["spawn -> red doors -> east surface -> top of the purple tentacle (394,24)", Vector2i(394, 24), "tile", Vector2i(394, 24), 8, "coarse"],
	["down the tentacle chute (jump DOWN through the up-arrows) -> cave (387,44)", Vector2i(387, 44), "tile", Vector2i(387, 44), 2, "fine"],
	["cave -> west through the red-door band (296-303, 36-44) behind the right-arrow wall", Vector2i(293, 45), "tile", Vector2i(293, 45), 4, "medium"],
	["underground -> portal 53 (7,75) -> hub (16,10)", Vector2i(7, 75), "portal_to", Vector2i(16, 10), 8, "coarse"],
	["hub -> left sky -> portal 60 (52,1) -> (321,137)", Vector2i(52, 1), "portal_to", Vector2i(321, 137), 8, "coarse"],
	["blue keys -> blue door pocket -> gold coin (331,141)", Vector2i(331, 141), "coins", 1, 4, "coarse"],
	["portal 61 (321,137) -> (52,1) -> attic -> 121 (54,9)", Vector2i(321, 137), "complete", 0, 8, "coarse"],
]

var sim: EESim
var lvl: EELevel
var events: Array = []
var _open := PackedByteArray()

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	lvl = EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	sim = EESim.new(lvl)
	sim.sim_event.connect(_on_event)
	var budget := int(OS.get_environment("ROUTE_LEG_NODES")) if OS.get_environment("ROUTE_LEG_NODES") != "" else 400000
	# ROUTE_LOCAL="sx,sy,gx,gy,macro,mode": debug a single leg from a tile position to a goal tile
	if OS.get_environment("ROUTE_LOCAL") != "":
		var a := OS.get_environment("ROUTE_LOCAL").split(",")
		sim.px = int(a[0]) * 16.0; sim.py = int(a[1]) * 16.0
		sim.prev_px = sim.px; sim.prev_py = sim.py
		var g := Vector2i(int(a[2]), int(a[3]))
		var leg := ["local", g, "tile", g, int(a[4]), a[5]]
		_build_open(false)
		var r := _search(sim.snapshot(), leg, _distance_field([g]), PackedInt32Array(), budget)
		if r.is_empty():
			print("LOCAL: unreachable")
		else:
			print("LOCAL: reached in %d macros: %s" % [r[0].size(), str(r[0].map(func(x): return ACTION_NAMES[x]))])
		_cleanup()
		quit()
		return
	# ROUTE_EXPLORE=1: exhaustive coarse exploration from spawn (no goal); dumps reached cells
	if OS.get_environment("ROUTE_EXPLORE") == "1":
		_build_open(false)
		var leg := ["explore", Vector2i(0, 0), "never", 0, 8, "coarse"]
		_search(sim.snapshot(), leg, _distance_field([Vector2i(0, 0)]), PackedInt32Array(), budget)
		print("portals used: ", portals_used.keys())
		_cleanup()
		quit()
		return
	var all_actions: Array = []    # [action, macro] pairs
	var first_leg := 0
	# ROUTE_RESUME=1: continue after the last leg that succeeded in a previous run
	if OS.get_environment("ROUTE_RESUME") == "1" and FileAccess.file_exists("user://route_partial.json"):
		var pj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://route_partial.json"))
		first_leg = int(pj["next_leg"])
		var inp0 := EEInput.new()
		for pr in pj["actions"]:
			all_actions.append([int(pr[0]), int(pr[1])])
			_apply(ACTIONS[int(pr[0])], int(pr[1]), inp0)
		print("resumed at leg %d after %d macros, pos %s" % [first_leg, all_actions.size(), Vector2i((int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4)])
	var snap := sim.snapshot()
	for li in range(first_leg, LEGS.size()):
		var leg: Array = LEGS[li]
		var lt := Time.get_ticks_msec()
		print("LEG: ", leg[0])
		var target: Vector2i = leg[1]
		# coin doors (43) stay closed in the heuristic until the coin is collected
		_build_open(leg[2] == "complete")
		var dist := _distance_field([target])
		# last leg: once back in the top-left zone (after portal 61), aim for 121 instead
		var dist2 := _distance_field([Vector2i(54, 9)]) if leg[2] == "complete" else PackedInt32Array()
		var res := _search(snap, leg, dist, dist2, budget)
		if res.is_empty():
			print("  LEG FAILED after %.1fs" % [(Time.get_ticks_msec() - lt) / 1000.0])
			_cleanup()
			quit(1)
			return
		# verify: replaying the chain from the leg start must land on the goal state
		sim.restore(snap)
		events.clear()
		var vi := EEInput.new()
		var goal_seen := false
		for a in res[0]:
			_apply(ACTIONS[a], leg[4], vi)
		sim.restore(res[1])
		var want := Vector2(sim.px, sim.py)
		sim.restore(snap)
		for a in res[0]:
			_apply(ACTIONS[a], leg[4], vi)
		print("  chain check: replay end (%.1f,%.1f) vs search end (%.1f,%.1f)" % [sim.px, sim.py, want.x, want.y])
		snap = res[1]
		for a in res[0]:
			all_actions.append([a, leg[4]])
		print("  leg done: %d macros, %.1fs" % [res[0].size(), (Time.get_ticks_msec() - lt) / 1000.0])
		var pf := FileAccess.open("user://route_partial.json", FileAccess.WRITE)
		pf.store_string(JSON.stringify({"next_leg": li + 1, "actions": all_actions})); pf.close()
	_write_outputs(all_actions)
	print("total %.1fs" % [(Time.get_ticks_msec() - t0) / 1000.0])
	_cleanup()
	quit(0)


func _on_event(kind: StringName, data: Dictionary) -> void:
	events.append([kind, data])


func _cleanup() -> void:
	if sim.sim_event.is_connected(_on_event):
		sim.sim_event.disconnect(_on_event)


# ---------------------------------------------------------------- search

func _apply(ac: Array, macro: int, inp: EEInput) -> void:
	inp.left = ac[0] == 1; inp.right = ac[1] == 1; inp.up = ac[2] == 1; inp.down = ac[3] == 1
	for t in macro:
		inp.jump = ac[4] == 1
		inp.jump_pressed = ac[4] == 1 and t == 0
		sim.tick(inp)


func _goal(leg: Array) -> bool:
	match leg[2]:
		"portal_to":
			for e in events:
				if e[0] == &"portal" and e[1]["to"] == leg[3]:
					return true
		"coins":
			return sim.coins >= int(leg[3])
		"tile":
			var t: Vector2i = leg[3]
			return absi(((int(sim.px) + 8) >> 4) - t.x) <= 1 and ((int(sim.py) + 8) >> 4) == t.y
		"complete":
			return sim.has_silver_crown
	return false


func _h(dist: PackedInt32Array, dist2: PackedInt32Array) -> int:
	var tx := (int(sim.px) + 8) >> 4
	var ty := (int(sim.py) + 8) >> 4
	var i := ty * sim.width + tx
	if not dist2.is_empty() and tx < 100 and ty < 20:
		return dist2[i] if dist2[i] >= 0 else 100000
	var d := dist[i]
	return d if d >= 0 else 100000


var _fine := false
var _medium := false
var reached_cells := {}
var portals_used := {}

func _key() -> int:
	if _fine:
		return hash([int(sim.px * 2.0), int(sim.py * 2.0), int(round(sim.speed_x * 4.0)), int(round(sim.speed_y * 4.0)),
			sim.gravity_dir, sim.current_tile, sim.coins, sim.is_key_active(&"blue"), sim.is_key_active(&"red")])
	if _medium:
		var tl := sim.key_time_left(&"red")
		return hash([int(sim.px) >> 2, int(sim.py) >> 2, int(round(sim.speed_x)), int(round(sim.speed_y)),
			sim.gravity_dir, sim.current_tile, sim.coins, int(ceil(tl)), sim.is_key_active(&"blue"), sim.on_ground])
	var k := 0
	for c in [&"red", &"blue"]:
		var tl := sim.key_time_left(c)
		k = k * 3 + (0 if tl <= 0.0 else (1 if tl < 2.5 else 2))
	var al := (1 if fmod(sim.px, 16.0) == 0.0 else 0) + (2 if fmod(sim.py, 16.0) == 0.0 else 0)
	return hash([int(sim.px) >> 3, int(sim.py) >> 3, int(round(sim.speed_x / 3.0)), int(round(sim.speed_y / 3.0)),
		sim.gravity_dir, sim.coins, k, sim.on_ground, al])


## Best-first (bucket queue on the geodesic distance). Returns [actions, end snapshot] or [].
func _search(start: Array, leg: Array, dist: PackedInt32Array, dist2: PackedInt32Array, budget: int) -> Array:
	var macro: int = leg[4]
	_fine = leg[5] == "fine"
	_medium = leg[5] == "medium"
	var inp := EEInput.new()
	var parent := PackedInt32Array([-1])
	var act := PackedByteArray([0])
	var buckets := {}          # h -> Array of [idx, snapshot]
	var heads := {}
	var hs: Array = []         # sorted non-empty bucket keys
	var seen := {}
	var tiles_seen := {}
	sim.restore(start)
	seen[_key()] = true
	var h0 := _h(dist, dist2)
	buckets[h0] = [[0, start]]; heads[h0] = 0; hs.append(h0)
	var queued := 1
	var best_h := h0
	var expanded := 0
	while not hs.is_empty() and parent.size() < budget:
		var hb: int = hs[0]
		var arr: Array = buckets[hb]
		var node: Array = arr[heads[hb]]
		arr[heads[hb]] = null
		heads[hb] += 1
		queued -= 1
		if heads[hb] >= arr.size():
			buckets.erase(hb); heads.erase(hb); hs.pop_front()
		expanded += 1
		for a in ACTIONS.size():
			sim.restore(node[1])
			events.clear()
			_apply(ACTIONS[a], macro, inp)
			if sim.is_dead:
				continue
			for e in events:
				if e[0] == &"portal":
					var pk := "%s->%s" % [e[1]["from"], e[1]["to"]]
					if not portals_used.has(pk):
						portals_used[pk] = true
						print("  portal used: ", pk, " (expanded ", expanded, ")")
				elif e[0] == &"coin":
					print("  COIN collected (expanded ", expanded, ")")
			var key := _key()
			if seen.has(key):
				continue
			seen[key] = true
			parent.append(node[0])
			act.append(a)
			var idx := parent.size() - 1
			if _goal(leg):
				var chain: Array = []
				var n := idx
				while n > 0:
					chain.push_front(act[n])
					n = parent[n]
				print("  goal reached: expanded %d, nodes %d" % [expanded, parent.size()])
				return [chain, sim.snapshot()]
			var h := _h(dist, dist2)
			if h < best_h:
				best_h = h
			if leg[5] == "coarse":
				h = 0     # FIFO (breadth-first) order; only novelty is prioritised
			# novelty first: a node that reaches a never-seen (tile, key state) is expanded before
			# any revisit; within each class, closest-to-target first
			var tk := hash([(int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4, sim.coins, sim.is_key_active(&"blue")])
			reached_cells[[(int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4]] = true
			if tiles_seen.has(tk):
				h += 1000000
			else:
				tiles_seen[tk] = true
			if queued > 250000:
				continue      # memory guard
			if not buckets.has(h):
				buckets[h] = []; heads[h] = 0
				hs.insert(hs.bsearch(h), h)
			buckets[h].append([idx, sim.snapshot()])
			queued += 1
		if expanded % 5000 == 0:
			sim.restore(node[1])
			print("    expanded %d nodes %d queued %d  best h %d  current h %d at %s" % [expanded, parent.size(), queued, best_h, hb,
				Vector2i((int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4)])
	print("  search exhausted: expanded %d, %d distinct (tile,coin,bluekey) cells" % [expanded, tiles_seen.size()])
	var cells := []
	for c: Array in reached_cells: cells.append(c)
	var jf := FileAccess.open("user://route_reached.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(cells)); jf.close()
	return []


# ---------------------------------------------------------------- geodesic heuristic

func _build_open(coin_doors_open: bool) -> void:
	var n := lvl.width * lvl.height
	_open.resize(n)
	for i in n:
		var v := lvl.fg[i]
		var fl: int = sim._flag(v)
		var door_ok := fl & EESim.F_DOOR != 0 and v != 50 and (coin_doors_open or v != EESim.COINDOOR)
		_open[i] = 1 if (fl & EESim.F_SOLID == 0 or door_ok or fl & EESim.F_JUMPTHRU != 0) else 0


## Tile BFS distance to the targets through open tiles (doors counted open), including portal
## links: a portal P (id -> target t) is as close as the portals whose id == t.
func _distance_field(targets: Array) -> PackedInt32Array:
	var w := lvl.width
	var dist := PackedInt32Array(); dist.resize(w * lvl.height); dist.fill(-1)
	var into := {}   # portal id -> indices of portals whose target == id
	for id in [242, 381]:
		for p in lvl.find_all(id):
			var e := lvl.get_extra(p.x, p.y)
			if int(e["target"]) == int(e["id"]): continue
			var t := int(e["target"])
			if not into.has(t): into[t] = []
			into[t].append(p.y * w + p.x)
	var q := PackedInt32Array()
	for t: Vector2i in targets:
		var i := t.y * w + t.x
		dist[i] = 0; q.append(i)
	var head := 0
	while head < q.size():
		var c := q[head]; head += 1
		var cx := c % w; var cy := c / w
		var nd := dist[c] + 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x; var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= lvl.height: continue
			var j := ny * w + nx
			if _open[j] == 1 and dist[j] < 0:
				dist[j] = nd; q.append(j)
		var v := lvl.fg[c]
		if v == 242 or v == 381:
			var id := int(lvl.get_extra(cx, cy)["id"])
			for j: int in into.get(id, []):
				if dist[j] < 0:
					dist[j] = nd; q.append(j)
	return dist


# ---------------------------------------------------------------- outputs

func _write_outputs(all_actions: Array) -> void:
	var inp := EEInput.new()
	var rep := EEReplay.new()
	for pair in all_actions:
		var ac: Array = ACTIONS[pair[0]]
		for t in int(pair[1]):
			inp.left = ac[0] == 1; inp.right = ac[1] == 1; inp.up = ac[2] == 1; inp.down = ac[3] == 1
			inp.jump = ac[4] == 1
			inp.jump_pressed = ac[4] == 1 and t == 0
			inp.god_toggle = false
			rep.record(inp)
	# verify from reset, collecting waypoints
	events.clear()
	rep.start(sim)
	var pts: Array = [{"tick": 0, "tile": [65, 11], "note": "spawn"}]
	var last := Vector2i(65, 11)
	var ev_log: Array = []
	while rep.step(sim):
		var tp := Vector2i((int(sim.px) + 8) >> 4, (int(sim.py) + 8) >> 4)
		for e in events:
			var k: StringName = e[0]
			if k == &"portal" or k == &"coin" or k == &"blue_coin" or k == &"complete" \
					or (k == &"door_state" and (e[1]["kind"] == &"coin" or e[1]["kind"] == &"blue")):
				var d: Dictionary = e[1]
				var entry := {"tick": sim.ticks(), "event": String(k), "tile": [tp.x, tp.y]}
				if k == &"portal":
					entry["from"] = [d["from"].x, d["from"].y]; entry["to"] = [d["to"].x, d["to"].y]
					pts.append({"tick": sim.ticks(), "tile": entry["from"], "note": "portal in"})
					pts.append({"tick": sim.ticks(), "tile": entry["to"], "note": "portal out"})
					last = d["to"]
				else:
					if d.has("kind"):
						entry["kind"] = String(d["kind"]); entry["open"] = d["open"]
					pts.append({"tick": sim.ticks(), "tile": [tp.x, tp.y], "note": String(k) + ((" " + String(d["kind"])) if d.has("kind") else "")})
					last = tp
				ev_log.append(entry)
		events.clear()
		if sim.ticks() % 25 == 0 and (absi(tp.x - last.x) + absi(tp.y - last.y)) >= 8:
			pts.append({"tick": sim.ticks(), "tile": [tp.x, tp.y], "note": ""})
			last = tp
	var ok := sim.has_silver_crown
	print("replay verification from reset: completed=%s ticks=%d (%.1f s game time) coins=%d blue=%d deaths=%d" % [ok, rep.tick_count(), rep.tick_count() / 100.0, sim.coins, sim.blue_coins, sim.deaths])
	for e in ev_log:
		print("  ", e)
	if not ok:
		return
	pts.append({"tick": rep.tick_count(), "tile": [54, 9], "note": "121 complete"})
	rep.meta = {"level": "ex_crew_odyssey", "kind": "completion", "ticks": rep.tick_count(), "hash": sim.state_hash()}
	rep.save("res://scripts/physics/route_completion.eerp")
	var f := FileAccess.open("res://scripts/physics/route_waypoints.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"level": "ex_crew_odyssey", "units": "tiles (x right, y down)",
		"spawn": [65, 11], "goal": [54, 9], "replay": "res://scripts/physics/route_completion.eerp",
		"ticks": rep.tick_count(), "waypoints": pts, "events": ev_log}, "  "))
	f.close()
	print("wrote route_completion.eerp (%d bytes) and route_waypoints.json (%d waypoints)" % [rep.to_bytes().size(), pts.size()])
