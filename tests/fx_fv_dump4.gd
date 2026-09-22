extends SceneTree
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var c := {}
	for t in lvl.find_all(43):
		var r := int(lvl.get_extra(t.x, t.y).get("rotation", 0)); c[r] = c.get(r, 0) + 1
	print("ODY43 ", c, " 409:", lvl.find_all(409).size(), " 113:", lvl.find_all(113).size(), " 77:", lvl.find_all(77).size())
	quit()
