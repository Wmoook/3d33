extends Node
## FV title: showcase flyover keys + readable prompt (tools_run_test.sh). Output: user://tfv_*.png
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "level": "forgotten_veil"}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 1:
		await get_tree().process_frame
	for i in 4:
		game.rig._cine_s = float(i) + 0.3
		await _secs(5.5 if i == 0 else 1.5)
		_shot("tfv_%d" % i)
	get_tree().quit()
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
