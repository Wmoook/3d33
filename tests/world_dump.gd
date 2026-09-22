extends SceneTree
## Dev helper: dumps fg/bg id grids as raw int32 little-endian to the path in argv (after --).
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var out := "user://level_dump.bin"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_32(l.width); f.store_32(l.height)
	f.store_buffer(l.fg.to_byte_array())
	f.store_buffer(l.bg.to_byte_array())
	f.close()
	print("DUMP ", l.width, "x", l.height, " -> ", ProjectSettings.globalize_path(out))
	quit()
