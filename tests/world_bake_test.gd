extends SceneTree
## Dev check: bakes the SDF and writes a visualisation to user://world_sdf.png
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var mask := PackedByteArray(); mask.resize(l.width * l.height)
	for i in l.fg.size():
		var m := 0
		if WorldPalette.is_world_solid(l.fg[i]): m = 3
		elif l.bg[i] >= 500 and l.bg[i] != 645: m = 2
		mask[i] = m
	var t := Time.get_ticks_msec()
	var img := WorldSdfBaker.bake(mask, l.width, l.height)
	print("BAKE ms=", Time.get_ticks_msec() - t, " size=", img.get_size())
	for p in [Vector2i(65*8+4, 11*8+4), Vector2i(0,0), Vector2i(800, 300)]:
		print(p, img.get_pixelv(p))
	var crop := img.get_region(Rect2i(0, 0, 100*8, 60*8))
	crop.convert(Image.FORMAT_RGBAF)
	var vis := Image.create(crop.get_width(), crop.get_height(), false, Image.FORMAT_RGB8)
	for y in crop.get_height():
		for x in crop.get_width():
			var c := crop.get_pixel(x, y)
			var f := c.r
			var band := 0.5 + 0.5 * sin(f * 12.0)
			vis.set_pixel(x, y, Color(clampf(f, 0, 1) * 0.8 + 0.2 * band, clampf(-f / 3.0, 0, 1), 0.3 if absf(f) < 0.05 else 0.0))
	vis.save_png("user://world_sdf.png")
	quit()
