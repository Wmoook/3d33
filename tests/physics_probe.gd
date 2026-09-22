extends SceneTree
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var a := EESim.new(l)
	var inp := EEInput.new()
	inp.right = true
	for i in 300: a.tick(inp)
	var s1 := a.snapshot()
	inp.right = false; inp.left = true; inp.jump = true
	for i in 400: a.tick(inp)    # junk branch
	a.restore(s1)
	var b := EESim.new(l)
	inp.left = false; inp.jump = false; inp.right = true
	for i in 300: b.tick(inp)
	# compare every script variable
	for p in b.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var n: String = p["name"]
		if str(a.get(n)) != str(b.get(n)):
			print("DIFF ", n, ": ", str(a.get(n)).left(60), " vs ", str(b.get(n)).left(60), "  in_snapshot=", EESim._SNAP_PROPS.has(StringName(n)))
	quit()
