extends Node
## Isolates audit sky-leak clusters: shoots a spot with each world subsystem hidden in turn.
## Args: x y (tile) [zoom]. Saves user://iso_<tag>.png (half res).
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	var a := OS.get_cmdline_user_args()
	var t := Vector2(float(a[0]), float(a[1]))
	if a.size() > 2:
		game.rig.target_zoom = float(a[2]); game.rig.zoom = float(a[2])
	await _wait(8.0)
	for i in 30:
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		await get_tree().physics_frame
	await _wait(1.5)
	await _shot("base")
	var wv = game.world
	for nm in ["Vista", "Backdrop", "Keels", "Voxel", "Depth", "Decor", "Foliage", "Grass"]:
		var n: Node3D = wv.get_node_or_null(nm)
		if n == null:
			continue
		n.visible = false
		await _shot("no" + nm.to_lower())
		n.visible = true
	get_tree().quit()
func _shot(tag: String) -> void:
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	im.resize(im.get_width() / 2, im.get_height() / 2)
	im.save_png("user://iso_%s.png" % tag)
	print("saved iso_", tag)
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
