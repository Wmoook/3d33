extends Node3D
## Visual test for the actors module. Builds ActorsView over the real level (with crude stand-in terrain
## for context), flies a camera to key spots and saves screenshots to user://fx_<name>.png, then quits.
## Run windowed: $G --path C:/Users/super/ex-odyssey res://tests/fx_preview.tscn  [-- only=<name>]

const ACTOR_IDS := [1, 2, 3, 4, 5, 6, 7, 8, 43, 100, 101, 121, 242, 381, 255]
const PASSIVE := [22, 32, 33, 34, 36, 50, 62]

var lvl: EELevel
var sim: FxMockSim
var actors: ActorsView
var cam: Camera3D
var ball_pos := Vector3.ZERO
var ball_vel := Vector2.ZERO   # scripted motion in EE speed units (world y up)
var extra_balls: Array = []    # [FxPlayerBall, FxMockSim]
var only := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	lvl = EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	sim = FxMockSim.new(lvl)
	_setup_env()
	_build_context()
	var t := Time.get_ticks_msec()
	actors = ActorsView.new()
	add_child(actors)
	actors.build(lvl, sim)
	print("ActorsView.build: ", Time.get_ticks_msec() - t, " ms")
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	ball_pos = sim.center()
	_run.call_deferred()

func _process(delta: float) -> void:
	# scripted ball motion
	if ball_vel != Vector2.ZERO:
		ball_pos += Vector3(ball_vel.x, ball_vel.y, 0) * delta * 100.0 / 16.0
	sim.speed_x = ball_vel.x
	sim.speed_y = -ball_vel.y
	actors.update_player(ball_pos, sim, delta)
	for e in extra_balls:
		e[0].update_from_sim(e[0].global_position, e[1], delta)

func _setup_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.36, 0.42)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 0.55
	sun.light_color = Color(0.75, 0.8, 1.0)
	sun.shadow_enabled = true
	add_child(sun)

## Crude context terrain: dark tinted boxes for solid FG tiles, flat far quads for BG tiles.
func _build_context() -> void:
	var info := {}
	var f := FileAccess.open("res://assets/ee_ref/blocks.json", FileAccess.READ)
	if f:
		info = JSON.parse_string(f.get_as_text())
	var solid_tiles: Array = []
	var solid_cols: Array = []
	var bg_tiles: Array = []
	var bg_cols: Array = []
	for y in lvl.height:
		for x in lvl.width:
			var id := lvl.get_fg(x, y)
			if id > 0 and id not in ACTOR_IDS and id not in PASSIVE and not (id >= 227 and id <= 254 and id != 242):
				solid_tiles.append(Vector2i(x, y))
				solid_cols.append(_avg(info, id, 0.55))
			var b := lvl.get_bg(x, y)
			if b > 0:
				bg_tiles.append(Vector2i(x, y))
				bg_cols.append(_avg(info, b, 0.22))
	_mm_boxes(solid_tiles, solid_cols, Vector3(1, 1, 1.6), -0.35)
	_mm_boxes(bg_tiles, bg_cols, Vector3(1, 1, 0.2), -2.2)

func _avg(info: Dictionary, id: int, k: float) -> Color:
	var d = info.get(str(id))
	if d == null or not d.has("avg_rgb"):
		return Color(0.3, 0.3, 0.3) * k
	var c: Array = d.avg_rgb
	return Color(c[0] / 255.0 * k, c[1] / 255.0 * k, c[2] / 255.0 * k)

func _mm_boxes(tiles: Array, cols: Array, size: Vector3, z: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = size
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	box.material = m
	mm.mesh = box
	mm.instance_count = tiles.size()
	for i in tiles.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, EECoords.tile_center(tiles[i].x, tiles[i].y, z)))
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)

func _look_at_tile(tx: float, ty: float, width_tiles := 40.0) -> void:
	var half_h := width_tiles / (16.0 / 9.0) * 0.5
	var d := half_h / tan(deg_to_rad(cam.fov * 0.5))
	cam.position = Vector3(tx, -ty, d)
	cam.rotation = Vector3.ZERO

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://fx_%s.png" % name)
	print("saved fx_", name)

func _want(name: String) -> bool:
	return only == "" or only == name

func _place_ball(tx: float, ty: float, ground := true, vel := Vector2.ZERO) -> void:
	sim.set_tile(tx, ty)
	ball_pos = sim.center()
	sim.on_ground = ground
	ball_vel = vel
	actors.player._has_prev = false

func _run() -> void:
	await _frames(5)
	if _want("spawn"):
		_place_ball(65, 11)
		_look_at_tile(65, 11)
		await _frames(30)
		await _shot("spawn")
	if _want("spawn_close"):
		_place_ball(65, 11)
		_look_at_tile(62, 11, 18)
		await _frames(30)
		await _shot("spawn_close")
	if _want("wind"):
		_place_ball(40, 125, false, Vector2(6.5, 0))
		_look_at_tile(40, 124)
		await _frames(40)
		await _shot("wind")
	if _want("tornado"):
		_place_ball(22, 104, false)
		_look_at_tile(22, 104)
		await _frames(30)
		await _shot("tornado")
	if _want("updraft"):
		_place_ball(160, 110, false, Vector2(0, 6))
		_look_at_tile(160, 110)
		await _frames(30)
		await _shot("updraft")
	if _want("redkeys"):
		_place_ball(110, 62)
		_look_at_tile(110, 58)
		await _frames(30)
		await _shot("redkeys")
		# touch a few red keys next to the ball: local flare + ring wave, key colour active
		sim.keys_active[&"red"] = true
		for t in [Vector2i(109, 62), Vector2i(111, 62), Vector2i(110, 61)]:
			if lvl.get_fg(t.x, t.y) == 6:
				sim.sim_event.emit(&"key", {"color": &"red", "tile": t})
		var any := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if not any and lvl.get_fg(110 + dx, 62 + dy) == 6:
					sim.sim_event.emit(&"key", {"color": &"red", "tile": Vector2i(110 + dx, 62 + dy)})
					any = true
		await _frames(14)
		await _shot("redkeys_flare")
		sim.keys_active[&"red"] = false
	if _want("coindoor"):
		_place_ball(60, 13)
		_look_at_tile(62, 14, 20)
		await _frames(30)
		await _shot("coindoor")
	if _want("portals"):
		_place_ball(14, 9, true)
		_look_at_tile(15, 10, 24)
		await _frames(30)
		await _shot("portals")
		sim.sim_event.emit(&"portal", {"from": Vector2i(15, 10), "to": Vector2i(18, 15)})
		await _frames(6)
		await _shot("portal_warp")
	if _want("coin"):
		_place_ball(206, 18)
		_look_at_tile(208, 18, 16)
		await _frames(30)
		await _shot("coin")
		sim.collected[Vector2i(208, 18)] = true
		sim.sim_event.emit(&"blue_coin", {"tile": Vector2i(208, 18)})
		await _frames(10)
		await _shot("coin_collect")
	if _want("crowns"):
		_place_ball(258, 138, false)
		_look_at_tile(258, 138, 30)
		await _frames(30)
		await _shot("crowns")
	if _want("hero_run"):
		# gameplay zoom (40 tiles wide): ball resting on open ground near the spawn, then a closer look
		var spot := _open_ground_near(Vector2i(65, 11))
		_place_ball(spot.x, spot.y, true, Vector2(0.0, 0))
		_look_at_tile(spot.x + 0.5, spot.y, 40)
		await _frames(40)
		await _shot("hero_run")
		ball_vel = Vector2(5.5, 0)
		await _frames(12)
		ball_vel = Vector2.ZERO
		_look_at_tile(ball_pos.x, -ball_pos.y, 12)
		await _frames(3)
		await _shot("hero_run_close")
	if _want("death"):
		_place_ball(65, 11)
		_look_at_tile(65, 11, 16)
		await _frames(20)
		sim.sim_event.emit(&"death", {})
		sim.is_dead = true
		await _frames(24)
		await _shot("death")
		await _frames(40)
		sim.is_dead = false
		sim.sim_event.emit(&"respawn", {})
		await _frames(8)
		await _shot("respawn")
		await _frames(30)
	if _want("faces"):
		await _faces()
	get_tree().quit()

## First air tile (with 6 free tiles to its right) that sits on top of a solid stand-in tile.
func _open_ground_near(c: Vector2i) -> Vector2i:
	for r in range(0, 60):
		for dx in range(-r, r + 1):
			for y in range(maxi(c.y - 10, 1), mini(c.y + 10, lvl.height - 2)):
				var x := c.x + dx
				var ok := true
				for k in 7:
					for h in 2:
						if lvl.get_fg(x + k, y - h) != 0:
							ok = false
				if ok and lvl.get_fg(x, y + 1) > 8:
					return Vector2i(x, y)
	return c

## Close-up turntable of face states, lit like a product shot.
func _faces() -> void:
	actors.player.visible = false
	var states := [
		["idle", {}],
		["look", {"look": Vector2(0.9, 0.1), "grin": 0.6}],
		["blink", {"eye_open": 0.0}],
		["happy", {"happy": 1.0, "grin": 1.0}],
		["squeeze", {"squeeze": 1.0}],
		["scared", {"wide": 1.0, "gasp": 1.0, "look": Vector2(0, -0.6)}],
		["dead", {"dead": 1.0}],
	]
	var base := Vector3(1000, 1000, 0)
	var i := 0
	for s in states:
		var b := FxPlayerBall.new()
		b.ball_layer = 1 << (10 + i)
		add_child(b)
		b.global_position = base + Vector3((i - 3) * 1.35, 0, 0)
		b.face_override = s[1]
		var ms := FxMockSim.new(lvl)
		ms.on_ground = true
		if s[0] == "happy":
			ms.has_crown = true
		extra_balls.append([b, ms])
		i += 1
	# god mode + gravity-left balls on a second row
	var g := FxPlayerBall.new()
	g.ball_layer = 1 << 17
	add_child(g)
	g.global_position = base + Vector3(-1.4, -1.7, 0)
	var gs := FxMockSim.new(lvl)
	gs.in_god_mode = true
	extra_balls.append([g, gs])
	var l := FxPlayerBall.new()
	l.ball_layer = 1 << 18
	add_child(l)
	l.global_position = base + Vector3(1.4, -1.7, 0)
	var ls := FxMockSim.new(lvl)
	ls.gravity_dir = Vector2i(-1, 0)
	ls.has_silver_crown = true
	extra_balls.append([l, ls])
	for e in extra_balls:
		e[0]._env_light.visible = false   # face turntable: only each ball's own character lights
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 10)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.07, 0.09)
	fm.roughness = 0.3
	floor.material_override = fm
	floor.rotation_degrees = Vector3(90, 0, 0)
	floor.position = base + Vector3(0, 0, -1.5)
	add_child(floor)
	cam.position = base + Vector3(0, -0.55, 8.2)
	cam.rotation = Vector3.ZERO
	await _frames(240)
	await _shot("faces")
	# close hero shot
	cam.position = base + Vector3(0, 0.05, 2.1)
	cam.fov = 40
	await _frames(10)
	await _shot("face_hero")
