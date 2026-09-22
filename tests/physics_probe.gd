extends SceneTree
# env PROBE="tx,ty,plan" plan = seg;seg  seg = ticks:keys (keys from L R U D J)
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(l)
	sim.sim_event.connect(func(k, d): if k != &"land" and k != &"jump" and k != &"door_state": print("   ev ", k, " ", d))
	var a := OS.get_environment("PROBE").split(",")
	sim.px = int(a[0]) * 16; sim.py = int(a[1]) * 16
	var inp := EEInput.new()
	for seg in a[2].split(";"):
		var p := seg.split(":")
		var keys := p[1] if p.size() > 1 else ""
		inp.left = "L" in keys; inp.right = "R" in keys; inp.up = "U" in keys; inp.down = "D" in keys; inp.jump = "J" in keys
		for i in int(p[0]):
			sim.tick(inp)
			if i % 5 == 0:
				print("t%d (%.1f,%.1f) tile(%d,%d) v=(%.2f,%.2f) g=%s cur=%d" % [sim.ticks(), sim.px, sim.py, (int(sim.px)+8)>>4, (int(sim.py)+8)>>4, sim.speed_x, sim.speed_y, sim.gravity_dir, sim.current_tile])
	quit()
