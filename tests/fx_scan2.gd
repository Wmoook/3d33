extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	print("spawn ", l.find_all(255))
	for y in range(50, 60):
		var s := ""
		for x in range(0, 8):
			s += " %4d/%4d" % [l.get_fg(x, y), l.get_bg(x, y)]
		print("ROW ", y, s)
	quit()
