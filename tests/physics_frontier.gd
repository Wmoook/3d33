extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(l)
	var arr: Array = JSON.parse_string(FileAccess.get_file_as_string("user://route_reached.json"))
	var S := {}
	for a in arr: S[Vector2i(int(a[0]), int(a[1]))] = true
	var fr := {}
	for t: Vector2i in S:
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = t + d
			if S.has(n) or n.x < 0 or n.y < 0 or n.x >= l.width or n.y >= l.height: continue
			var v := l.get_fg(n.x, n.y)
			var fl: int = sim._flag(v)
			if fl & EESim.F_SOLID == 0 or v in [23, 24, 25, 26, 27, 28, 43]:
				fr[n] = v
	var ks := fr.keys(); ks.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	for k in ks: print(k, " id ", fr[k])
	quit()
