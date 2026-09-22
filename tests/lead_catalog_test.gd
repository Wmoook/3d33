extends SceneTree
func _init() -> void:
	for c in LevelCatalog.all():
		var l := EELevel.load_file(c.level_file)
		print(c.id, " -> ", l.width, "x", l.height, " spawn=", l.find_all(255), " ref=", c.ref_dir, " exists=", ResourceLoader.exists(c.ref_dir + "/minimap_ee.png") or FileAccess.file_exists(c.ref_dir + "/minimap_ee.png"))
	quit()
