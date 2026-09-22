extends SceneTree
## Topology survey: 4-connected air components of layer 0 (all key doors/gates/coin doors treated
## as passable = optimistic), linked by portal edges. Physics-agnostic upper bound on reachability.
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(l)
	var w := l.width; var h := l.height
	var open := PackedByteArray(); open.resize(w * h)
	for i in w * h:
		var v := l.fg[i]
		var fl: int = sim._flag(v)
		var doors_open := OS.get_environment("DOORS") == "open"
		var passable_door := v in [26, 27, 28] or (doors_open and fl & EESim.F_DOOR != 0 and v != 50)
		open[i] = 1 if (fl & EESim.F_SOLID == 0 or passable_door or fl & EESim.F_JUMPTHRU != 0) else 0
	var comp := PackedInt32Array(); comp.resize(w * h); comp.fill(-1)
	var sizes := []
	var nc := 0
	for i in w * h:
		if open[i] == 0 or comp[i] >= 0: continue
		var st := [i]; comp[i] = nc; var n := 0
		while not st.is_empty():
			var c: int = st.pop_back(); n += 1
			var cx := c % w; var cy := c / w
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nx: int = cx + d.x; var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
				var j := ny * w + nx
				if open[j] == 1 and comp[j] < 0:
					comp[j] = nc; st.append(j)
		sizes.append(n); nc += 1
	var at := func(x: int, y: int) -> int: return comp[y * w + x]
	print("components: ", nc)
	var named := {"spawn": Vector2i(65, 11), "goal121": Vector2i(54, 9), "coin100": Vector2i(331, 141)}
	for k in named:
		var p: Vector2i = named[k]
		print("  %s %s -> comp %d (size %d)" % [k, p, at.call(p.x, p.y), sizes[at.call(p.x, p.y)]])
	for p in l.find_all(101):
		print("  blue coin %s -> comp %d" % [p, at.call(p.x, p.y)])
	# portal edges
	var by_id := {}
	for id in [242, 381]:
		for p in l.find_all(id):
			var e := l.get_extra(p.x, p.y)
			if not by_id.has(int(e["id"])): by_id[int(e["id"])] = []
			by_id[int(e["id"])].append(p)
	var edges := {}
	for id in [242, 381]:
		for p in l.find_all(id):
			var e := l.get_extra(p.x, p.y)
			var t := int(e["target"])
			if t == int(e["id"]) or not by_id.has(t): continue
			for q in by_id[t]:
				var a: int = at.call(p.x, p.y); var b: int = at.call(q.x, q.y)
				var key := "%d->%d" % [a, b]
				if not edges.has(key): edges[key] = "%s(id%d) -> %s(id%d)" % [p, int(e["id"]), q, t]
	print("portal component edges:")
	for k in edges: print("  ", k, "  ", edges[k])
	# BFS over components from spawn
	var start: int = at.call(65, 11)
	var reach := {start: true}
	var q := [start]
	while not q.is_empty():
		var c: int = q.pop_front()
		for k: String in edges:
			var ab := k.split("->")
			if int(ab[0]) == c and not reach.has(int(ab[1])):
				reach[int(ab[1])] = true; q.append(int(ab[1]))
	print("components reachable from spawn via portals (doors all open): ", reach.keys())
	print("goal reachable (topologically): ", reach.has(at.call(54, 9)), "  coin reachable: ", reach.has(at.call(331, 141)))
	# which comps hold portals
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var cols := {}
	for i in w * h:
		if comp[i] < 0: img.set_pixel(i % w, i / w, Color(0.25, 0.25, 0.25)); continue
		if not cols.has(comp[i]):
			var r := RandomNumberGenerator.new(); r.seed = comp[i] * 7919
			cols[comp[i]] = Color(r.randf_range(0.3, 1), r.randf_range(0.3, 1), r.randf_range(0.3, 1))
		img.set_pixel(i % w, i / w, Color(1, 1, 1) if reach.has(comp[i]) else cols[comp[i]])
	img.save_png("user://topology.png")
	var big := []
	for c in nc: if sizes[c] > 150: big.append([c, sizes[c]])
	print("big components (>150 tiles): ", big)
	# door tiles adjacent to 2+ different components (closed-door mode): the "bridges"
	var bridges := {}
	for i in w * h:
		var v := l.fg[i]
		if not (v in [23, 24, 25, 43]): continue
		var cs := {}
		var cx := i % w; var cy := i / w
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nx: int = cx + d.x; var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
			var c: int = comp[ny * w + nx]
			if c >= 0: cs[c] = true
		if cs.size() >= 2:
			var ks := cs.keys(); ks.sort()
			var key := str(ks) + " via " + str(v)
			if not bridges.has(key): bridges[key] = []
			bridges[key].append(Vector2i(cx, cy))
	# door clusters (same door id, 4-connected) and the components they touch
	var seen_d := PackedByteArray(); seen_d.resize(w * h)
	for i in w * h:
		var v := l.fg[i]
		if not (v in [23, 24, 25, 43]) or seen_d[i] == 1: continue
		var st := [i]; seen_d[i] = 1
		var cs := {}; var tl := []
		while not st.is_empty():
			var c: int = st.pop_back(); tl.append(Vector2i(c % w, c / w))
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nx: int = c % w + d.x; var ny: int = c / w + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
				var j := ny * w + nx
				if l.fg[j] == v and seen_d[j] == 0: seen_d[j] = 1; st.append(j)
				elif comp[j] >= 0 and sizes[comp[j]] >= 20: cs[comp[j]] = sizes[comp[j]]
		if cs.size() >= 2:
			print("  door cluster id%d n=%d at %s joins %s" % [v, tl.size(), tl[0], cs])
	for k in bridges:
		var ks: String = k
		var big_only := true
		print("  bridge ", k, " sizes ", _sizes_of(ks, sizes), " at ", bridges[k].slice(0, 4))
	quit()

func _sizes_of(k: String, sizes: Array) -> String:
	var inner := k.substr(1, k.find("]") - 1)
	var out := []
	for t in inner.split(","): out.append(sizes[int(t)])
	return str(out)
