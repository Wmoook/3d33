extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var byid := {}
	for id in [242, 381]:
		for p in l.find_all(id):
			var e := l.get_extra(p.x, p.y)
			var k := int(e["id"])
			if not byid.has(k): byid[k] = []
			byid[k].append([p, int(e["target"]), int(e["rotation"]), id])
	var ks := byid.keys(); ks.sort()
	for k in ks:
		var s := "id %d -> " % k
		var tg := {}
		for a in byid[k]: tg[a[1]] = true
		s += str(tg.keys()) + " rot " + str(byid[k][0][2]) + " type " + str(byid[k][0][3]) + " at "
		for a in byid[k]: s += str(a[0])
		print(s)
	for id in [100, 101, 121, 26, 28, 24, 8, 7]:
		var a := l.find_all(id)
		print(id, " count ", a.size(), " bbox ", _bbox(a))
	var cd := l.find_all(43)
	print("coin doors: ", cd)
	quit()
func _bbox(a: Array) -> String:
	if a.is_empty(): return "-"
	var mn: Vector2i = a[0]; var mx: Vector2i = a[0]
	for p in a:
		mn = Vector2i(mini(mn.x, p.x), mini(mn.y, p.y)); mx = Vector2i(maxi(mx.x, p.x), maxi(mx.y, p.y))
	return str(mn) + "-" + str(mx)
