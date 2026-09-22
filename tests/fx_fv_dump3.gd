extends SceneTree
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	for y in range(125, 178):
		var s := "%3d " % y
		for x in range(126, 175):
			var f := lvl.get_fg(x, y)
			var ch := "."
			match f:
				0: ch = " " if lvl.get_bg(x,y) in [531,540,541,542,0] else ("~" if lvl.get_bg(x,y) in [537,514,521,506,526,530] else ",")
				10: ch = "a"
				39: ch = "b"
				54: ch = "c"
				85: ch = "d"
				25: ch = "D"
				242: ch = "P"
				_: ch = "#" if WorldPalette.is_world_solid(f) else "o"
			s += ch
		print(s)
	quit()
