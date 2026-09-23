extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	for y in range(int(a[1]), int(a[3]) + 1):
		var s := "%3d: " % y
		for x in range(int(a[0]), int(a[2]) + 1):
			s += "%4d" % lvl.get_fg(x, y)
		print(s)
	quit()
