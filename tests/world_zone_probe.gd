extends SceneTree
## Headless zone lookup probe: prints get_zone_at for a few tiles.
func _init() -> void:
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var t := WorldTerrain.new()
	t.level = lvl; t.W = lvl.width; t.H = lvl.height
	t._classify()
	var z := WorldZones.new()
	z.build(t)
	for p in [Vector2i(54, 86), Vector2i(20, 110), Vector2i(40, 140), Vector2i(65, 11), Vector2i(150, 55)]:
		print(p, " ", z.zone_at(p))
	t.free()
	quit()
