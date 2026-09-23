extends Node
## Sub-pixel shimmer isolation: at a spot (zoom 30) it grabs frames with the ball at px and px + 0.45 EE px,
## and measures the mean abs difference inside given tile rects, with each world layer hidden in turn.
## Args: bx by  x0 y0 x1 y1 [x0 y0 x1 y1 ...]   (tile coords, y down)
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
	var b := Vector2(float(a[0]), float(a[1]))
	var rects: Array[Rect2] = []
	var i := 2
	while i + 3 < a.size():
		rects.append(Rect2(float(a[i]), float(a[i + 1]), float(a[i + 2]) - float(a[i]) + 1.0, float(a[i + 3]) - float(a[i + 1]) + 1.0))
		i += 4
	await _wait(8.0)
	var wv = game.world
	var layers := ["", "", "", "Vista", "Backdrop", "Keels", "Voxel", "Depth", "DepthGreen", "Forest", "Decor", "Foliage", "Grass", "Trials", "Doors", "Lights", ""]
	if OS.get_environment("SHIM_SUB") != "":
		layers = [""]
		for c in wv.get_node(OS.get_environment("SHIM_SUB")).get_children():
			layers.append(OS.get_environment("SHIM_SUB") + "/" + String(c.name))
		layers.append("")
	for ln in layers:
		var n: Node3D = wv.get_node_or_null(ln) if ln != "" else null
		if ln != "" and n == null:
			continue
		if n:
			n.visible = false
		var f0 := await _grab(b)
		# a shift of exactly ONE screen pixel, compared motion-compensated (image shifted back by 1 px):
		# a stable, well-antialiased surface then matches except for noise; aliasing / shimmer does not
		var px_tiles := _tiles_per_px()
		var f1 := await _grab(b + Vector2(px_tiles, 0.0))
		var f2 := await _grab(b + Vector2(px_tiles, 0.0))   # same position again: the noise floor
		if OS.get_environment("SHIM_SAVE") != "" and ln == "":
			f0.save_png("user://shim_f0.png"); f1.save_png("user://shim_f1.png")
		var line := "SHIM %-10s" % (ln if ln != "" else "base")
		for r in rects:
			line += "  %s=%.4f/%.4f" % [str(r.position), minf(_diff(f0, f1, r, 1), _diff(f0, f1, r, -1)), _diff(f1, f2, r, 0)]
		print(line)
		if n:
			n.visible = true
	get_tree().quit()
func _grab(t: Vector2) -> Image:
	for k in 40:
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		await get_tree().physics_frame
	for k in 4:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
func _tiles_per_px() -> float:
	var cam := get_viewport().get_camera_3d()
	var a := cam.project_position(Vector2(0, 0), cam.global_position.z)
	var b := cam.project_position(Vector2(1, 0), cam.global_position.z)
	var img_w := float(get_viewport().get_texture().get_image().get_width())
	return absf(b.x - a.x) * get_viewport().get_visible_rect().size.x / img_w

func _diff(a: Image, b: Image, r: Rect2, sh: int) -> float:
	var cam := get_viewport().get_camera_3d()
	var p0 := cam.unproject_position(Vector3(r.position.x, -r.position.y, 0.0))
	var p1 := cam.unproject_position(Vector3(r.end.x, -r.end.y, 0.0))
	var s := Vector2(a.get_width(), a.get_height()) / get_viewport().get_visible_rect().size
	var x0 := int(clampf(minf(p0.x, p1.x) * s.x, 0, a.get_width() - 1))
	var x1 := int(clampf(maxf(p0.x, p1.x) * s.x, 0, a.get_width() - 1))
	var y0 := int(clampf(minf(p0.y, p1.y) * s.y, 0, a.get_height() - 1))
	var y1 := int(clampf(maxf(p0.y, p1.y) * s.y, 0, a.get_height() - 1))
	var sum := 0.0
	var n := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(clampi(x - sh, 0, b.get_width() - 1), y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return sum / maxf(n, 1)
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
