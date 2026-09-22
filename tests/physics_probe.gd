extends SceneTree
const ACTIONS := [[0,0,0,0,0],[1,0,0,0,0],[0,1,0,0,0],[0,0,1,0,0],[0,0,0,1,0],[0,0,0,0,1],[1,0,0,0,1],[0,1,0,0,1]]
func _apply(sim: EESim, ac: Array, macro: int, inp: EEInput) -> void:
	inp.left = ac[0] == 1; inp.right = ac[1] == 1; inp.up = ac[2] == 1; inp.down = ac[3] == 1
	for t in macro:
		inp.jump = ac[4] == 1
		inp.jump_pressed = ac[4] == 1 and t == 0
		sim.tick(inp)
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var pj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://route_partial.json"))
	var acts: Array = pj["actions"]
	var a := EESim.new(l)
	var b := EESim.new(l)
	var ia := EEInput.new(); var ib := EEInput.new()
	for i in acts.size():
		var ac: Array = ACTIONS[int(acts[i][0])]
		var m := int(acts[i][1])
		_apply(a, ac, m, ia)
		var s := b.snapshot()
		b.restore(s)
		_apply(b, ac, m, ib)
		if a.state_hash() != b.state_hash():
			print("diverged at macro ", i)
			for p in EESim._SNAP_PROPS:
				if str(a.get(p)) != str(b.get(p)): print("  ", p, ": ", str(a.get(p)).left(80), " vs ", str(b.get(p)).left(80))
			break
	print("end a ", Vector2i((int(a.px)+8)>>4, (int(a.py)+8)>>4), " b ", Vector2i((int(b.px)+8)>>4, (int(b.py)+8)>>4))
	quit()
