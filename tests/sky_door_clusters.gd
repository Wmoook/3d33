extends SceneTree
## Lists connected clusters of door/gate ids in FV: id, bbox, count.
const IDS := [23, 24, 25, 26, 27, 28, 184, 185, 1005, 1006, 1007, 1008, 1009, 1010, 43, 156, 157, 1079, 1080]
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var W := lvl.width
	var H := lvl.height
	var seen := PackedByteArray()
	seen.resize(W * H)
	for s in W * H:
		var id := lvl.fg[s]
		if seen[s] or not (id in IDS):
			continue
		var q := [s]
		seen[s] = 1
		var mn := Vector2i(s % W, s / W)
		var mx := mn
		var qi := 0
		while qi < q.size():
			var i: int = q[qi]; qi += 1
			var x := i % W
			var y := i / W
			mn = Vector2i(mini(mn.x, x), mini(mn.y, y)); mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if not seen[j] and lvl.fg[j] == id:
					seen[j] = 1
					q.append(j)
		print("CL id=%d n=%d rect=%s-%s" % [id, q.size(), mn, mx])
	quit()
