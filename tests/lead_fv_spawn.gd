extends Node
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	await _wait(3.0)
	get_viewport().get_texture().get_image().save_png("user://lead_fv_spawn.png")
	get_tree().quit()
func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
