extends SceneTree
## Picks QA spots: one representative open tile per object kind / zone.
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	for id in [23, 24, 25, 26, 28, 43, 100, 101, 121, 242, 381, 255, 5, 7, 8]:
		var a := l.find_all(id)
		var picks := []
		var step := maxi(1, a.size() / 3)
		for k in range(0, a.size(), step):
			picks.append(a[k])
			if picks.size() >= 3: break
		print("ID ", id, " ", picks)
	quit()
