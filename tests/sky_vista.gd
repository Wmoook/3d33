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
	if "diag" in only:
		await _diag(wv)
		get_tree().quit()
		return
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

func _diag(wv) -> void:
	for c in wv.get_children():
		print("WV child ", c.name, " ", c.get_class(), " kids=", c.get_child_count())
		for g in c.get_children():
			if g is GeometryInstance3D:
				var gi: GeometryInstance3D = g
				var ab := gi.get_aabb() if gi is VisualInstance3D else AABB()
				print("   ", g.name, " ", g.get_class(), " vis=", gi.visible, " aabb_z=", ab.position.z, "..", ab.end.z)
	var t: Vector2i = SPOTS["falls"]
	for i in 20:
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		await get_tree().physics_frame
	await _wait(2.0)
	var env: Environment = wv.get_environment()
	print("env fog=", env.fog_enabled, " vfog=", env.volumetric_fog_enabled, " dens=", env.volumetric_fog_density, " expo=", env.tonemap_exposure, " sat=", env.adjustment_saturation, " glow=", env.glow_intensity)
	await _shot("diag_base")
	env.volumetric_fog_enabled = false
	await _shot("diag_novfog")
	env.fog_enabled = false
	env.glow_enabled = false
	await _shot("diag_noglow")
	var ca = get_viewport().get_camera_3d().attributes
	print("cam attrs ", ca)
	if ca:
		ca.set("dof_blur_far_enabled", false)
	await _shot("diag_nodof")

func _shot(n: String) -> void:
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://sky_vista_%s.png" % n)
