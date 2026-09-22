extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	for r in [[190,38,250,64],[262,168,400,200]]:
		var c := {}
		for y in range(r[1], r[3]):
			for x in range(r[0], r[2]):
				var id := l.get_fg(x, y)
				c[id] = c.get(id, 0) + 1
		print("R ", r, " ", c)
	quit()
