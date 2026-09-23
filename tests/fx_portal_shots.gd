extends Node
## Portal blocks in the real game: rows, one isolated portal per rotation (close zoom), a teleport moment.
## Args: -- level=forgotten_veil|odyssey tag=x   Saves user://fx_portal_<level>_<name><tag>.png
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := {
	"forgotten_veil": [["twin81", Vector2(248, 83), 30.0], ["twin91", Vector2(248, 93), 30.0],
		["rot0", Vector2(2, 15), 12.0], ["rot1", Vector2(8, 17), 12.0], ["rot2", Vector2(68, 103), 12.0],
		["rot3", Vector2(49, 74), 12.0], ["teleport", Vector2(247, 83), 18.0]],
	"odyssey": [["rot0", Vector2(195, 37), 12.0], ["rot1", Vector2(151, 42), 12.0], ["rot2", Vector2(53, 1), 12.0],
		["rot3", Vector2(370, 160), 12.0], ["wide", Vector2(151, 42), 30.0]],
}
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var lv := "forgotten_veil"
	var tag := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="): lv = a.substr(6)
		if a.begins_with("tag="): tag = "_" + a.substr(4)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": lv, "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	for s in SPOTS[lv]:
		var t: Vector2 = s[1]
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		game.rig.set("target_zoom", s[2]); game.rig.set("zoom", s[2])
		await _real(2.2)
		if s[0] == "teleport":
			game.sim.sim_event.emit(&"portal", {"from": Vector2i(249, 80), "to": Vector2i(250, 80)})
			await _real(0.12)
		get_viewport().get_texture().get_image().save_png("user://fx_portal_%s_%s%s.png" % [lv, s[0], tag])
		print("saved ", s[0])
	get_tree().quit()
func _real(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame
