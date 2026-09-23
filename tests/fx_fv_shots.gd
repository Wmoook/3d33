extends Node
## Forgotten Veil actors/VFX check inside the REAL game (main.tscn, level "forgotten_veil"): god mode
## teleports the ball to key spots and saves user://fx_fv_<name>.png.  Args: -- only=a,b  tag=x
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS := [
	["spawn", Vector2(2, 56)],
	["falls", Vector2(128, 150)],
	["pool", Vector2(148, 166)],
	["switch_off", Vector2(195, 41)],
	["switch_on", Vector2(195, 41)],
	["boost", Vector2(300, 131)],
	["piano", Vector2(393, 30)],
	["piano_hit", Vector2(393, 30)],
	["magenta", Vector2(214, 41)],
	["coindoor", Vector2(50, 53)],
	["coins", Vector2(23, 68)],
	["coin_collect", Vector2(23, 68)],
	["bluecoin", Vector2(202, 23)],
	["bats", Vector2(330, 150)],
	["invisible", Vector2(186, 113)],
	["forest", Vector2(40, 46)],
	["spire", Vector2(200, 30)],
	["channels", Vector2(230, 190)],
	["finish", Vector2(392, 74)],
	["ruins", Vector2(40, 92)],
	["vines_spire", Vector2(190, 60)],
	["vine_part", Vector2(190, 60)],
	["grove_dapple", Vector2(30, 40)],
	["grove_nodapple", Vector2(30, 40)],
	["falls_glint", Vector2(140, 160)],
	["shrine", Vector2(388, 73)],
	["shrine_nopillar", Vector2(388, 73)],
	["shrine_none", Vector2(388, 73)],
	["crowning_a", Vector2(391, 73)],
	["crowning_b", Vector2(391, 73)],
	["crowning_c", Vector2(391, 73)],
	["scroll", Vector2(372, 30)],
	["scroll_noink", Vector2(372, 30)],
	["scroll_far", Vector2(372, 30)],
	["logo", Vector2(322, 28)],
	["veils", Vector2(245, 84)],
	["rainbow", Vector2(141, 164)],
	["updraft", Vector2(200, 64)],
	["aqueduct", Vector2(360, 180)],
	["sky_birds", Vector2(20, 12)],
	["qa_bridges", Vector2(225, 64)],
	["qa_keep", Vector2(300, 90)],
	["qa_hall", Vector2(350, 95)],
	["qa_sanctum", Vector2(300, 140)],
	["qa_halls", Vector2(85, 90)],
]
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil"}
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
		if s[0] == "vine_part" and game.actors.vines:
			# park the ball on the vine anchor nearest the spot, a bit below it, so it pushes the strand aside
			var best := Vector3.ZERO
			var bd := INF
			for v: Vector3 in game.actors.vines._sites:
				var d := Vector2(v.x, -v.y).distance_to(t)
				if d < bd:
					bd = d
					best = v
			game.sim.px = (best.x - 0.5) * 16.0; game.sim.py = (-best.y + 1.0) * 16.0
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		if s[0] == "switch_on":
			game.sim._switches[1] = true
			game.sim.sim_event.emit(&"switch", {"kind": &"purple", "id": 1, "on": true})
		await _wait(2.0)
		if game.actors.veil and s[0] == "grove_nodapple":
			for dp in game.actors.veil._dapples:
				dp.node.visible = false
			for i in 3:
				await get_tree().process_frame
		if s[0].begins_with("shrine_") and game.actors.shrine:
			var r: Node3D = game.actors.shrine._shrines[0].root
			r.get_node("LightPillar").visible = false
			if s[0] == "shrine_none":
				r.visible = false
			for i in 3:
				await get_tree().process_frame
		if s[0] == "sky_birds" and game.actors.day_life:
			print("glide sites ", game.actors.day_life._glide_sites.size(), " gliders ", game.actors.day_life._gliders.size(), " first ", game.actors.day_life._glide_sites.slice(0, 4))
		if s[0] == "scroll_noink":
			for n in game.actors.blocks.find_children("InkLetters", "", false, false):
				n.visible = false
			for i in 3:
				await get_tree().process_frame
		if game.rig and s[0] != "scroll_far":
			game.rig.set("target_zoom", 30.0)
		if s[0] == "scroll_far" and game.rig:
			game.rig.set("target_zoom", 70.0); game.rig.set("zoom", 70.0)
			await _wait(1.5)
		if s[0].begins_with("crowning"):
			while game.actors.shrine._crowning >= 0.0:
				await get_tree().process_frame
			game.sim.set("has_silver_crown", false)
			game.actors.shrine.reset_if_needed()   # as after a restart
			game.sim.set("has_silver_crown", true)
			game.actors._on_sim_event(&"complete", {"tile": Vector2i(394, 74)})
			var wait: float = {"crowning_a": 0.9, "crowning_b": 2.3, "crowning_c": 3.4}[s[0]]
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < int(wait * 1000.0):
				await get_tree().process_frame
			print("crowning t=", game.actors.shrine._crowning, " crown vis=", game.actors.shrine._shrines[0].crown.visible, " at ", game.actors.shrine._shrines[0].crown.global_position)
		if s[0] == "piano_hit":
			for k in 4:
				var pt := Vector2i(396 + (k % 2), 27 + k * 2)
				game.sim.sim_event.emit(&"piano", {"tile": pt, "note": game.sim.get_tile_number(pt.x, pt.y)})
				for i in 5:
					await get_tree().process_frame
		if s[0] == "coin_collect":
			game.sim.sim_event.emit(&"coin", {"tile": Vector2i(26, 70)})
			for i in 14:
				await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://fx_fv_%s%s.png" % [s[0], tag])
		print("saved fx_fv_", s[0])
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame
