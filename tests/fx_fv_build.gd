extends SceneTree
## Headless smoke: ActorsView builds for every level config (parse + site counts).
func _init() -> void:
	for id in ["forgotten_veil", "odyssey"]:
		var cfg := LevelCatalog.get_config(id)
		var lvl := EELevel.load_file(cfg.level_file)
		var sim := EESim.new(lvl)
		var a := ActorsView.new()
		root.add_child(a)
		a.set_level_config(cfg)
		a.build(lvl, sim)
		var m := a.overlays.maps
		var nw := 0
		var ns := 0
		for i in m.water.size():
			nw += m.water[i]
			ns += m.stream[i]
		print("[fx_fv_build] %s water=%d stream=%d surf=%d mech=%d children" % [id, nw, ns, m.water_surface.size(), a.mech.get_child_count()])
		a.update_player(Vector3(10, -10, 0), sim, 0.016)
		a._on_sim_event(&"piano", {"tile": Vector2i(396, 14), "note": 14})
		a._on_sim_event(&"switch", {"kind": &"purple", "id": 1, "on": true})
		a.queue_free()
	quit()
