extends SceneTree
## Prints wall_code / forest hollow / room depth for tiles around (x, y) after a full WorldView build (day).
## Run: godot --headless --path . -s res://tests/world_tile_probe2.gd -- at=40,81
func _init() -> void:
	var at := Vector2i(40, 81)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("at="):
			var v := a.substr(3).split(",")
			at = Vector2i(int(v[0]), int(v[1]))
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
	t.window_image()
	var h := WorldForest.hollow_mask(t)
	var hi := WorldForest.hollow_image(t)
	for y in range(at.y - 3, at.y + 4):
		var line := "%3d " % y
		for x in range(at.x - 6, at.x + 7):
			var i := y * lvl.width + x
			line += "%s%3d%s%s%s " % ["S" if t.solid[i] else ".", t.wall_code[i], "h" if h[i] else " ", "k" if t.sky[i] else " ", "i" if hi.get_pixel(x, y).r > 0.1 else " "]
		print(line)
	quit()
