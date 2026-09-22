extends SceneTree
# Debug helper: solidity map of a region. env DUMP="x0,y0,x1,y1"
# # solid  . air  - one-way  R/G/B key door  r/g/b key gate  $ coin door  k/K/j keys(red/green/blue)
# c coin  C crown  W 121  P portal  S spawn  < ^ > arrows  * dot
func _init() -> void:
	var l := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(l)
	var r := OS.get_environment("DUMP").split(",")
	var x0 := int(r[0]); var y0 := int(r[1]); var x1 := int(r[2]); var y1 := int(r[3])
	var hdr := "     "
	for x in range(x0, x1 + 1): hdr += str(x % 10)
	print(hdr)
	var m := {23:"R",24:"G",25:"B",26:"r",27:"g",28:"b",43:"$",6:"k",7:"K",8:"j",100:"c",101:"c",5:"C",121:"W",242:"P",381:"P",255:"S",1:"<",2:"^",3:">",4:"*"}
	for y in range(y0, y1 + 1):
		var s := "%4d " % y
		for x in range(x0, x1 + 1):
			var v := l.get_fg(x, y)
			if m.has(v): s += m[v]
			elif sim.is_tile_one_way(x, y): s += "-"
			elif sim.is_tile_solid_now(x, y): s += "#"
			else: s += "."
		print(s)
	quit()
