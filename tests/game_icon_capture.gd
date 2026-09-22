extends Node
## Renders a close-up of the hero ball for the app icon (tools_run_test.sh) -> user://icon_capture.png
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	while game.state != 3:
		await get_tree().process_frame
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.hud.set_state({"visible": false})
	game.hud.show_hints = false
	game.tutorial.done = {"move": true, "keys": true, "arrows": true, "god": true}
	game.rig.target_zoom = 20.0
	game.rig.zoom = 20.0
	await _secs(4.0)
	var img := get_viewport().get_texture().get_image()
	var p: Vector2 = game.rig.cam.unproject_position(game._render_pos)
	var scale := img.get_size().x / get_viewport().get_visible_rect().size.x
	p *= scale
	var ppt: float = img.get_size().x / game.rig.zoom   # pixels per tile at the plane
	var half := int(ppt * 0.95)
	var r := Rect2i(int(p.x) - half, int(p.y) - half, half * 2, half * 2)
	var crop := img.get_region(r)
	crop.save_png("user://icon_capture.png")
	print("[icon] ball at %s, crop %s" % [p, r])
	get_tree().quit()
func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame
