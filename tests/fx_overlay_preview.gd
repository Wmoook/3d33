extends Node3D
## Hero FX overlays over the REAL WorldView. Saves user://fx_ov_<name>.png per spot, then quits.
## $G --path C:/Users/super/ex-odyssey res://tests/fx_overlay_preview.tscn  [-- only=<name>]

var lvl: EELevel
var sim: FxMockSim
var world: WorldView
var actors: ActorsView
var cam: Camera3D
var ball := Vector3.ZERO
var only := ""

const SPOTS := [
	["skullpit", Vector2(140, 108), 40.0],
	["skullpit_close", Vector2(150, 118), 22.0],
	["demonlake", Vector2(325, 183), 40.0],
	["lake_close", Vector2(345, 188), 22.0],
	["tornado", Vector2(24, 108), 48.0],
	["icecavern", Vector2(330, 140), 40.0],
	["braziers", Vector2(220, 176), 30.0],
	["righthalls", Vector2(335, 92), 40.0],
	["upperlake", Vector2(216, 52), 40.0],
	["corruption", Vector2(210, 100), 40.0],
]

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	lvl = EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	sim = FxMockSim.new(lvl)
	world = WorldView.new()
	add_child(world)
	world.build(lvl)
	world.set_sim(sim)
	if "flames" in world and world.flames != null and not OS.get_cmdline_user_args().has("worldflames"):
		world.flames.visible = false   # judge the actors fire alone (see coordination with world)
	actors = ActorsView.new()
	add_child(actors)
	actors.build(lvl, sim)
	var args := OS.get_cmdline_user_args()
	actors.player.visible = false   # overlays only; the ball would sit inside terrain at these spots
	if args.has("nofield"):
		actors.overlays.get_node("OverlayField").visible = false
	if args.has("noflames"):
		for c in actors.overlays._flame_chunks:
			c.node.queue_free()
		actors.overlays._flame_chunks.clear()
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 500.0
	add_child(cam)
	cam.make_current()
	_run.call_deferred()

func _process(delta: float) -> void:
	world.update_focus(ball, delta)
	actors.update_player(ball, sim, delta)

func _look(t: Vector2, width: float) -> void:
	var half_h := width / (16.0 / 9.0) * 0.5
	var d := half_h / tan(deg_to_rad(cam.fov * 0.5))
	cam.position = Vector3(t.x, -t.y, d)
	ball = Vector3(t.x + 3.0, -t.y, 0.0)   # keep the ball out of the way (focus follows it)

func _run() -> void:
	for s in SPOTS:
		if only != "" and only != s[0]:
			continue
		_look(s[1], s[2])
		for i in 90:
			await get_tree().process_frame
		# GPU cost of the overlays: average viewport GPU time with overlays on vs hidden
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		var on_ms := 0.0
		var off_ms := 0.0
		for i in 30:
			await RenderingServer.frame_post_draw
			on_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		actors.overlays.visible = false
		for i in 30:
			await RenderingServer.frame_post_draw
			off_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		actors.overlays.visible = true
		for i in 5:
			await get_tree().process_frame
		print("GPU ms %s: with overlays %.2f, without %.2f, overlay cost %.2f" % [s[0], on_ms / 30.0, off_ms / 30.0, (on_ms - off_ms) / 30.0])
		await RenderingServer.frame_post_draw
		var suffix := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("tag="):
				suffix = "_" + a.substr(4)
		get_viewport().get_texture().get_image().save_png("user://fx_ov_%s%s.png" % [s[0], suffix])
		print("saved fx_ov_", s[0], "  fps=", Engine.get_frames_per_second())
	get_tree().quit()
