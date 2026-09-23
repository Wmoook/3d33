extends SceneTree
func dump(l: EELevel, x0: int, x1: int, y0: int, y1: int, name: String) -> void:
	var c := {}
	var air := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			if l.get_fg(x, y) == 0 or l.get_fg(x, y) in [1,2,3,4,242,381,100,101]:
				air += 1
				var b := l.get_bg(x, y)
				c[b] = c.get(b, 0) + 1
	print(name, " air=", air, " bg_of_air=", c)
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	dump(l, 330, 400, 83, 96, "trial15_hall")
	dump(l, 185, 215, 42, 88, "great_spire_shaft")
	dump(l, 232, 262, 70, 95, "twin_spire")
	dump(l, 290, 320, 80, 105, "keep")
	quit()
