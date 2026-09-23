extends Node
## GPU cost of the surface-detail layer in the real game (Forgotten Veil): per spot, measures the average
## GPU frame time with (a) nothing, (b) PBR terrain, (c) + WorldGrass, (d) + WorldFoliage.
## Args (after --): only=a,b  zoom=30  frames=90
const GameScript := preload("res://scripts/game/game.gd")
const Shots := preload("res://tests/detail_shots.gd")
const SPOTS := [
	["spawn", Vector2(6, 56)],
	["grove", Vector2(30, 44)],
	["eastwood", Vector2(380, 96)],
	["falls", Vector2(140, 150)],
	["grove_far", Vector2(40, 45)],
]
var game
var args := {"only": "", "zoom": "30", "frames": "90"}

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	var wv: WorldView = game.world
	var mat: ShaderMaterial = wv.terrain.material
	var sh_orig: Shader = mat.shader
	var patcher = Shots.new()
	patcher._patch_terrain(wv)
	var sh_pbr: Shader = mat.shader
	var grass := WorldGrass.new()
	wv.add_child(grass)
	grass.build(wv.level, wv.terrain)
	var foliage := WorldFoliage.new()
	wv.add_child(foliage)
	foliage.build(wv.level, wv.terrain)
	patcher.free()
	var decor_grass: Node3D = wv.decor.get_node_or_null("Grass") if wv.decor else null
	game._ui.visible = false
	game.sim.set_god_mode(true)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("viewport ", get_viewport().get_visible_rect().size)
	var only: PackedStringArray = args.only.split(",", false)
	for s in SPOTS:
		if not only.is_empty() and not only.has(s[0]):
			continue
		var t: Vector2 = s[1]
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		var z := 60.0 if s[0].ends_with("_far") else float(args.zoom)
		game.rig.set("target_zoom", z); game.rig.set("zoom", z)
		await _frames(60)
		var res := {}
		for mode in ["base", "pbr", "grass", "leaves"]:
			mat.shader = sh_orig if mode == "base" else sh_pbr
			grass.visible = mode == "grass" or mode == "leaves"
			foliage.visible = mode == "leaves"
			if decor_grass:
				decor_grass.visible = not grass.visible
			await _frames(20)
			var acc := 0.0
			var n := int(args.frames)
			for i in n:
				await get_tree().process_frame
				acc += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			res[mode] = acc / n
		print("PERF %-10s base %.2f ms | pbr +%.2f | grass +%.2f | leaves +%.2f | total +%.2f ms" % [s[0], res.base,
			res.pbr - res.base, res.grass - res.pbr, res.leaves - res.grass, res.leaves - res.base])
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
