extends Node
## Prints each trial's number and coin tile (play order from the route survey), then quits.
const GameScript := preload("res://scripts/game/game.gd")

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 1, "level": "forgotten_veil", "skip_title": true}
	var game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	var tr: WorldTrials = game.world.trials
	for k in tr.coins.size():
		print("TRIAL %d coin %s map=%d" % [k + 1, tr.coins[k], tr.get_trial_at(tr.coins[k])])
	print("cave (43,64) -> trial %d" % tr.get_trial_at(Vector2i(43, 64)))
	get_tree().quit()
