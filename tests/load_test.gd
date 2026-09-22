extends SceneTree
func _init() -> void:
	var t := Time.get_ticks_msec()
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	print("LOAD ", l.width, "x", l.height, " in ", Time.get_ticks_msec() - t, "ms; spawn=", l.find_all(255), " portals=", l.find_all(242).size(), " extra=", l.extra.size())
	quit()
