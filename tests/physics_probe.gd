extends SceneTree
# Plays a sequence and prints trajectory. env PROBE="tx,ty,plan" (tx<0 = from spawn)
# plan = seg;seg  seg = ticks:keys (keys from L R U D J; P = press jump on first tick)
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(l)
	var cb := func(k, d): if k != &"land" and k != &"jump" and k != &"door_state": print("   ev ", k, " ", d)
	sim.sim_event.connect(cb)
	var a := OS.get_environment("PROBE").split(",")
	if int(a[0]) >= 0:
		sim.px = int(a[0]) * 16; sim.py = int(a[1]) * 16
	var inp := EEInput.new()
	for seg in a[2].split(";"):
		var p := seg.split(":")
		var keys := p[1] if p.size() > 1 else ""
		inp.left = "L" in keys; inp.right = "R" in keys; inp.up = "U" in keys; inp.down = "D" in keys; inp.jump = "J" in keys
		for i in int(p[0]):
			inp.jump_pressed = "P" in keys and i == 0
			sim.tick(inp)
			if i % 5 == 0:
				print("t%d (%.1f,%.1f) tile(%d,%d) v=(%.2f,%.2f) g=%s cur=%d red=%s" % [sim.ticks(), sim.px, sim.py, (int(sim.px)+8)>>4, (int(sim.py)+8)>>4, sim.speed_x, sim.speed_y, sim.gravity_dir, sim.current_tile, sim.is_key_active(&"red")])
	sim.sim_event.disconnect(cb)
	quit()
