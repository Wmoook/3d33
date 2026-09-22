extends Node
## Actors GPU / primitive cost in the REAL game at a few spots, with sub-systems toggled.
const GameScript := preload("res://scripts/game/game.gd")
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
	game.sim.set_god_mode(true)
	var a: ActorsView = game.actors
	for spot in [["inferno", Vector2(150, 110)], ["spawn", Vector2(65, 11)]]:
		var t: Vector2 = spot[1]
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		await _wait(2.0)
		var base := await _measure()
		var cases := {
			"all_actors": [a],
			"overlays": [a.overlays],
			"blocks": [a.blocks],
			"life": [a.life],
			"player": [a.player],
		}
		print("== ", spot[0], " base gpu %.2f ms prims %.1fM draws %d" % base)
		for k in cases:
			for n in cases[k]: n.visible = false
			var m := await _measure()
			for n in cases[k]: n.visible = true
			print("   hide %-10s  -> gpu %.2f (%+.2f)  prims %.1fM (%+.1fM)  draws %d (%+d)" % [k, m[0], m[0] - base[0], m[1], m[1] - base[1], m[2], m[2] - base[2]])
		var sh: bool = a.player._env_light.shadow_enabled
		a.player._env_light.shadow_enabled = false
		var m2 := await _measure()
		a.player._env_light.shadow_enabled = sh
		print("   ball light shadow off -> gpu %.2f (%+.2f)  prims %.1fM (%+.1fM)" % [m2[0], m2[0] - base[0], m2[1], m2[1] - base[1]])
	get_tree().quit()

func _measure() -> Array:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 10:
		await RenderingServer.frame_post_draw
	var g := 0.0
	var p := 0.0
	var d := 0.0
	for i in 30:
		await RenderingServer.frame_post_draw
		g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		p += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		d += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	return [g / 30.0, p / 30.0 / 1e6, int(d / 30.0)]

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
