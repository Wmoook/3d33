extends SceneTree
## Door probe: lists key-door / gate regions (id, first tile, size) of a level.
func _init() -> void:
	var path := "res://levels/forgotten_veil.eelvl"
	for a in OS.get_cmdline_user_args():
		path = a
	var lvl := EELevel.load_file(path)
	var cnt := {}
	var first := {}
	for y in lvl.height:
		for x in lvl.width:
			var id := lvl.get_fg(x, y)
			if id in [23, 24, 25, 26, 27, 28, 184, 185, 1006]:
				cnt[id] = cnt.get(id, 0) + 1
				if not first.has(id):
					first[id] = Vector2i(x, y)
	print("doors ", cnt, " first ", first)
	quit()
