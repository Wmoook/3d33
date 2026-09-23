extends Node
## Open coin doors in context (FV, 99 coins): shots of door 212/223 with actors' door parts toggled, to find
## what draws inside an open frame. Env HIDE = comma list of node-name prefixes under InteractiveBlocks.
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	game.sim.coins = 99
	var hide := OS.get_environment("HIDE").split(",", false)
	for c in game.actors.blocks.get_children():
		for h in hide:
			if String(c.name).begins_with(h) or (h == "all" and c is GeometryInstance3D):
				c.visible = false
	for spot in [["212", Vector2(215, 191)], ["223", Vector2(225, 182)]]:
		var t: Vector2 = spot[1]
		for i in 25:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			await get_tree().physics_frame
		await _wait(1.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://fx_coindoor_open_%s%s.png" % [spot[0], OS.get_environment("TAG")])
		print("saved ", spot[0])
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
