extends SceneTree
## Headless WorldVoxel check: builds Forgotten Veil's WorldView, then the voxel landscape (async), and verifies
## timings, determinism-relevant stats and the readability clearance (no block right behind open sky air).
##   godot --headless --audio-driver Dummy --path . -s res://tests/voxel_gen.gd

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var cfg := LevelCatalog.get_config("forgotten_veil")
	var lvl := EELevel.load_file(str(cfg.get("level_file")))
	var world := WorldView.new()
	root.add_child(world)
	world.set_level_config(cfg)
	world.build(lvl)
	var vx: WorldVoxel = world.get("voxel") as WorldVoxel
	if vx == null:
		vx = WorldVoxel.new()
		world.add_child(vx)
		var t0 := Time.get_ticks_msec()
		vx.setup(world.terrain, world.depth, world.vista)
		print("setup (blocking) %d ms" % (Time.get_ticks_msec() - t0))
		vx.start()
	var t1 := Time.get_ticks_msec()
	while not vx.is_ready:
		await process_frame
		if Time.get_ticks_msec() - t1 > 120000:
			print("TIMEOUT")
			quit(1)
			return
	print("voxel async total %d ms" % (Time.get_ticks_msec() - t1))
	# block histogram (sparse sample)
	var hist := {}
	for p in range(0, vx.vox.size(), 7):
		var id: int = vx.vox[p]
		hist[id] = int(hist.get(id, 0)) + 1
	print("histogram /7: ", hist)
	# readability: blocks closer than 20 units behind open sky air (with 2 tiles margin from solids)
	var t := world.terrain
	var bad := 0
	var checked := 0
	for ty in t.H:
		for tx in t.W:
			var i := ty * t.W + tx
			if not t.sky[i] or t.solid[i]:
				continue
			checked += 1
			for dz in range(4, 22, 2):
				var id := vx.block_at(Vector3(tx + 0.5, -ty - 0.5, -float(dz) - 0.5))
				if id > 0 and id < 64:
					bad += 1
					if bad < 10:
						print("  block %d behind sky tile (%d,%d) at z=-%d" % [id, tx, ty, dz])
					break
	print("CLEARANCE: %d / %d sky tiles have a block <= 22 behind them %s" % [bad, checked, "OK" if bad == 0 else "CHECK"])
	quit(0)
