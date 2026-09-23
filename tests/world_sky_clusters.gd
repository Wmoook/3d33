extends SceneTree
## Lists connected sky-air clusters (day sky mask) whose bbox reaches below y_min, to spot underground halls
## that render see-through. Run: godot --headless --path . -s res://tests/world_sky_clusters.gd -- y_min=90
func _init() -> void:
	var y_min := 90
	for a in OS.get_cmdline_user_args():
		if a.begins_with("y_min="):
			y_min = int(a.substr(6))
	var cfg := LevelCatalog.get_config("forgotten_veil")
	var lvl := EELevel.load_file(str(cfg.get("level_file", "")))
	WorldPalette.level_id = "forgotten_veil"
	var t := WorldTerrain.new()
	t.ref_dir = str(cfg.get("ref_dir", ""))
	t.day = true
	t.level = lvl
	t.W = lvl.width
	t.H = lvl.height
	t._classify()
	var W := t.W
	# painted non-sky bg rendered as open sky
	var bad := {}
	for i in W * t.H:
		var b: int = lvl.bg[i]
		if t.sky[i] and not t.solid[i] and b != 0 and not (b in WorldPalette.FV_SKY_BG):
			bad[b] = bad.get(b, 0) + 1
			if bad[b] <= 3:
				print("PAINTED-SKY tile (%d, %d) bg %d" % [i % W, i / W, b])
	print("PAINTED-SKY totals by bg: ", bad)
	var lost := {}
	for i in W * t.H:
		var b: int = lvl.bg[i]
		if not t.sky[i] and not t.solid[i] and not t.backwall[i] and b != 0 and not (b in WorldPalette.FV_SKY_BG):
			lost[b] = lost.get(b, 0) + 1
			if lost.size() <= 3 and lost[b] <= 2:
				print("NO-WALL tile (%d, %d) bg %d" % [i % W, i / W, b])
	print("NO-WALL painted bg (neither sky nor wall) by bg: ", lost)
	# floating wall specks: back-wall components of <= 6 tiles whose outline is mostly open sky air
	var seen2 := PackedByteArray(); seen2.resize(W * t.H)
	var specks := 0
	for s0 in W * t.H:
		if seen2[s0] or not t.backwall[s0] or t.solid[s0]:
			continue
		var comp2 := PackedInt32Array([s0]); seen2[s0] = 1
		var q2 := 0
		var edges := 0
		var skye := 0
		while q2 < comp2.size():
			var i := comp2[q2]; q2 += 1
			for o in [-1, 1, -W, W]:
				var j: int = i + o
				if j < 0 or j >= W * t.H:
					continue
				if t.backwall[j] and not t.solid[j]:
					if not seen2[j]:
						seen2[j] = 1
						comp2.append(j)
				else:
					edges += 1
					if t.sky[j] and not t.solid[j]:
						skye += 1
		if comp2.size() <= 6 and edges > 0 and skye * 2 >= edges:
			specks += 1
			print("FLOATING-WALL speck %d tiles at (%d, %d)" % [comp2.size(), comp2[0] % W, comp2[0] / W])
	print("FLOATING-WALL specks: ", specks)
	var seen := PackedByteArray(); seen.resize(W * t.H)
	for s in W * t.H:
		if seen[s] or not t.sky[s] or t.solid[s]:
			continue
		var comp := PackedInt32Array([s]); seen[s] = 1
		var qi := 0
		var r := Rect2i(s % W, s / W, 1, 1)
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			r = r.expand(Vector2i(i % W, i / W))
			for o in [-1, 1, -W, W]:
				var j: int = i + o
				if j >= 0 and j < W * t.H and not seen[j] and t.sky[j] and not t.solid[j]:
					seen[j] = 1
					comp.append(j)
		if r.end.y >= y_min:
			print("SKY cluster %d tiles bbox %s" % [comp.size(), r])
			# deep parts: per 10-column band, sky rows below y_min
			var bands := {}
			for i in comp:
				if i / W >= y_min:
					var b: int = (i % W) / 10
					if not bands.has(b):
						bands[b] = Vector2i(9999, -1)
					bands[b] = Vector2i(mini(bands[b].x, i / W), maxi(bands[b].y, i / W))
			for b in bands:
				print("   x %d-%d: y %d-%d" % [b * 10, b * 10 + 9, bands[b].x, bands[b].y])
	quit()
