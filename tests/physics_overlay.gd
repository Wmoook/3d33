extends SceneTree
# Overlay of user://route_reached.json on the solidity map. env DUMP="x0,y0,x1,y1"
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(l)
	var arr: Array = JSON.parse_string(FileAccess.get_file_as_string("user://route_reached.json"))
	var S := {}
	for a in arr: S[Vector2i(int(a[0]), int(a[1]))] = true
	var r := OS.get_environment("DUMP").split(",")
	var hdr := "     "
	for x in range(int(r[0]), int(r[2]) + 1): hdr += str(x % 10)
	print(hdr)
	var m := {23:"R",24:"G",25:"B",26:"r",27:"g",28:"b",43:"$",6:"k",7:"K",8:"j",100:"c",101:"c",5:"C",121:"W",242:"P",381:"P",255:"S",1:"<",2:"^",3:">",4:"*"}
	for y in range(int(r[1]), int(r[3]) + 1):
		var s := "%4d " % y
		for x in range(int(r[0]), int(r[2]) + 1):
			var v := l.get_fg(x, y)
			if S.has(Vector2i(x, y)): s += "o"
			elif m.has(v): s += m[v]
			elif sim.is_tile_one_way(x, y): s += "-"
			elif sim.is_tile_solid_now(x, y): s += "#"
			else: s += "."
		print(s)
	quit()
