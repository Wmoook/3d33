extends Node
## Probe: which action causes a long frame (pause tree / minimap corner / minimap full / pause menu)?
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	await _frames(60)
	await _probe("corner", func(): game.minimap.set_mode(Minimap.Mode.CORNER))
	await _probe("corner_off", func(): game.minimap.set_mode(Minimap.Mode.OFF))
	await _probe("tree_pause", func(): get_tree().paused = true)
	await _probe("tree_unpause", func(): get_tree().paused = false)
	await _probe("tree_pause2", func(): get_tree().paused = true)
	await _probe("tree_unpause2", func(): get_tree().paused = false)
	await _probe("full_map", func(): game.minimap.set_mode(Minimap.Mode.FULL))
	await _probe("full_off", func(): game.minimap.set_mode(Minimap.Mode.OFF))
	await _probe("pause_menu", func(): game._pause())
	await _probe("resume", func(): game._resume())
	get_tree().quit()
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _probe(label: String, f: Callable) -> void:
	f.call()
	var worst := 0
	var last := Time.get_ticks_usec()
	for i in 20:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	print("[probe] %-14s worst frame %.1f ms" % [label, worst / 1000.0])
