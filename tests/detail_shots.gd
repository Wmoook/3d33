extends Node
## Surface-detail check in the REAL game: patches terrain.gdshader at runtime with the pbr_detail include
## (the same lines proposed to world), adds WorldGrass / WorldFoliage, teleports (god mode) and saves
## user://detail_<level>_<spot><tag>.png.
## Args (after --): level=forgotten_veil|odyssey  only=a,b  tag=x  pbr=0|1  grass=0|1  leaves=0|1  zoom=30
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS_FV := [
	["spawn", Vector2(6, 56)],
	["lawn", Vector2(2, 57)],
	["grove", Vector2(30, 44)],
	["ruins", Vector2(40, 92)],
	["spire", Vector2(200, 30)],
	["falls", Vector2(140, 150)],
	["keep", Vector2(300, 88)],
	["shrine", Vector2(388, 73)],
	["eastwood", Vector2(380, 96)],
]
const SPOTS_OD := [
	["surface", Vector2(60, 14)],
	["earth", Vector2(120, 50)],
	["cave", Vector2(210, 110)],
]
var game
var args := {"level": "forgotten_veil", "only": "", "tag": "", "pbr": "1", "grass": "1", "leaves": "1", "zoom": "30", "hud": "0"}

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": args.level, "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	var wv: WorldView = game.world
	var t0 := Time.get_ticks_msec()
	if args.pbr == "1":
		_patch_terrain(wv)
	var t1 := Time.get_ticks_msec()
	var grass: Node3D = null
	var foliage: Node3D = null
	if args.grass == "1":
		grass = WorldGrass.new()
		grass.name = "Grass2"
		wv.add_child(grass)
		grass.build(wv.level, wv.terrain)
		_hide_decor(wv, "Grass")
	var t2 := Time.get_ticks_msec()
	if args.leaves == "1":
		foliage = WorldFoliage.new()
		foliage.name = "Foliage2"
		wv.add_child(foliage)
		foliage.build(wv.level, wv.terrain)
	var t3 := Time.get_ticks_msec()
	print("detail: pbr patch %d ms, grass %d ms, foliage %d ms" % [t1 - t0, t2 - t1, t3 - t2])
	if grass:
		print("grass stats ", grass.stats)
	if foliage:
		print("foliage stats ", foliage.stats)
	if args.has("probe"):
		_probe(wv.terrain, args.probe)
	if args.hud != "1" and game.get("_ui"):
		game._ui.visible = false
	game.sim.set_god_mode(true)
	var spots: Array = SPOTS_FV if args.level == "forgotten_veil" else SPOTS_OD
	var only: PackedStringArray = args.only.split(",", false)
	for s in spots:
		if not only.is_empty() and not only.has(s[0]):
			continue
		var t: Vector2 = s[1]
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		if game.rig:
			game.rig.set("target_zoom", float(args.zoom)); game.rig.set("zoom", float(args.zoom))
		await _wait(1.6)
		var ball := Vector3(t.x + 0.5, -t.y - 0.5, 0.0)
		if grass:
			grass.update_focus(ball, 0.016)
		if foliage:
			foliage.update_focus(ball, 0.016)
		for i in 3:
			await get_tree().process_frame
		var lv := "fv" if args.level == "forgotten_veil" else "od"
		get_viewport().get_texture().get_image().save_png("user://detail_%s_%s%s.png" % [lv, s[0], args.tag])
		print("saved detail_", lv, "_", s[0], args.tag, "  fps ", Engine.get_frames_per_second())
	get_tree().quit()

func _hide_decor(wv: WorldView, nm: String) -> void:
	if wv.decor and wv.decor.has_node(nm):
		(wv.decor.get_node(nm) as Node3D).visible = false

## The integration patch proposed to world, applied to a copy of the terrain shader.
func _patch_terrain(wv: WorldView) -> void:
	var mat: ShaderMaterial = wv.terrain.material
	var code: String = mat.shader.code.replace("\r\n", "\n")
	if code.find("// DETAIL-PATCH #include") >= 0:
		# world applied the patch commented out: switch it on
		code = code.replace('// DETAIL-PATCH #include', '#include')
		var rx := RegEx.new()
		rx.compile("float pbr_k = 0\\.0;\\s*// DETAIL-PATCH: ([^\\n]*)")
		code = rx.sub(code, "float pbr_k = $1", true)
	elif code.find("pbr_detail.gdshaderinc") < 0:
		code = code.replace('#include "res://shaders/world/terrain_common.gdshaderinc"',
			'#include "res://shaders/world/terrain_common.gdshaderinc"
#include "res://shaders/world/pbr_detail.gdshaderinc"')
		var anchor := "	if (layer == 0) {
		// soft rim of the bevel"
		assert(code.find(anchor) >= 0, "anchor 1 missing")
		code = code.replace(anchor, "	float pbr_k = (layer == 2) ? 0.0 : pbr_terrain(mat, wp, gn, p, CAMERA_POSITION_WORLD, albedo, n, rough, ao);
" + anchor)
		var a2 := "if (mat != M_WATER && mat != M_ICE && mat != M_GLASS && mat != M_GEM && mat != M_OBSIDIAN && mat != M_MARBLE) {"
		assert(code.find(a2) >= 0, "anchor 2 missing")
		code = code.replace(a2, "if (pbr_k < 0.5 && mat != M_WATER && mat != M_ICE && mat != M_GLASS && mat != M_GEM && mat != M_OBSIDIAN && mat != M_MARBLE) {")
	assert(code.find("pbr_k = (layer") >= 0, "pbr call missing")
	var sh := Shader.new()
	sh.code = code
	mat.shader = sh
	WorldPbr.bind(mat, WorldPalette.is_odyssey(), 1.0, wv.terrain)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout
	for i in int(s * 40.0):
		await get_tree().process_frame

## ASCII map of a rect "x0,y0,x1,y1": C canopy, g ground-grass top, f foliage, w wood, e earth, # other, . air
func _probe(t: WorldTerrain, r: String) -> void:
	var v := r.split(",")
	var W := t.W
	for y in range(int(v[1]), int(v[3])):
		var line := "%3d " % y
		for x in range(int(v[0]), int(v[2])):
			var i := y * W + x
			var ch := "."
			if t.solid[i]:
				var m: int = t.mat_ids[i]
				if WorldGrass.is_leafy(m):
					ch = "C" if WorldGrass.canopy_column(t, x, y, W, t.H) else "f"
					if ch == "f" and not t.solid[i - W]:
						ch = "g"
				elif m == WorldPalette.M_WOOD:
					ch = "w"
				elif m == WorldPalette.M_EARTH:
					ch = "e"
				else:
					ch = "#"
			line += ch
		print(line)
	var hist := {}
	for y in range(int(v[1]), int(v[3])):
		for x in range(int(v[0]), int(v[2])):
			var i := y * W + x
			if t.solid[i]:
				var k := "%d/m%d" % [t.level.fg[i], t.mat_ids[i]]
				hist[k] = hist.get(k, 0) + 1
	print("ids ", hist)
