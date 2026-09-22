extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var hits := []
	for id in [23, 24, 25, 26, 28]:
		for t in l.find_all(id):
			if t.y < 20: hits.append([id, t])
	print(hits)
	quit()
