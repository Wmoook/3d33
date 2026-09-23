extends SceneTree
## Dumps WorldBgSpace's maps for FV: user://bgspace_class.png (class colours) and bgspace_tone.png.
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var s := WorldBgSpace.new()
	var solid := PackedByteArray()
	solid.resize(lvl.width * lvl.height)
	s.build(lvl, WorldBgSpace.load_colors("res://assets/ee_ref_fv"), solid)
	var pal := [Color(0.75, 0.85, 1.0), Color(0.55, 0.35, 0.15), Color(0.15, 0.5, 0.12), Color(0.5, 0.5, 0.52), Color(0.8, 0.7, 0.45), Color(0.15, 0.4, 0.8), Color(0.05, 0.02, 0.08)]
	var ci := Image.create(s.W, s.H, false, Image.FORMAT_RGB8)
	var ti := Image.create(s.W, s.H, false, Image.FORMAT_RGB8)
	for y in s.H:
		for x in s.W:
			var i := y * s.W + x
			var c: Color = pal[s.cls[i]]
			if WorldPalette.is_world_solid(lvl.fg[i]):
				c = c.darkened(0.7)
			ci.set_pixel(x, y, c)
			ti.set_pixel(x, y, s.tone[i] if s.cls[i] != 0 else Color(0.75, 0.85, 1.0))
	ci.save_png("user://bgspace_class.png")
	ti.save_png("user://bgspace_tone.png")
	print("bgspace ok")
	quit()
