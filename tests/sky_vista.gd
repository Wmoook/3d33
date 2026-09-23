extends Node
## WorldVista check: boots Forgotten Veil in god mode, (attaches a WorldVista if WorldView doesn't create
## one yet), and saves user://sky_vista_<spot>.png from high, mid and low vantages + a GPU cost measure.
const GameScript := preload("res://scripts/game/game.gd")
var game
const SPOTS := {
	"spire_top": Vector2i(200, 30), "spiregap": Vector2i(222, 70), "falls": Vector2i(150, 140),
	"pool": Vector2i(150, 165), "logo": Vector2i(320, 45), "keep": Vector2i(300, 70), "grove_top": Vector2i(40, 30),
}
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	game.sim.set_god_mode(true)
	var wv = game.world
	var vista: WorldVista = wv.get_node_or_null("Vista")
	if vista == null:
		vista = WorldVista.new()
		vista.name = "Vista"
		wv.add_child(vista)
		vista.build(wv.level, wv.lights.moon.transform.basis.z, wv.atmosphere.sky_mat)
	var only := OS.get_cmdline_user_args()
	for n in SPOTS:
		if only.size() > 0 and not (n in only):
			continue
		var t: Vector2i = SPOTS[n]
		for i in 20:
			game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			game.sim.speed_x = 0.0; game.sim.speed_y = 0.0
			await get_tree().physics_frame
		await _wait(2.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://sky_vista_%s.png" % n)
		print("saved ", n, " cam ", get_viewport().get_camera_3d().global_position)
	# GPU cost of the vista at the last spot
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for on in [true, false, true, false]:
		vista.visible = on
		await _wait(0.4)
		var s := 0.0
		for i in 40:
			await RenderingServer.frame_post_draw
			s += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		print("GPU ms vista=%s: %.3f" % [str(on), s / 40.0])
	get_tree().quit()
func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
