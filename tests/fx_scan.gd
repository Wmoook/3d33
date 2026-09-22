extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	print("size ", l.width, "x", l.height, " grav ", l.gravity)
	for id in [1,2,3,4,5,6,7,8,23,24,25,26,28,43,100,101,121,242,381,255]:
		var a := l.find_all(id)
		if a.is_empty():
			print(id, ": none"); continue
		var mn := Vector2i(9999,9999); var mx := Vector2i(-1,-1)
		for p in a:
			mn = Vector2i(mini(mn.x,p.x), mini(mn.y,p.y)); mx = Vector2i(maxi(mx.x,p.x), maxi(mx.y,p.y))
		var s := ""
		for k in mini(6, a.size()): s += str(a[k]) + " "
		print(id, ": n=", a.size(), " bbox ", mn, "-", mx, " first ", s)
	for id in [242,381,43]:
		for p in l.find_all(id).slice(0, 12):
			print(id, " ", p, " ", l.get_extra(p.x,p.y))
	# red key density: 10x10 windows
	for id in [1,2,3,4,5,43,242]:
		var best := 0; var bp := Vector2i()
		for by in range(0, l.height, 10):
			for bx in range(0, l.width, 10):
				var c := 0
				for y in range(by, mini(by+20, l.height)):
					for x in range(bx, mini(bx+20, l.width)):
						if l.get_fg(x,y) == id: c += 1
				if c > best: best = c; bp = Vector2i(bx,by)
		print("densest ", id, " at ", bp, " count ", best)
	quit()
