extends Node
## Visual checks (tools_run_test.sh): title flyover along the route at 3 moments (one right after a portal
## cut), and the high-contrast glyph toggle off/on at the same spot. Output: user://vis_*.png
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 1:
		await get_tree().process_frame
	var keys: Array = game.rig._cine_keys
	await _secs(5.0)
	_shot("vis_flyover_a")
	game.rig._cine_s = keys.size() * 0.45
	await _secs(1.5)
	_shot("vis_flyover_b")
	var cut_i := -1
	for i in keys.size():
		if keys[i].get("cut", false):
			cut_i = i
			break
	if cut_i > 0:
		game.rig._cine_s = cut_i - 0.2
		await _secs(3.5)   # crosses the cut (dip to black) and settles
		_shot("vis_flyover_cut")
		print("[vis] cut key %d at %s" % [cut_i, keys[cut_i].pos])
	game.press_start()
	while game.state != 3:
		await get_tree().process_frame
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.hud.show_hints = false
	game.tutorial.done = {"move": true, "keys": true, "arrows": true, "god": true}
	await _secs(2.5)
	game._on_setting_changed("high_contrast", false)
	await _secs(0.5)
	_shot("vis_contrast_off")
	game._on_setting_changed("high_contrast", true)
	await _secs(0.5)
	_shot("vis_contrast_on")
	game._on_setting_changed("high_contrast", false)
	get_tree().quit()
func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % n)
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
