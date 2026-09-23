extends SceneTree
## Dumps the painted-sky mask of Forgotten Veil (bg 530/531/540/541/542 with empty fg) as an image + the
## deepest painted-sky row per column.
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var W := lvl.width
	var H := lvl.height
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var ids := {}
	var deep := []
	for x in W:
		var d := 0
		for y in H:
			var b := lvl.get_bg(x, y)
			var f := lvl.get_fg(x, y)
			var skyish := b in [530, 531, 540, 541, 542]
			if skyish:
				ids[f] = ids.get(f, 0) + 1
			if skyish and f == 0:
				d = y
				img.set_pixel(x, y, Color(0.5, 0.7, 1.0) if b == 531 else (Color.WHITE if b == 540 else Color(0.8, 0.6, 1.0)))
			elif skyish:
				img.set_pixel(x, y, Color(0.3, 0.3, 0.6))
			elif f != 0:
				img.set_pixel(x, y, Color(0.4, 0.3, 0.2))
		deep.append(d)
	img.save_png("user://sky_profile_mask.png")
	print("deep ", deep)
	print("fg in sky ", ids)
	quit()
