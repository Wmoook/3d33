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
	["lake_close", Vector2(330, 186)],
	["inferno", Vector2(150, 110)],
	["inferno_nooverlay", Vector2(150, 110)],
	["ghost", Vector2(66, 11)],
	["keytouch", Vector2(89, 10)],
	["cave_shadow_on", Vector2(216, 69)],
	["cave_shadow_off", Vector2(216, 69)],
	["cave_diag_on", Vector2(216, 69)],
	["cave_diag_off", Vector2(216, 69)],
	["hc_off", Vector2(262, 150)],
	["hc_on", Vector2(262, 150)],
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
	var only: PackedStringArray = []
	var tag := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
		if a.begins_with("tag="):
			tag = "_" + a.substr(4)
	game.sim.set_god_mode(true)
	for s in SPOTS:
		if not only.is_empty() and not only.has(s[0]):
			continue
		var t: Vector2 = s[1]
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		game.actors.overlays.visible = s[0] != "inferno_nooverlay"
		game.actors.set_high_contrast(s[0] == "hc_on")
		game.actors.set_ball_shadows(not s[0].ends_with("_off") or not s[0].begins_with("cave"))
		if s[0].begins_with("cave_diag"):
			game.actors.player._halo.visible = false
			game.world.lights.visible = false   # isolate the ball light
		if s[0] == "ghost" and ghost == null:
			ghost = game.actors.create_ghost_ball()
			game.actors.get_parent().add_child(ghost)
		await _wait(2.0)
		if s[0] == "lake_close" and game.rig:
			game.rig.set("zoom", 2.0)
		if s[0] == "keytouch":
			game.sim.sim_event.emit(&"key", {"color": &"red", "tile": Vector2i(86, 12)})
			for i in 8:
				await get_tree().process_frame
		if s[0].begins_with("cave"):
			var L: OmniLight3D = game.actors.player._env_light
			if s[0].begins_with("cave_diag"):
				L.light_energy = 6.0
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
			print("ball light shadow=", L.shadow_enabled, " energy=", L.light_energy, " range=", L.omni_range, " mask=", L.shadow_caster_mask, " cull=", L.light_cull_mask)
		get_viewport().get_texture().get_image().save_png("user://fx_game_%s%s.png" % [s[0], tag])
		print("saved fx_game_", s[0])
	get_tree().quit()
func _process(delta: float) -> void:
	if ghost:
		ghost.update_ghost(EECoords.player_center(game.sim.px - 40.0, game.sim.py), game.sim, delta)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
