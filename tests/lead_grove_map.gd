extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var legend := {}
	var chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	for y in range(56, 112):
		var row := ""
		for x in range(0, 120):
			var f: int = l.get_fg(x, y)
			var bgid: int = l.get_bg(x, y)
			if f != 0:
				row += "#"
			else:
				if not legend.has(bgid):
					legend[bgid] = chars[legend.size() % chars.length()]
				row += "." if bgid == 0 else String(legend[bgid])
		print("%3d %s" % [y, row])
	print(legend)
	quit()
