extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	for y in range(100, 113):
		var row := ""
		for x in range(9, 18):
			row += "%4d/%-4d" % [l.get_fg(x, y), l.get_bg(x, y)]
		print("%3d %s" % [y, row])
	quit()
