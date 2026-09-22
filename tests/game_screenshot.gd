extends Node
## Windowed screenshot tour of the shell: loading, title, gameplay, minimap, pause, settings.
## Run: $G --audio-driver Dummy --position 20000,20000 --path . res://tests/game_screenshot.tscn   -> user://game_*.png

const GameScript := preload("res://scripts/game/game.gd")
var game

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _wait(0.5)
	_shot("loading")
	await _wait(1.2)
	_shot("loading2")
	if game.state == 0:  # BOOT
		await game.booted
	await _wait(6.0)
	_shot("title")
	game.press_start()
	await _wait(1.0)
	_shot("intro")
	while game.state != 3:  # PLAYING
		await get_tree().process_frame
	game.input_provider = func(t: int) -> Dictionary:
		return {"right": t < 160, "jump": t > 60 and t < 80}
	await _wait(1.2)
	_shot("play")
	await _wait(2.0)
	_shot("play2")
	game.collision_overlay.visible = true
	game.collision_overlay.mark_dirty()
	await _wait(0.3)
	_shot("collision")
	game.collision_overlay.visible = false
	print("[shot] fps during play: ", Engine.get_frames_per_second())
	game.minimap.set_shown(true)
	await _wait(0.8)
	_shot("minimap")
	game.minimap.set_mode(Minimap.Mode.FULL)
	var f0 := Engine.get_process_frames()
	await _wait(0.8)
	print("[shot] frames during map open: ", Engine.get_process_frames() - f0, " full_a=", game.minimap._full_a, " zoom=", game.minimap._zoom)
	_shot("map_full")
	var f2 := Engine.get_process_frames()
	await _wait(1.5)
	print("[shot] frames after: ", Engine.get_process_frames() - f2, " zoom=", game.minimap._zoom)
	game.minimap._zoom_at(4.0, game.minimap._full_rect().get_center())
	await _wait(0.5)
	_shot("map_zoom")
	game.minimap.set_mode(Minimap.Mode.OFF)
	await _wait(0.3)
	# fly (god mode) into the Inferno to exercise zone cards / music crossfade / world atmosphere
	game.input_provider = func(_t: int) -> Dictionary:
		return {}
	game.sim.set_god_mode(true)
	for tile in [Vector2(140, 104), Vector2(320, 165)]:
		game.sim.px = tile.x * 16.0
		game.sim.py = tile.y * 16.0
		game.sim.prev_px = game.sim.px
		game.sim.prev_py = game.sim.py
		await _wait(2.2)
		_shot("zone_%d" % int(tile.x))
	game._pause()
	var f1 := Engine.get_process_frames()
	await _wait(0.6)
	print("[shot] frames during pause: ", Engine.get_process_frames() - f1)
	_shot("pause")
	game.pause_menu._on_settings()
	await _wait(0.4)
	_shot("settings")
	game._resume()
	get_tree().quit()

## Waits real time AND a minimum number of frames (a 4K screenshot readback stalls ~0.5 s, eating timer time).
func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://game_%s.png" % name)
	print("[shot] game_%s.png %s" % [name, img.get_size()])