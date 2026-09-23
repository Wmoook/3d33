extends SceneTree
## FV bg survey: bg id histogram over non-sky air tiles (fg 0 or passable), with minimap colours + a zone
## breakdown by rough area, and a class map image user://bg_class.png.
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var cols := {}
	var f := FileAccess.open("res://assets/ee_ref_fv/minimap_colors.json", FileAccess.READ)
	var mc = JSON.parse_string(f.get_as_text())
	var blocks = JSON.parse_string(FileAccess.open("res://assets/ee_ref_fv/blocks.json", FileAccess.READ).get_as_text())
	var hist := {}
	for i in lvl.width * lvl.height:
		var b := lvl.bg[i]
		if b == 0 or b in [531, 540, 541, 542]:
			continue
		hist[b] = hist.get(b, 0) + (1 if lvl.fg[i] == 0 else 0)
	var keys := hist.keys()
	keys.sort_custom(func(a, b): return hist[a] > hist[b])
	for k in keys:
		var pk = blocks.get(str(k), {})
		print("BG %4d n=%5d col=%s pkg=%s" % [k, hist[k], str(mc.get(str(k))), str(pk.get("package", "?") if pk is Dictionary else "?")])
	# map: air tiles (not world-solid) coloured by bg minimap colour; bg 0 air = magenta; solid = dark grey
	var img := Image.create(lvl.width, lvl.height, false, Image.FORMAT_RGB8)
	for y in lvl.height:
		for x in lvl.width:
			var i := y * lvl.width + x
			var fg := lvl.fg[i]
			var b := lvl.bg[i]
			var solid := WorldPalette.is_world_solid(fg)
			var c := Color(0.12, 0.12, 0.12)
			if not solid:
				if b in [531, 540, 541, 542]:
					c = Color(0.75, 0.85, 1.0)
				elif b == 0:
					c = Color(1, 0, 1)
				elif mc.get(str(b)) is String:
					c = Color.html(mc[str(b)])
			img.set_pixel(x, y, c)
	img.save_png("user://bg_class.png")
	var n0 := 0
	for i in lvl.width * lvl.height:
		if not WorldPalette.is_world_solid(lvl.fg[i]) and lvl.bg[i] == 0:
			n0 += 1
	print("BG air with bg 0: ", n0)
	quit()
