extends SceneTree
## Prints fg/bg ids of an FV tile rect.  Args: x0 y0 x1 y1
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	for y in range(int(a[1]), int(a[3]) + 1):
		var s := "%3d: " % y
		for x in range(int(a[0]), int(a[2]) + 1):
			s += "%4d/%-4d" % [lvl.get_fg(x, y), lvl.get_bg(x, y)]
		print(s)
	quit()
