extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	for y in range(48, 60):
		var s := "%3d: " % y
		for x in range(0, 8):
			s += "%5d/%-4d" % [l.get_fg(x, y), l.get_bg(x, y)]
		print(s)
	quit()
