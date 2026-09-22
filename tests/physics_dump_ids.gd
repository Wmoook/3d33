extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var r := OS.get_environment("DUMP").split(",")
	var x0 := int(r[0]); var y0 := int(r[1]); var x1 := int(r[2]); var y1 := int(r[3])
	var hdr := "     "
	for x in range(x0, x1 + 1): hdr += "%4d" % x
	print(hdr)
	for y in range(y0, y1 + 1):
		var s := "%4d " % y
		for x in range(x0, x1 + 1):
			var v := l.get_fg(x, y)
			s += "%4s" % ("." if v == 0 else str(v))
		print(s)
	quit()
