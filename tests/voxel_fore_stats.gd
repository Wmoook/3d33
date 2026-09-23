extends SceneTree
## Headless: coverable-mask statistics for the foreground band (how much interior rock each level offers).
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var cfg := LevelCatalog.get_config("forgotten_veil")
	var lvl := EELevel.load_file(str(cfg.get("level_file")))
	WorldVoxel.enabled = false
	var world := WorldView.new()
	root.add_child(world)
	world.set_level_config(cfg)
	world.build(lvl)
	var f := WorldVoxelFore.new()
	root.add_child(f)
	f.setup(world.terrain)
	var h := {}
	for d in f.dist:
		var b := mini(d, 8)
		h[b] = int(h.get(b, 0)) + 1
	var solid := 0
	for v in world.terrain.solid:
		solid += v
	print("solid tiles %d, dist histogram %s" % [solid, str(h)])
	quit(0)
