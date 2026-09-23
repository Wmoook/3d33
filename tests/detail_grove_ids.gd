extends SceneTree
## Headless: fg ids (letters) in the Elder Grove hollow and the Eastern Wood.
func _init() -> void:
	var l := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var legend := {}
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	for r: Array in [[0, 30, 90, 62], [360, 80, 400, 112]]:
		for y in range(r[1], r[3]):
			var row := ""
			for x in range(r[0], r[2]):
				var f: int = l.get_fg(x, y)
				if f == 0:
					row += "."
				else:
					if not legend.has(f):
						legend[f] = chars[legend.size() % chars.length()]
					row += String(legend[f])
			print("%3d %s" % [y, row])
		print("")
	print(legend)
	quit()
