extends Node
## Door readability check on Forgotten Veil: closed/open pairs for its key doors, gate and purple doors.
## Saves user://doors_fv_<name>.png.
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [
	["door25", Vector2i(163, 168), "", -1], ["door25_open", Vector2i(163, 168), "blue", -1],
	["gate28", Vector2i(138, 135), "", -1], ["gate28_active", Vector2i(138, 135), "blue", -1],
	["purple184", Vector2i(210, 86), "", -1], ["purple184_open", Vector2i(210, 86), "", 1],
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
	var sw_id: int = game.sim.get_tile_number(210, 88)
	for s in SPOTS:
		for c in [&"red", &"green", &"blue"]:
			game.sim._set_key(c, s[2] != "" and StringName(s[2]) == c)
		game.sim._press_purple_switch(sw_id, s[3] > 0)
		var t: Vector2i = s[1]
		for i in 20:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			await get_tree().physics_frame
		await _wait(1.5)
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		im.resize(im.get_width() / 2, im.get_height() / 2)
		im.save_png("user://doors_fv_%s.png" % s[0])
		print("saved ", s[0], " solid=", game.sim.is_tile_solid_now(t.x, t.y + 2))
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
