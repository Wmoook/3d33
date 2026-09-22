extends SceneTree
## Dumps Forgotten Veil mechanic blocks (ids, positions, extras) for the physics audit / route survey.
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	print("size ", l.width, "x", l.height, " gravity ", l.gravity)
	var counts := {}
	for v in l.fg:
		counts[v] = counts.get(v, 0) + 1
	var ids := counts.keys(); ids.sort()
	var s := ""
	for id in ids: s += "%d:%d " % [id, counts[id]]
	print("fg counts: ", s)
	for id in [113, 184, 185, 114, 115, 116, 117, 408, 409, 410, 1005, 1006, 1007, 1008, 1009, 1010, 1004, 43, 100, 101, 77, 411, 412, 413, 414, 255, 121, 360, 5, 6, 7, 8, 23, 24, 25, 26, 27, 28, 467, 1619, 1620, 1079, 1080, 165, 213, 214]:
		var pts := l.find_all(id)
		if pts.is_empty(): continue
		var line := "id %d (%d):" % [id, pts.size()]
		for p in pts.slice(0, 60):
			var ex := l.get_extra(p.x, p.y)
			line += " %d,%d%s" % [p.x, p.y, ("" if ex.is_empty() else "r" + str(ex.get("rotation", "")))]
		print(line)
	for id in [242, 381]:
		var pts := l.find_all(id)
		var line := "portal %d (%d):" % [id, pts.size()]
		for p in pts:
			var ex := l.get_extra(p.x, p.y)
			line += " %d,%d[%s>%s r%s]" % [p.x, p.y, ex.get("id"), ex.get("target"), ex.get("rotation")]
		print(line)
	quit()
