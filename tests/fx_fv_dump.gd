extends SceneTree
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var counts := {}
	for i in lvl.fg.size():
		var id := lvl.fg[i]
		counts[id] = counts.get(id, 0) + 1
	var ks := counts.keys(); ks.sort()
	var s := ""
	for k in ks: s += "%d:%d " % [k, counts[k]]
	print("FG ", s)
	for id in [113, 115, 77, 409, 412, 414, 100, 101, 242, 381, 43, 121, 255, 184, 185, 1006, 1004, 5, 6, 7, 8, 1, 2, 3, 4]:
		var t := lvl.find_all(id)
		var out := []
		for k in mini(t.size(), 40):
			var e := lvl.get_extra(t[k].x, t[k].y)
			out.append("%d,%d%s" % [t[k].x, t[k].y, (" " + str(e)) if not e.is_empty() else ""])
		print("ID ", id, " n=", t.size(), " ", out)
	quit()
