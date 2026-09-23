extends Node
## FV background overhaul shots at zoom 30: user://bgov_<spot>_<tag>.png (tag = env BG_TAG, default "cur").
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := {"shaft": Vector2(43, 64), "grove_hollow": Vector2(50, 52), "west_halls": Vector2(30, 95),
	"sanctum": Vector2(250, 112), "earth_cave": Vector2(45, 162), "great_hall": Vector2(350, 90),
	"aqueduct_cave": Vector2(330, 168), "twin": Vector2(248, 86)}
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	await _wait(8.0)
	var tag := OS.get_environment("BG_TAG")
	if tag == "":
		tag = "cur"
	var only := OS.get_cmdline_user_args()
	for n in SPOTS:
		if not only.is_empty() and not only.has(n):
			continue
		var t: Vector2 = SPOTS[n]
		for i in 30:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			await get_tree().physics_frame
		await _wait(1.5)
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		im.resize(im.get_width() / 2, im.get_height() / 2)
		im.save_png("user://bgov_%s_%s.png" % [n, tag])
	print("bg shots done")
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
