extends SceneTree
## Headless: C overview toggle eases to ~2.5x the visible width and back, never touching the saved zoom.
## Run: $G --headless --audio-driver Dummy --path . -s res://tests/game_overview_test.gd
const GameScript := preload("res://scripts/game/game.gd")
var game
func _init() -> void:
	GameScript.boot_options = {"skip_title": true, "no_save": true}
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.ready_to_play.connect(_run)
func _run() -> void:
	await _frames(20)
	var z0: float = game.rig.zoom
	var saved: float = game.settings.zoom
	var ev := InputEventAction.new()
	game.toggle_overview()
	await _frames(400)
	var z1: float = game.rig.zoom
	game.toggle_overview()
	await _frames(400)
	var z2: float = game.rig.zoom
	var ok: bool = absf(z1 - minf(z0 * 2.5, 160.0)) < 1.0 and absf(z2 - z0) < 0.5 and game.settings.zoom == saved \
		and InputMap.action_has_event(&"ee_overview", _key_c())
	print("OVERVIEW %s: zoom %.1f -> %.1f -> %.1f (saved zoom %.1f unchanged: %s)" % ["OK" if ok else "FAIL", z0, z1, z2, saved, game.settings.zoom == saved])
	quit(0 if ok else 1)
func _key_c() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_C
	return e
func _frames(n: int) -> void:
	for i in n:
		await process_frame
