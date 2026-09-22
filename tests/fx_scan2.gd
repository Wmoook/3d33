extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	for y in range(6, 18):
		var s := ""
		for x in range(84, 100):
			s += "%4d" % l.get_fg(x, y)
		print("ROW ", y, s)
	quit()
