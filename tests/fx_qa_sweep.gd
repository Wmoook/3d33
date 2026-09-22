extends Node
## READABILITY QA sweep in the REAL game: ~40 god-mode spots over every zone and gameplay object kind.
## Each saves user://qa_<n>.png = [normal | F3 collision overlay] side by side (default zoom).
## Also a death/respawn strip and a portal-warp strip.  Run via tools_run_test.sh.  Args: -- from=<n>
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [
	# [name, tile, key colour to activate or ""]
	["spawn", Vector2(65, 11), ""],
	["finish_121", Vector2(54, 9), ""],
	["canopy_green_keys", Vector2(29, 9), ""],
	["door23_surface", Vector2(80, 9), ""],
	["door23_surface_open", Vector2(80, 9), "red"],
	["coin_door_62_14", Vector2(62, 14), ""],
	["portals_surface", Vector2(15, 10), ""],
	["portal_52_1", Vector2(52, 2), ""],
	["blue_coin_384_6", Vector2(384, 6), ""],
	["arrow_col_right", Vector2(388, 18), ""],
	["door24_green", Vector2(94, 42), ""],
	["door25_blue", Vector2(93, 40), ""],
	["door25_blue_open", Vector2(93, 40), "blue"],
	["red_key_tunnels", Vector2(110, 62), ""],
	["blue_keys_120_35", Vector2(120, 35), ""],
	["gate28_blue", Vector2(205, 50), ""],
	["gate28_blue_active", Vector2(205, 50), "blue"],
	["upper_lake", Vector2(216, 52), ""],
	["door25_236_56", Vector2(236, 56), ""],
	["blue_coin_217_77", Vector2(217, 77), ""],
	["invisible_portals", Vector2(210, 92), ""],
	["corruption", Vector2(210, 100), ""],
	["skull_pit", Vector2(140, 108), ""],
	["inferno_arrows", Vector2(150, 110), ""],
	["coin_door_141_105", Vector2(141, 105), ""],
	["tornado_top", Vector2(24, 90), ""],
	["tornado_mid", Vector2(36, 124), ""],
	["blue_keys_193_121", Vector2(193, 121), ""],
	["ice_dots", Vector2(262, 150), ""],
	["ice_cavern", Vector2(330, 140), ""],
	["gold_coin_331_141", Vector2(331, 141), ""],
	["crowns_249_134", Vector2(249, 134), ""],
	["right_halls", Vector2(335, 92), ""],
	["coin_door_281_58", Vector2(281, 58), ""],
	["demon_lake", Vector2(330, 186), ""],
	["lake_portal_273_183", Vector2(273, 183), ""],
	["portal_388_155", Vector2(388, 155), ""],
	["braziers", Vector2(220, 176), ""],
	["deep_doors_23", Vector2(22, 176), ""],
	["deep_doors_23_open", Vector2(22, 176), "red"],
	["gates26_red", Vector2(12, 184), ""],
	["gates26_red_active", Vector2(12, 184), "red"],
	["bones", Vector2(120, 170), ""],
]
var game

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
	var from := 0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("from="):
			from = int(a.substr(5))
		if a.begins_with("only="):
			only = a.substr(5)
	game.sim.set_god_mode(true)
	for i in range(from, SPOTS.size()):
		var s: Array = SPOTS[i]
		if only != "" and only != s[0]:
			continue
		for c in [&"red", &"green", &"blue"]:
			game.sim._set_key(c, s[2] != "" and StringName(s[2]) == c)
		_put(s[1])
		await _wait(1.6)
		game.collision_overlay.visible = false
		await _frames(3)
		var a := _grab()
		game.collision_overlay.visible = true
		game.collision_overlay.mark_dirty()
		await _frames(4)
		var b := _grab()
		game.collision_overlay.visible = false
		_pair(a, b).save_png("user://qa_%02d_%s.png" % [i, s[0]])
		print("saved qa_%02d_%s" % [i, s[0]])
	if only == "" or only == "death":
		await _death_strip()
	if only == "" or only == "portal":
		await _portal_strip()
	get_tree().quit()

func _put(t: Vector2) -> void:
	game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
	game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py

func _grab() -> Image:
	var im := get_viewport().get_texture().get_image()
	im.convert(Image.FORMAT_RGB8)
	im.resize(im.get_width() / 2, im.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	return im

func _pair(a: Image, b: Image) -> Image:
	var out := Image.create(a.get_width() * 2, a.get_height(), false, Image.FORMAT_RGB8)
	out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	out.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width(), 0))
	return out

func _strip(frames: Array, name: String) -> void:
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var out := Image.create(w * frames.size(), h, false, Image.FORMAT_RGB8)
	for i in frames.size():
		out.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	out.save_png("user://qa_%s.png" % name)
	print("saved qa_", name)

func _death_strip() -> void:
	game.sim.set_god_mode(false)
	_put(Vector2(66, 10))
	await _wait(1.5)
	var fr := [_grab()]
	game.sim.kill_player()
	await _frames(10)
	fr.append(_grab())
	await _wait(1.2)
	fr.append(_grab())
	await _wait(1.5)
	fr.append(_grab())
	_strip(fr, "death_respawn")

func _portal_strip() -> void:
	game.sim.set_god_mode(false)
	# stand just above portal (15,10) so gravity drops us in
	_put(Vector2(15, 8))
	var fr := [_grab()]
	for k in 3:
		await _frames(12)
		fr.append(_grab())
	_strip(fr, "portal_warp")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
