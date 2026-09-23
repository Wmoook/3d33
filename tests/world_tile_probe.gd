extends SceneTree
## Prints fg/bg ids and terrain flags for a tile rectangle. Run headless:
## godot --headless --path . -s res://tests/world_tile_probe.gd -- level=forgotten_veil rect=318,26,12,10
func _init() -> void:
	var level_id := "forgotten_veil"
	var r := Rect2i(318, 26, 12, 10)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			level_id = a.substr(6)
		elif a.begins_with("rect="):
			var v := a.substr(5).split(",")
			r = Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
	var cfg := LevelCatalog.get_config(level_id)
	var lvl := EELevel.load_file(str(cfg.get("level_file", "")))
	WorldPalette.level_id = level_id
	var t := WorldTerrain.new()
	t.ref_dir = str(cfg.get("ref_dir", "res://assets/ee_ref"))
	t.day = str(cfg.get("time_of_day", "night")) == "day"
	t.level = lvl
	t.W = lvl.width
	t.H = lvl.height
	t._classify()
	t._find_pockets()
	for y in range(r.position.y, r.end.y):
		var line := "%3d " % y
		for x in range(r.position.x, r.end.x):
			var i := y * lvl.width + x
			var f := "S" if t.solid[i] else ("s" if t.sky[i] else ("w" if t.backwall[i] else ("p" if t.pocket[i] else ".")))
			line += "%4d/%-4d%s " % [lvl.fg[i], lvl.bg[i], f]
		print(line)
	quit()
