extends Node
## Ambient life in the REAL game: for each creature type, a 3-frame strip (0.35 s apart) showing motion /
## reaction, saved as user://fx_life_<name>.png.  Run via tools_run_test.sh.  Args: -- only=<name>
const GameScript := preload("res://scripts/game/game.gd")
var game
var life: FxAmbientLife

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.booted
	await _wait(1.0)
	game.press_start()
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	life = game.actors.life
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	game.sim.set_god_mode(true)
	if only == "" or only == "bats":
		var r := _dense_roost()
		await _strip("bats", Vector2(r.x - 9, r.y + 1), Vector2(r.x + 0.5, r.y + 1.0))
	if only == "" or only == "fish":
		var f: Vector2i = life._fish_sites[life._fish_sites.size() / 2]
		await _strip("fish", Vector2(f.x - 7, f.y), Vector2(f.x, f.y))
	if only == "" or only == "fireflies":
		var t: Vector2i = life._ff_sites[life._ff_sites.size() / 3]
		await _strip("fireflies", Vector2(t.x - 4, t.y), Vector2(t.x, t.y))
	if only == "" or only == "moths":
		await _strip("moths", Vector2(214, 164), Vector2(219, 164))
	if only == "" or only == "wisps":
		await _strip("wisps", Vector2(208, 100), Vector2(212, 100))
	if only == "" or only == "ash":
		await _strip("ash", Vector2(150, 106), Vector2(154, 106))
	get_tree().quit()

func _dense_roost() -> Vector2i:
	var best := Vector2i(150, 70)
	var bc := 0
	for i in range(0, life._roosts.size(), 3):
		var t: Vector2i = life._roosts[i]
		var c := 0
		for o in life._roosts:
			if Vector2(o).distance_to(Vector2(t)) < 4.0:
				c += 1
		if c > bc:
			bc = c
			best = t
	print("bat roost ", best, " neighbours ", bc)
	return best

func _put(t: Vector2) -> void:
	game.sim.px = t.x * 16.0 - 8.0; game.sim.py = t.y * 16.0 - 8.0
	game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py

func _strip(name: String, start: Vector2, goal: Vector2) -> void:
	_put(start)
	await _wait(2.5)
	var frames: Array[Image] = []
	frames.append(_grab())
	# glide the ball toward the goal while capturing
	for k in 2:
		for i in 14:
			var a := (k * 14 + i + 1) / 28.0
			_put(start.lerp(goal, a))
			await get_tree().process_frame
			await get_tree().process_frame
		frames.append(_grab())
	var fw := frames[0].get_width() / 2
	var fh := frames[0].get_height() / 2
	var strip := Image.create(fw * 3, fh, false, Image.FORMAT_RGBA8)
	for i in 3:
		var im := frames[i]
		im.convert(Image.FORMAT_RGBA8)
		var c := im.get_region(Rect2i(im.get_width() / 4, im.get_height() / 4, im.get_width() / 2, im.get_height() / 2))
		strip.blit_rect(c, Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))
	strip.save_png("user://fx_life_%s.png" % name)
	print("saved fx_life_", name)

func _grab() -> Image:
	return get_viewport().get_texture().get_image()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
