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
	["keeproom", Vector2(308, 95)],
	["hollow", Vector2(30, 54)],
	["pine", Vector2(62, 50)],
	["spawn2", Vector2(2, 56)],
	["walkstart", Vector2(14, 56)],
	["walk8", Vector2(8, 56)],
	["user7", Vector2(11, 56)],
	["far_grove", Vector2(35, 50)],
	["far_keep", Vector2(320, 100)],
	["far_east", Vector2(385, 100)],
	["easthollow", Vector2(382, 104)],
	["outside_grove", Vector2(20, 68)],
	["outside_east", Vector2(96, 50)],
	["canopytop", Vector2(30, 36)],
	["shrine", Vector2(388, 73)],
	["eastwood", Vector2(380, 96)],
]
const SPOTS_OD := [
	["surface", Vector2(60, 14)],
	["earth", Vector2(120, 50)],
	["cave", Vector2(210, 110)],
]
var game
var forest_node: Node3D = null
var args := {"level": "forgotten_veil", "only": "", "tag": "", "pbr": "1", "grass": "1", "leaves": "1", "zoom": "30", "hud": "1"}

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
	elif wv.terrain.material.get_shader_parameter("pbr_strength") != null:
		wv.terrain.material.set_shader_parameter("pbr_strength", 0.0)
	var t1 := Time.get_ticks_msec()
	var grass: Node3D = null
	var foliage: Node3D = null
	var live: bool = wv.get("grass") != null   # world wired the detail layer in itself
	if live:
		grass = wv.grass
		foliage = wv.foliage
		print("detail: live integration (world_view builds grass + foliage)")
	if args.grass == "1" and not live:
		grass = WorldGrass.new()
		grass.name = "Grass2"
		wv.add_child(grass)
		grass.build(wv.level, wv.terrain)
		_hide_decor(wv, "Grass")
	var t2 := Time.get_ticks_msec()
	if args.leaves == "1" and not live:
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
	if live:
		grass.visible = args.grass == "1"
		foliage.visible = args.leaves == "1"
	if args.get("forest", "0") == "1":
		_build_forest(wv)
	if args.get("depth", "0") == "1":
		_build_depth_stub(wv)
	if args.has("hide"):
		for nm: String in str(args.hide).split(","):
			var nd: Node = wv.get_node_or_null(nm)
			if nd == null:
				nd = game.find_child(nm, true, false)
			if nd is Node3D:
				(nd as Node3D).visible = false
	if args.has("tileinfo"):
		var v := str(args.tileinfo).split(",")
		var ti := int(v[1]) * wv.terrain.W + int(v[0])
		print("TILE ", v, " fg ", wv.level.fg[ti], " bg ", wv.level.bg[ti], " solid ", wv.terrain.solid[ti], " pocket ", wv.terrain.pocket[ti], " mat ", wv.terrain.mat_ids[ti], " hollow ", WorldForest.hollow_mask(wv.terrain)[ti], " wall_code ", wv.terrain.wall_code[ti] if wv.terrain.wall_code.size() > ti else -1)
	if args.has("tree"):
		for c in wv.get_children():
			print("WV ", c.name, " ", c.get_class())
		for c in game.get_children():
			print("TREE ", c.get_path(), " ", c.get_class())
			for c2 in c.get_children():
				print("TREE   ", c2.name, " ", c2.get_class())
	if args.has("findat"):
		var v := str(args.findat).split(",")
		_find_at(Vector2(float(v[0]), float(v[1])), float(v[2]) if v.size() > 2 else 1.2)
	if args.get("nolightfade", "0") == "1":
		var nl := 0
		for n in get_tree().root.find_children("*", "Light3D", true, false):
			(n as Light3D).distance_fade_enabled = false
			nl += 1
		print("light distance fade off on ", nl, " lights")
	if args.get("nossao", "0") == "1":
		var env: Environment = wv.get_environment()
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		print("ssao/ssil/sdfgi off")
	if args.has("debug"):
		wv.set_debug_mode(int(args.debug))
	if args.hud != "1" and game.get("_ui"):
		game._ui.visible = false
	game.sim.set_god_mode(true)
	var spots: Array = SPOTS_FV if args.level == "forgotten_veil" else SPOTS_OD
	if args.get("regions", "0") == "1":
		spots = []
		for r: Rect2i in WorldForest.regions(wv.terrain):
			# the lowest open floor tile near the region centre
			var c := Vector2i(r.position.x + r.size.x / 2, r.end.y - 2)
			spots.append(["region_%d_%d" % [r.position.x, r.position.y], Vector2(c)])
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
		var fnode: Node3D = forest_node if forest_node else wv.get("forest")
		if fnode:
			var fball := ball
			if args.has("fadefrom"):
				var fv := str(args.fadefrom).split(",")
				fball = Vector3(float(fv[0]) + 0.5, -float(fv[1]) - 0.5, 0.0)   # the player is elsewhere (zoomed-out view)
			for k in 4:
				fnode.update_focus(fball, 1.0)   # settle the region fades at this spot
		for i in 3:
			await get_tree().process_frame
		var lv := "fv" if args.level == "forgotten_veil" else "od"
		var shot := get_viewport().get_texture().get_image()
		shot.save_png("user://detail_%s_%s%s.png" % [lv, s[0], args.tag])
		print("saved detail_", lv, "_", s[0], args.tag, "  fps ", Engine.get_frames_per_second())
		if args.get("skycheck", "0") == "1":
			# measured without the HUD (its panels / titles are not the world)
			var ui_vis: bool = game._ui.visible
			game._ui.visible = false
			for i in 3:
				await get_tree().process_frame
			print("SKYCHECK %s: %s" % [s[0], str(_sky_check(get_viewport().get_texture().get_image(), wv))])
			game._ui.visible = ui_vis
		if args.get("walk", "0") == "1":
			if args.get("fly", "0") != "1":
				game.sim.set_god_mode(false)
			var wdir: String = args.get("walkdir", "right")
			game.input_provider = func(_t: int) -> Dictionary: return {wdir: true}
			for f in 3:
				for i in int(args.get("walkframes", "12")):
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://detail_%s_%s%s_walk%d.png" % [lv, s[0], args.tag, f])
			game.input_provider = func(_t: int) -> Dictionary: return {}
			game.sim.set_god_mode(true)
	get_tree().quit()

func _hide_decor(wv: WorldView, nm: String) -> void:
	if wv.decor and wv.decor.has_node(nm):
		(wv.decor.get_node(nm) as Node3D).visible = false

## The integration patch proposed to world, applied to a copy of the terrain shader.
func _patch_terrain(wv: WorldView) -> void:
	var mat: ShaderMaterial = wv.terrain.material
	var code: String = mat.shader.code.replace("\r\n", "\n")
	if code.find("pbr_k = (layer == 2) ? 0.0 : pbr_terrain(") >= 0 and code.find("DETAIL-PATCH") < 0:
		return   # live: world's shader already runs the detail library
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
			var ch := "." if not WorldForest.hollow_mask(t)[i] else "o"
			if not t.solid[i] and ch == "." and t.level.bg[i] in [0, 510, 511, 512, 534]:
				ch = "," if t.pocket[i] == 0 else ";"
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

## WorldDepthGreen against world's API if present (terrain.depth_top_y / depth_mat), else a stub surface:
## each sky-exposed column's top continued flat backward.
func _build_depth_stub(wv: WorldView) -> void:
	var t: WorldTerrain = wv.terrain
	var top_at: Callable
	var mat_at: Callable
	if t.has_method("depth_top_y") and t.has_method("depth_mat"):
		top_at = Callable(t, "depth_top_y")
		mat_at = Callable(t, "depth_mat")
		print("depth: using world's API")
	else:
		var tops := PackedInt32Array()
		tops.resize(t.W)
		for x in t.W:
			tops[x] = -1
			for y in t.H:
				if t.solid[y * t.W + x]:
					tops[x] = y
					break
		top_at = func(x: float, _z: float) -> float:
			var c := clampi(int(x), 0, t.W - 1)
			return NAN if tops[c] < 0 else -float(tops[c])
		mat_at = func(x: float, _z: float) -> int:
			var c := clampi(int(x), 0, t.W - 1)
			return -1 if tops[c] < 0 else int(t.mat_ids[tops[c] * t.W + c])
		print("depth: stub surface")
	var t0 := Time.get_ticks_msec()
	var g := WorldDepthGreen.new()
	g.name = "DepthGreen"
	wv.add_child(g)
	g.build_depth(wv.level, t, top_at, mat_at)
	print("depth green %d ms %s" % [Time.get_ticks_msec() - t0, g.depth_stats])

## WorldForest + the hollow hook proposed to world (terrain discards bg/cave layers on forest-hollow tiles),
## unless world already wired it (world_view.forest).
func _build_forest(wv: WorldView) -> void:
	if wv.get("forest") != null:
		forest_node = wv.forest
		print("forest: live integration ", wv.forest.stats)
		_patch_depth_forest_haze(wv)
		return
	var mat: ShaderMaterial = wv.terrain.material
	var code: String = mat.shader.code.replace("

", "
")
	if code.find("forest_tex") < 0:
		var anchor := "	if (layer == 2 && fld.r > 0.5) {"
		assert(code.find(anchor) >= 0, "forest anchor missing")
		code = code.replace(anchor, "	if (layer != 0 && texelFetch(forest_tex, clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1), 0).r > 0.5) {
		discard;   // forest hollow: WorldForest's deep forest shows through
	}
" + anchor)
		code = code.replace("varying vec3 w_pos;", "uniform sampler2D forest_tex : filter_nearest, repeat_disable;
varying vec3 w_pos;")
		var sh := Shader.new()
		sh.code = code
		mat.shader = sh
	var ftex := ImageTexture.create_from_image(WorldForest.hollow_image(wv.terrain))
	mat.set_shader_parameter("forest_tex", ftex)
	# world_depth: no back-wall volume in the hollow (its hazed faces were the "blue waterfall" columns)
	var dv = wv.get("depth")
	if dv and dv.material:
		var dm: ShaderMaterial = dv.material
		var dc: String = dm.shader.code.replace("\r\n", "\n")
		if dc.find("forest_tex") < 0:
			var a := "void fragment() {\n"
			assert(dc.find(a) >= 0, "depth anchor missing")
			dc = dc.replace(a, a + "\tif (solid_f < 0.5 && texelFetch(forest_tex, clamp(ivec2(floor(tile)), ivec2(0), ivec2(level_size) - 1), 0).r > 0.5) {\n\t\tdiscard;   // forest hollow\n\t}\n")
			dc = dc.replace("varying vec3 w_pos;", "uniform sampler2D forest_tex : filter_nearest, repeat_disable;\nvarying vec3 w_pos;")
			var dsh := Shader.new()
			dsh.code = dc
			dm.shader = dsh
		dm.set_shader_parameter("forest_tex", ftex)
	var t0 := Time.get_ticks_msec()
	var f := WorldForest.new()
	f.name = "Forest"
	wv.add_child(f)
	f.build(wv.level, wv.terrain)
	forest_node = f
	print("forest %d ms %s" % [Time.get_ticks_msec() - t0, f.stats])

## Pixels (every 3rd) whose camera ray crosses the play plane inside a forest-hollow tile and whose colour is
## pale sky blue (b > g > r, bright, bluish): must be 0.
func _sky_check(img: Image, wv: WorldView) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var hm := WorldForest.hollow_mask(wv.terrain)
	var W := wv.terrain.W
	var H := wv.terrain.H
	var vs := get_viewport().get_visible_rect().size
	var sx := vs.x / img.get_width()
	var sy := vs.y / img.get_height()
	var n_hollow := 0
	var n_sky := 0
	var lum_sum := 0.0
	for py in range(0, img.get_height(), 3):
		for px in range(0, img.get_width(), 3):
			var o := cam.project_ray_origin(Vector2(px * sx, py * sy))
			var d := cam.project_ray_normal(Vector2(px * sx, py * sy))
			if absf(d.z) < 1e-5:
				continue
			var hit := o + d * (-o.z / d.z)
			var tx := int(floor(hit.x))
			var ty := int(floor(-hit.y))
			if tx < 0 or ty < 0 or tx >= W or ty >= H or not hm[ty * W + tx]:
				continue
			# gameplay glyphs (portals, keys, arrows...) within a tile are not the world: skip them
			var glyph := false
			for gy in range(maxi(ty - 1, 0), mini(ty + 2, H)):
				for gx in range(maxi(tx - 1, 0), mini(tx + 2, W)):
					var gid: int = wv.level.fg[gy * W + gx]
					if gid != 0 and not WorldPalette.is_world_solid(gid) and not WorldPalette.is_world_deco(gid):
						glyph = true
			if glyph:
				continue
			n_hollow += 1
			var c := img.get_pixel(px, py)
			lum_sum += c.get_luminance()
			if c.b > c.g and c.g > c.r and c.b > 0.45 and c.b - c.r > 0.12:
				n_sky += 1
				if n_sky <= 6:
					print("  sky px at ", Vector2i(px, py), " tile ", Vector2i(tx, ty), " ", c)
	return {"hollow_px": n_hollow, "sky_px": n_sky, "mean_lum": lum_sum / maxf(n_hollow, 1.0)}

## Proposed to world: inside forest regions (the dilated hollow tex covers the solids bordering a hollow) the
## depth volume's faces haze into the dark forest fog instead of the pale sky, so trunk / pocket side faces
## never read as blue lines.
func _patch_depth_forest_haze(wv: WorldView) -> void:
	var dv = wv.get("depth")
	if dv == null or dv.material == null:
		return
	var dm: ShaderMaterial = dv.material
	var dc: String = dm.shader.code.replace("

", "
")
	if dc.find("forest_fog") >= 0:
		return
	dc = dc.replace("varying vec3 w_pos;", "uniform sampler2D forest_tex : filter_nearest, repeat_disable;
uniform vec3 forest_fog : source_color = vec3(0.035, 0.07, 0.04);
varying vec3 w_pos;")
	var a := "	ALBEDO = albedo * ao * (1.0 - hz);"
	assert(dc.find(a) >= 0, "depth haze anchor missing")
	dc = dc.replace(a, "	vec3 hcol = haze_color;
	if (texelFetch(forest_tex, clamp(ivec2(floor(tile)), ivec2(0), ivec2(level_size) - 1), 0).r > 0.5) {
		hcol = forest_fog;   // forest: faces recede into the dark forest fog, not the sky
		hz = max(hz, smoothstep(0.3, 6.0, d) * 0.8);
		albedo *= 0.7;
	}
" + a)
	dc = dc.replace("	EMISSION = haze_color * hz * haze_emit", "	EMISSION = hcol * hz * haze_emit")
	var sh := Shader.new()
	sh.code = dc
	dm.shader = sh
	dm.set_shader_parameter("forest_tex", ImageTexture.create_from_image(WorldForest.hollow_image(wv.terrain)))
	print("depth forest-haze patch applied")

## Prints every visual instance whose world AABB overlaps the column through tile-space point t (radius r), in
## front of z -3 (candidates for a prop seen at that spot).
func _find_at(t: Vector2, r: float) -> void:
	var wp := Vector2(t.x, -t.y)
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		if vi is MultiMeshInstance3D:
			var mmi := vi as MultiMeshInstance3D
			if mmi.multimesh == null:
				continue
			var mm := mmi.multimesh
			for k in mm.instance_count:
				var o := mmi.global_transform * mm.get_instance_transform(k).origin
				if Vector2(o.x, o.y).distance_to(wp) < r and o.z > -30.0:
					print("FIND mm ", mmi.get_path(), " inst ", k, " at ", o)
					break
			continue
		var ab := vi.global_transform * vi.get_aabb()
		if ab.size.length() > 30.0:
			continue
		var c := ab.get_center()
		if Vector2(c.x, c.y).distance_to(wp) < r + ab.size.length() * 0.5 and c.z > -30.0:
			print("FIND ", vi.get_path(), " ", vi.get_class(), " aabb ", ab)
