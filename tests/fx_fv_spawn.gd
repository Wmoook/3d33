extends Node
## FV spawn check: ball parked right of the spawn so the tile behind the spawn marker is visible.
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
	game.sim.px = 4 * 16.0; game.sim.py = 57 * 16.0
	game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
	if OS.get_cmdline_user_args().has("noactors"):
		game.actors.visible = false
		game.actors.player.visible = true
	for i in 160:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://fx_fv_spawn%s.png" % ("_noactors" if OS.get_cmdline_user_args().has("noactors") else ""))
	print("saved fx_fv_spawn")
	get_tree().quit()
