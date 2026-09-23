extends Node
## Whole-level visual-artifact audit (sky leaks, z-fighting flicker, black lines). Boots the real game
## (HUD hidden, god mode), walks a spot set and, per spot and zoom, captures three frames:
##   a = the normal camera, b = camera distance x (1 + 1e-5) (every depth value re-rounds, nothing visibly moves),
##   c = the normal camera again, d + e = the camera moved by 0.45 px (twice). a vs c marks animated pixels
##   (particles, wind, water), b vs a+c marks z-fighting, d+e vs a's 3x3 neighbourhood marks shimmer (colours
##   that appear when the camera moves). The frames + camera
## projection go to user://<out>/raw/, then tests/fv_audit_report.py analyses them (run automatically unless
## analyse=0) and writes user://<out>/<spot>_z<zoom>.png marked images + report.txt / report.json.
## Run: bash tools_run_test.sh res://tests/fv_audit.tscn [-- spots=grid|list zoom=30,60 only=a,b step=22
##          hide=forest,voxel,depth out=audit settle=0.45 q=3 analyse=1 flicker=1 grid60=2 keep=0 shift_px=0.45]
##   only= spot names (named spots or grid names g_<x>_<y>) or tile rects "rect:x0_y0_x1_y1" (grid spots inside)
##   hide= WorldView members (forest, voxel, depth, depth_green, decor, grass, foliage, vista, backdrop, keels,
##         trials, doors, lights) or node names anywhere in the game, hidden before capturing (isolation)
##   novoxel / nodepth: build without the voxel landscape / the depth volume (like world_game_shot)
const GameScript := preload("res://scripts/game/game.gd")
const SPOTS_FV := [
	["spawn", Vector2i(2, 56)],
	["grove", Vector2i(30, 54)],
	["pine", Vector2i(62, 50)],
	["shaft", Vector2i(43, 60)],
	["dirt", Vector2i(42, 69)],
	["hall_a", Vector2i(40, 81)],
	["hall_b", Vector2i(26, 92)],
	["hall_c", Vector2i(40, 75)],
	["twin", Vector2i(245, 85)],
	["gspire", Vector2i(196, 62)],
	["keep", Vector2i(300, 90)],
	["t15", Vector2i(348, 86)],
	["falls", Vector2i(150, 140)],
	["eastwood", Vector2i(382, 104)],
]
var game: Node
var wv: WorldView
var args := {"level": "forgotten_veil", "spots": "grid", "zoom": "30,60", "only": "", "step": "22", "hide": "",
	"out": "audit", "settle": "0.45", "q": "3", "analyse": "1", "flicker": "1", "grid60": "2", "maxsky": "0.9"}

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
		elif a == "novoxel":
			WorldVoxel.enabled = false
		elif a == "nodepth":
			WorldView.depth_enabled = false
	var t_boot := Time.get_ticks_msec()
	GameScript.boot_options = {"no_save": true, "quality": int(args.q), "level": args.level, "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	wv = game.world as WorldView
	game.sim.set_god_mode(true)
	var ui: CanvasLayer = game.get("_ui")
	if ui:
		ui.visible = false
	var ov: Node3D = game.get("collision_overlay")
	if ov:
		ov.visible = false
	# the voxel landscape streams in on a thread: wait for it before the first capture
	if wv.voxel:
		var tv := Time.get_ticks_msec()
		while not wv.voxel.is_ready and Time.get_ticks_msec() - tv < 120000:
			await get_tree().process_frame
		wv.voxel.finish_fade()
		print("AUDIT voxel ready after %d ms (is_ready %s)" % [Time.get_ticks_msec() - tv, str(wv.voxel.is_ready)])
	_apply_hide()
	if args.has("tileinfo"):
		# tileinfo=x0_y0_x1_y1: dump the terrain classes of a rect (for fixers), then exit
		_tileinfo(str(args.tileinfo))
		OS.kill(OS.get_process_id())
	var out_dir := "user://%s" % args.out
	DirAccess.make_dir_recursive_absolute(out_dir + "/raw")
	_save_tiles(out_dir + "/tiles.png")
	var zooms: Array[float] = []
	for z: String in str(args.zoom).split(",", false):
		zooms.append(float(z))
	var caps: Array[Dictionary] = []
	var spots := _spot_list(zooms)
	print("AUDIT %d captures planned (boot %d ms)" % [spots.size(), Time.get_ticks_msec() - t_boot])
	var pid := -1
	for fn: String in DirAccess.get_files_at(out_dir + "/raw"):
		DirAccess.remove_absolute(out_dir + "/raw/" + fn)
	DirAccess.remove_absolute(out_dir + "/report.txt")
	if args.analyse == "1":
		var py := ProjectSettings.globalize_path("res://tests/fv_audit_report.py")
		var pa: PackedStringArray = [py, ProjectSettings.globalize_path(out_dir), "--watch"]
		if args.get("keep", "0") == "1":
			pa.append("--keep")
		pid = OS.create_process("python", pa)
		print("AUDIT analyser pid ", pid)
	var cam: Camera3D = game.rig.cam
	var near0 := cam.near
	var far0 := cam.far
	var t0 := Time.get_ticks_msec()
	var last_zoom := -1.0
	for s: Dictionary in spots:
		var t: Vector2i = s.tile
		var zm: float = s.zoom
		game.sim.px = t.x * 16.0; game.sim.py = t.y * 16.0
		game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		game.sim.speed_x = 0.0; game.sim.speed_y = 0.0
		game.rig.target_zoom = zm
		game.rig.zoom = zm
		game.rig.snap_to(EECoords.player_center(game.sim.px, game.sim.py))
		var settle := float(args.settle) * (2.0 if zm != last_zoom else 1.0)
		last_zoom = zm
		await _wait(settle)
		if wv.forest:
			for k in 4:
				wv.forest.update_focus(EECoords.player_center(game.sim.px, game.sim.py), 1.0)
		await _frames(2)
		var base := "%s_z%d" % [s.name, int(zm)]
		var tc := Time.get_ticks_msec()
		var frames: Array[Image] = [await _grab()]
		var meta := _cam_meta(cam, frames[0])
		if args.flicker == "1":
			_perturb(cam, true, near0, far0, zm)
			await _frames(3)
			frames.append(await _grab())
			_perturb(cam, false, near0, far0, zm)
			await _frames(3)
			frames.append(await _grab())
			# d: the camera moved by a fraction of a pixel (what moving does): z-fighting / shimmering
			# pixels take colours their neighbourhood in a never had
			var ppt := float(frames[0].get_width()) / zm
			var sh := float(args.get("shift_px", "0.45")) / ppt * 16.0
			game.sim.px += sh; game.sim.py += sh * 0.7
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
			await _frames(3)
			frames.append(await _grab())
			await _frames(3)
			frames.append(await _grab())   # e: same shifted camera again (moving particles are not shimmer)
			game.sim.px -= sh; game.sim.py -= sh * 0.7
			game.sim.prev_px = game.sim.px; game.sim.prev_py = game.sim.py
		var tw := Time.get_ticks_msec()
		for k in frames.size():
			var fr := FileAccess.open("%s/raw/%s_%s.bin" % [out_dir, base, "abcde"[k]], FileAccess.WRITE)
			fr.store_buffer(frames[k].get_data())
			fr.close()
		meta["format"] = frames[0].get_format()
		meta["frames"] = frames.size()
		meta["name"] = s.name
		meta["base"] = base
		meta["zoom"] = zm
		meta["tile"] = [t.x, t.y]
		meta["ball"] = [game.sim.px / 16.0, game.sim.py / 16.0]
		# the per-capture json is written last: the analyser picks the capture up once it exists
		var fm := FileAccess.open("%s/raw/%s.json" % [out_dir, base], FileAccess.WRITE)
		fm.store_string(JSON.stringify(meta))
		fm.close()
		caps.append(meta)
		print("AUDIT cap %d/%d %s  grab %d ms  write %d ms" % [caps.size(), spots.size(), base, tw - tc, Time.get_ticks_msec() - tw])
	print("AUDIT captured %d in %d s" % [caps.size(), (Time.get_ticks_msec() - t0) / 1000])
	var f := FileAccess.open(out_dir + "/captures.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"level": args.level, "W": wv.terrain.W, "H": wv.terrain.H, "hide": args.hide,
		"captures": caps}, "\t"))
	f.close()
	var fd := FileAccess.open(out_dir + "/raw/capture_done", FileAccess.WRITE)
	fd.store_string(str(caps.size()))
	fd.close()
	if pid > 0:
		# the analyser has been chewing through the captures in parallel: wait for its report
		var tr := Time.get_ticks_msec()
		while OS.is_process_running(pid) and Time.get_ticks_msec() - tr < 900000:
			await _wait(0.5)
		print("AUDIT analyser finished %d s after the last capture; see %s/report.txt" % [(Time.get_ticks_msec() - tr) / 1000, ProjectSettings.globalize_path(out_dir)])
		var rep := FileAccess.get_file_as_string(out_dir + "/report.txt")
		for l: String in rep.split("
").slice(0, 60):
			print(l)
	print("AUDIT DONE")
	# the engine hangs on exit after this scene (voxel/forest teardown): everything is written, so just leave
	OS.kill(OS.get_process_id())

## The depth-precision change for frame b (arg fmode): zoom (default) = camera distance x (1 + 1e-5): every depth
## value re-rounds, the image scales by 1e-5 (< 0.02 px), shadows stay put; near = near 0.3 -> 0.12 (also moves the
## directional shadow splits: shadow edges false-positive); far = far 900 -> 2500.
func _perturb(cam: Camera3D, on: bool, near0: float, far0: float, zm: float) -> void:
	var fm := str(args.get("fmode", "zoom"))
	cam.near = near0 * 0.4 if on and fm.contains("near") else near0
	cam.far = 2500.0 if on and fm.contains("far") else far0
	if fm.contains("zoom"):
		game.rig.zoom = zm * (1.00001 if on else 1.0)
		game.rig.target_zoom = game.rig.zoom

func _apply_hide() -> void:
	for nm: String in str(args.hide).split(",", false):
		var nd: Node = null
		var v: Variant = wv.get(nm)
		if v is Node:
			nd = v
		if nd == null:
			nd = wv.get_node_or_null(nm)
		if nd == null:
			nd = game.find_child(nm, true, false)
		if nd is Node3D:
			(nd as Node3D).visible = false
			print("AUDIT hid ", nm)
		elif nd is CanvasItem:
			(nd as CanvasItem).visible = false
			print("AUDIT hid ", nm)
		else:
			print("AUDIT hide: no node ", nm)

func _tileinfo(r: String) -> void:
	var v := r.split("_")
	var t := wv.terrain
	var W := t.W
	for y in range(int(v[1]), int(v[3]) + 1):
		for x in range(int(v[0]), int(v[2]) + 1):
			var i := y * W + x
			print("TILE (%d,%d) fg %d bg %d solid %d sky %d backwall %d pocket %d mat %d window %d wall_code %d enclosed_sky_bg %d art_door %d" % [
				x, y, wv.level.fg[i], wv.level.bg[i], t.solid[i], t.sky[i], t.backwall[i], t.pocket[i], t.mat_ids[i],
				t.window[i] if t.window.size() > i else -1, t.wall_code[i] if t.wall_code.size() > i else -1,
				t.enclosed_sky_bg[i] if t.enclosed_sky_bg.size() > i else -1, t.art_door[i] if t.art_door.size() > i else -1])

## Tile classes for the analyser: R = 0 air / 1 open sky / 2 solid, G = material id, B = bit 0 gameplay glyph
## (non-world fg id within 1 tile) | bit 1 painted window (glass art: pale panes, dark frames by design) | bit 2 painted water /
## waterfall stream (FxOverlayMaps: the falls' sheets are pale blue-white), A = 255.
func _save_tiles(path: String) -> void:
	var t := wv.terrain
	var W := t.W
	var H := t.H
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var glyph := PackedByteArray()
	glyph.resize(W * H)
	for y in H:
		for x in W:
			var gid: int = wv.level.fg[y * W + x]
			if gid != 0 and not WorldPalette.is_world_solid(gid) and not WorldPalette.is_world_deco(gid):
				for gy in range(maxi(y - 1, 0), mini(y + 2, H)):
					for gx in range(maxi(x - 1, 0), mini(x + 2, W)):
						glyph[gy * W + gx] = 1
	# painted water / waterfall streams (FxOverlayMaps): the falls' sheets are pale blue-white by design
	var wet := PackedByteArray()
	wet.resize(W * H)
	var veil: Node = game.actors.find_child("Veil", true, false) if game.actors else null
	var maps: Object = veil.get("maps") if veil else null
	if maps:
		var st: PackedByteArray = maps.get("stream")
		var wa: PackedByteArray = maps.get("water")
		for i in W * H:
			if (st.size() > i and st[i] == 1) or (wa.size() > i and wa[i] == 1):
				wet[i] = 4
	for y in H:
		for x in W:
			var i := y * W + x
			var cls := 2 if t.solid[i] else (1 if t.sky[i] else 0)
			var win := 2 if t.window.size() == W * H and t.window[i] > 0 else 0
			img.set_pixel(x, y, Color8(cls, int(t.mat_ids[i]), glyph[i] | win | wet[i], 255))
	img.save_png(path)

func _spot_list(zooms: Array[float]) -> Array[Dictionary]:
	var only: PackedStringArray = str(args.only).split(",", false)
	var rects: Array[Rect2i] = []
	var names: PackedStringArray = []
	for o: String in only:
		if o.begins_with("rect:"):
			var v := o.substr(5).split("_")
			if v.size() >= 4:
				rects.append(Rect2i(int(v[0]), int(v[1]), int(v[2]) - int(v[0]), int(v[3]) - int(v[1])))
		else:
			names.append(o)
	var out: Array[Dictionary] = []
	for zm in zooms:
		for s: Array in SPOTS_FV:
			if only.is_empty() or names.has(s[0]):
				out.append({"name": s[0], "tile": s[1], "zoom": zm})
		if args.spots != "grid":
			continue
		var t := wv.terrain
		var step := int(args.step) * (int(args.grid60) if zm >= 45.0 else 1)
		var stepy := maxi(int(round(step * 12.0 / 22.0)), 1)
		var hw := int(zm * 0.5)
		var hh := int(zm * 0.5 * 9.0 / 16.0)
		for gy in range(stepy / 2, t.H, stepy):
			for gx in range(step / 2, t.W, step):
				var nm := "g_%d_%d" % [gx, gy]
				if not only.is_empty():
					var hit := names.has(nm)
					for r in rects:
						if r.has_point(Vector2i(gx, gy)):
							hit = true
					if not hit:
						continue
				var n := 0
				var ns := 0
				for y in range(maxi(gy - hh, 0), mini(gy + hh, t.H)):
					for x in range(maxi(gx - hw, 0), mini(gx + hw, t.W)):
						n += 1
						var i := y * t.W + x
						if t.sky[i] and not t.solid[i]:
							ns += 1
				if n == 0 or float(ns) / float(n) > float(args.maxsky):
					continue
				out.append({"name": nm, "tile": Vector2i(gx, gy), "zoom": zm})
	return out

## Pixel -> z = 0 plane mapping (the camera looks straight down -z, so it is affine): world hits of the
## viewport corners, plus a centre probe for verification.
func _cam_meta(cam: Camera3D, img: Image) -> Dictionary:
	var vs := get_viewport().get_visible_rect().size
	var p00 := _hit(cam, Vector2.ZERO)
	var p11 := _hit(cam, vs)
	var pc := _hit(cam, vs * 0.5)
	return {"img": [img.get_width(), img.get_height()], "vp": [vs.x, vs.y],
		"p00": [p00.x, p00.y], "p11": [p11.x, p11.y], "pc": [pc.x, pc.y],
		"cam": [cam.global_position.x, cam.global_position.y, cam.global_position.z], "near": cam.near}

func _hit(cam: Camera3D, v: Vector2) -> Vector3:
	var o := cam.project_ray_origin(v)
	var d := cam.project_ray_normal(v)
	return o + d * (-o.z / d.z) if absf(d.z) > 1e-6 else o

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
