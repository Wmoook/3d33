extends Node
## Dynamic horizon camera on FV (tools_run_test.sh): spire top / mid spire gap / falls pool / low spot, each after
## the pitch settles; logs pitch and ball screen offset from centre. Output: user://hz_<spot>.png
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [["spire_top", Vector2(200, 30)], ["spire_gap", Vector2(222, 70)], ["falls_pool", Vector2(150, 170)], ["low", Vector2(200, 192)]]
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
	game.hud.show_hints = false
	game.sim.set_god_mode(true)
	print("[hz] fov=%.1f horizon_y=%.1f on=%s" % [game.rig.fov_v, game.rig.horizon_y, game.rig.horizon_pitch_on])
	for sp in SPOTS:
		var t: Vector2 = sp[1]
		game.sim.px = t.x * 16.0
		game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px
		game.sim.prev_py = game.sim.py
		game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))
		await _secs(8.0)
		var scr: Vector2 = game.rig.cam.unproject_position(game._render_pos)
		var c := get_viewport().get_visible_rect().size * 0.5
		print("[hz] %-10s pitch=%.2f deg  ball offset from centre=(%.0f, %.0f) px" % [sp[0], game.rig._alt_pitch, scr.x - c.x, scr.y - c.y])
		get_viewport().get_texture().get_image().save_png("user://hz_%s.png" % sp[0])
	get_tree().quit()
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
