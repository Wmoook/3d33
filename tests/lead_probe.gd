extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var c := {}
	for y in range(0, 16):
		for x in range(0, 400):
			var id := l.get_fg(x, y)
			c[id] = c.get(id, 0) + 1
	print("top rows ids: ", c)
	var s := ""
	for y in range(0, 16):
		s = ""
		for x in range(50, 72):
			s += "%5d" % l.get_fg(x, y)
		print(s)
	quit()
