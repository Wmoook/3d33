extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var cs := l.find_all(100)
	cs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var i := 1
	for c in cs:
		print(i, " ", c, " bg=", l.get_bg(c.x, c.y))
		i += 1
	quit()
