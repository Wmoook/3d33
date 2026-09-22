extends Node
## Actors verification inside the REAL game (main.tscn + shell + world + physics): god-mode teleports the
## ball to key spots and saves user://fx_game_<name>.png.  Args: -- only=<name>
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [
	["canopy", Vector2(29, 9)],
	["redkeys", Vector2(110, 62)],
	["tornado", Vector2(36, 124)],
	["arrowline", Vector2(388, 18)],
	["dots", Vector2(262, 152)],
	["spawn", Vector2(65, 11)],
	["dot92", Vector2(90, 13)],
	["lake", Vector2(330, 186)],
	["inferno", Vector2(150, 110)],
	["inferno_nooverlay", Vector2(150, 110)],
	["ghost", Vector2(66, 11)],
]
var ghost: Node3D
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.booted
	await _wait(1.0)
	game.press_start()
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	game.sim.set_god_mode(true)
	for s in SPOTS:
		if only != "" and only != s[0]:
			continue
		var t: Vector2 = s[1]
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		game.actors.overlays.visible = s[0] != "inferno_nooverlay"
		if s[0] == "ghost" and ghost == null:
			ghost = game.actors.create_ghost_ball()
			game.actors.get_parent().add_child(ghost)
		await _wait(2.0)
		get_viewport().get_texture().get_image().save_png("user://fx_game_%s.png" % s[0])
		print("saved fx_game_", s[0])
	get_tree().quit()
func _process(delta: float) -> void:
	if ghost:
		ghost.update_ghost(EECoords.player_center(game.sim.px - 40.0, game.sim.py), game.sim, delta)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
