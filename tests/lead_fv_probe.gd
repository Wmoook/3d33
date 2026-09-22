extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	if l == null:
		print("LOAD FAILED"); quit(); return
	print("name=", l.world_name, " owner=", l.owner, " size=", l.width, "x", l.height, " grav=", l.gravity, " bg=", "%x" % l.background_color)
	var c := {}
	for i in l.fg.size():
		c[l.fg[i]] = c.get(l.fg[i], 0) + 1
	var b := {}
	for i in l.bg.size():
		b[l.bg[i]] = b.get(l.bg[i], 0) + 1
	var ks := c.keys(); ks.sort()
	var s := ""
	for k in ks: s += "%d:%d " % [k, c[k]]
	print("FG ", s)
	ks = b.keys(); ks.sort(); s = ""
	for k in ks: s += "%d:%d " % [k, b[k]]
	print("BG ", s)
	print("spawn=", l.find_all(255), " extra=", l.extra.size())
	var ex := {}
	for i in l.extra: 
		var id := l.fg[i]
		if not ex.has(id): ex[id] = []
		if ex[id].size() < 4: ex[id].append([i % l.width, i / l.width, l.extra[i]])
	for k in ex: print("  extra ", k, " ", ex[k])
	quit()
