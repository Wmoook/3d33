extends SceneTree
## Headless: the coin-door pill tracks sim.coins live and flips to "COIN DOOR OPEN" then hides.
const GameScript := preload("res://scripts/game/game.gd")
var game
func _init() -> void:
	GameScript.boot_options = {"skip_title": true, "no_save": true, "level": "forgotten_veil"}
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.ready_to_play.connect(_run)
func _run() -> void:
	await _frames(5)
	game._door_toast_need = 16
	game.hud.toast("COIN DOOR", game._door_toast_text(), 5.0)
	game.sim.coins = 7
	await _frames(3)
	var t1: String = game.hud._toast_text
	game.sim.coins = 16
	await _frames(3)
	var t2: String = game.hud._toast_title
	var t0 := Time.get_ticks_msec()
	while game.hud.toast_active() and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	var hid_ms := Time.get_ticks_msec() - t0
	var ok: bool = t1.ends_with("you have 7") and t2 == "COIN DOOR OPEN" and hid_ms < 2500
	print("COINDOOR %s: '%s' -> '%s', hidden after %d ms" % ["OK" if ok else "FAIL", t1, t2, hid_ms])
	quit(0 if ok else 1)
func _frames(n: int) -> void:
	for i in n:
		await process_frame
