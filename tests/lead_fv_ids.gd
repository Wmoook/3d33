extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var c := {}; var b := {}
	for y in range(128, 152):
		for x in range(138, 170):
			c[l.get_fg(x, y)] = c.get(l.get_fg(x, y), 0) + 1
			b[l.get_bg(x, y)] = b.get(l.get_bg(x, y), 0) + 1
	print("fg ", c); print("bg ", b)
	quit()
