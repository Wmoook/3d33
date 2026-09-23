extends Node
## One in-game shot of the C overview (tools_run_test.sh): user://dof_fv_vista.png / dof_fv_vista_wide.png
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "skip_title": true, "level": "forgotten_veil"}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 3:
		await get_tree().process_frame
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.tutorial.done = {"move": true, "keys": true, "arrows": true, "god": true}
	game.sim.set_god_mode(true)
	game.sim.px = 118 * 16.0
	game.sim.py = 30 * 16.0
	game.sim.prev_px = game.sim.px
	game.sim.prev_py = game.sim.py
	game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))
	print("[dof] transition=%s" % (game.rig.cam.attributes.dof_blur_far_transition if game.rig.cam.attributes else "none"))
	await _secs(3.0)
	get_viewport().get_texture().get_image().save_png("user://dof_fv_vista.png")
	game.toggle_overview()
	await _secs(2.0)
	get_viewport().get_texture().get_image().save_png("user://dof_fv_vista_wide.png")
	get_tree().quit()
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
