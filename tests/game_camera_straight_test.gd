extends SceneTree
## Headless: the gameplay camera is EE-exact straight-on on every level: fov 34, identity rotation (no pitch/yaw),
## camera x/y exactly on the focus pivot. Run: $G --headless --audio-driver Dummy --path . -s res://tests/game_camera_straight_test.gd
const GameScript := preload("res://scripts/game/game.gd")
var fails := 0
func _init() -> void:
	_run()
func _run() -> void:
	for lv in ["odyssey", "forgotten_veil"]:
		GameScript.boot_options = {"skip_title": true, "no_save": true, "level": lv}
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		await game.ready_to_play
		game.input_provider = func(t: int) -> Dictionary: return {"right": t < 80, "jump": t > 20 and t < 30}
		for i in 150:
			await process_frame
		var cam: Camera3D = game.rig.cam
		var b := cam.global_transform.basis
		var ok: bool = is_equal_approx(cam.fov, 34.0) and b.is_equal_approx(Basis.IDENTITY) \
			and absf(cam.global_position.x - game.rig.focus.x) < 1e-4 and absf(cam.global_position.y - game.rig.focus.y) < 1e-4
		print("CAMERA %s %s: fov=%.1f basis_identity=%s cam=(%.3f,%.3f) focus=(%.3f,%.3f)" % [lv, "OK" if ok else "FAIL", cam.fov,
			b.is_equal_approx(Basis.IDENTITY), cam.global_position.x, cam.global_position.y, game.rig.focus.x, game.rig.focus.y])
		if not ok:
			fails += 1
		game.queue_free()
		await process_frame
	quit(fails)
