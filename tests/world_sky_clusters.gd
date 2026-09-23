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
