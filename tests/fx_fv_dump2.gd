extends SceneTree
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var img := Image.create(lvl.width, lvl.height, false, Image.FORMAT_RGB8)
	var bgc := {}
	for y in lvl.height:
		for x in lvl.width:
			var f := lvl.get_fg(x, y); var b := lvl.get_bg(x, y)
			bgc[b] = bgc.get(b, 0) + 1
			var c := Color(0,0,0)
			if f in [10, 39, 54, 85]: c = Color(0, 0.5, 1)
			elif f == 25 or f == 28: c = Color(1, 0, 0)
			elif b in [537, 514, 521, 506, 526, 530]: c = Color(0, 1, 1) if f == 0 else Color(0,0.4,0.4)
			elif f == 0: c = Color(0.15, 0.15, 0.15)
			else: c = Color(0.4, 0.35, 0.3)
			img.set_pixel(x, y, c)
	img.resize(1600, 800, Image.INTERPOLATE_NEAREST)
	img.save_png("C:/Users/super/AppData/Local/Temp/claude/C--Users-super/0e57ecf3-522b-4b69-88ae-cc30d6e8ee4e/scratchpad/water.png")
	print("BG ", bgc)
	quit()
