extends Node
## FV door / gate / coin-door re-verification against the recessed rooms and caves: every cluster shot
## in state A (keys off, switches off, 0 coins) and state B (all keys, all switches, 99 coins) at zoom 30.
## Saves user://dall_<name>.png = [A | B] (half res each).  Arg: only=<name>.
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [
	["purple_row", Vector2(196, 88)], ["magenta_209", Vector2(209, 87)], ["purple_287", Vector2(288, 131)],
	["purple_330", Vector2(330, 132)], ["gate28", Vector2(138, 136)], ["blue_pool_w", Vector2(145, 172)],
	["blue_pool_e", Vector2(163, 171)], ["blue_aqueduct", Vector2(125, 187)], ["coin16", Vector2(50, 54)],
	["coin_244", Vector2(250, 80)], ["coin_349", Vector2(352, 108)], ["coin_336", Vector2(336, 145)],
	["coin_223", Vector2(225, 182)], ["coin_212", Vector2(215, 191)],
]
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	await _wait(8.0)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	for s in SPOTS:
		if only != "" and only != s[0]:
			continue
		var imgs := []
		for st in [false, true]:
			for c in [&"red", &"green", &"blue", &"magenta"]:
				game.sim._set_key(c, st)
			game.sim._press_purple_switch(1000, st)
			game.sim.coins = 99 if st else 0
			var t: Vector2 = s[1]
			for i in 25:
				game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
				game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
				await get_tree().physics_frame
			await _wait(1.2)
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.resize(im.get_width() / 2, im.get_height() / 2)
			imgs.append(im)
		var a: Image = imgs[0]
		var out := Image.create(a.get_width() * 2, a.get_height(), false, a.get_format())
		out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
		out.blit_rect(imgs[1], Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(a.get_width(), 0))
		out.save_png("user://dall_%s.png" % s[0])
		print("saved dall_", s[0])
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
