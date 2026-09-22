extends SceneTree
## Headless EE physics tests:
##   $G --headless --path C:/Users/super/ex-odyssey -s res://tests/physics_test.gd
## Uses the real level for spawn / trajectory / perf and small synthetic maps for isolated rules.
## Expected values come from an independent reference re-implementation of the AS3 formulas
## (Config.as constants, Player.as update order), not from EESim itself.

var _fails := 0
var _passes := 0

# ---- reference constants, recomputed independently from Config.as
var R_MULT := 7.752
var R_BASE := pow(0.9981, 10) * 1.00016093
var R_NOMOD := pow(0.9900, 10) * 1.00016093

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_passes += 1
		print("  PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_fails += 1
		print("  FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")

func near(a: float, b: float, eps := 1e-9) -> bool:
	return absf(a - b) <= eps

# ---------------------------------------------------------------- synthetic maps
func make_level(w: int, h: int) -> EELevel:
	var l := EELevel.new()
	l.width = w; l.height = h
	l.fg.resize(w * h); l.fg.fill(0)
	l.bg.resize(w * h); l.bg.fill(0)
	for x in w:
		l.fg[x] = 9; l.fg[(h - 1) * w + x] = 9
	for y in h:
		l.fg[y * w] = 9; l.fg[y * w + w - 1] = 9
	return l

func put(l: EELevel, x: int, y: int, id: int, ex := {}) -> void:
	l.fg[y * l.width + x] = id
	if not ex.is_empty():
		l.extra[y * l.width + x] = ex

var _sims: Array[EESim] = []

func new_sim(l: EELevel) -> EESim:
	var s := EESim.new(l)
	_sims.append(s)
	return s

func run(sim: EESim, inp: EEInput, n: int) -> void:
	for i in n:
		sim.tick(inp)

## Side-effect-free check: is the 16x16 box overlapping any currently-solid, non-one-way tile?
func stuck(sim: EESim) -> bool:
	if sim.in_god_mode:
		return false
	var x0 := int(sim.px) >> 4
	var y0 := int(sim.py) >> 4
	for ty in range(y0, int(ceil((sim.py + 16.0) / 16.0))):
		for tx in range(x0, int(ceil((sim.px + 16.0) / 16.0))):
			if tx * 16 < sim.px + 16.0 and sim.px < tx * 16 + 16 and ty * 16 < sim.py + 16.0 and sim.py < ty * 16 + 16:
				if sim.is_tile_solid_now(tx, ty) and not sim.is_tile_one_way(tx, ty):
					return true
	return false

# ---------------------------------------------------------------- tests
func _init() -> void:
	print("=== EE physics tests ===")
	if OS.get_environment("PHYS_ONLY") == "fv":     # quick iteration on the Forgotten Veil block
		load("res://tests/physics_test_fv.gd").new(self).run_all()
		_finish()
		return
	test_spawn_real_level()
	test_free_fall()
	test_jump()
	test_walk()
	test_arrows_and_dots()
	test_portal()
	test_keys()
	test_coin_door()
	test_god_mode()
	test_scripted_run()
	test_perf()
	test_replay()
	test_snapshot()
	test_key_door_stay_inside()
	test_key_gate_deferred()
	test_key_door_real_level()
	load("res://tests/physics_test_fv.gd").new(self).run_all()
	_finish()


func _finish() -> void:
	# break signal->lambda->sim reference cycles so nothing leaks at exit
	for s in _sims:
		for c in s.sim_event.get_connections():
			s.sim_event.disconnect(c["callable"])
	_sims.clear()
	print("=== %d passed, %d failed ===" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func test_spawn_real_level() -> void:
	print("[spawn]")
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := new_sim(lvl)
	check("spawn px/py == tile (65,11)", sim.px == 65.0 * 16.0 and sim.py == 11.0 * 16.0, "%s,%s" % [sim.px, sim.py])
	check("spawn tile id 255", lvl.get_fg(65, 11) == 255)


func test_free_fall() -> void:
	print("[free fall]")
	var l := make_level(6, 800)
	put(l, 2, 2, 255)
	var sim := new_sim(l)
	var inp := EEInput.new()
	var v := 0.0
	var y := sim.py
	var exact := true
	var g := 2.0 / R_MULT
	for i in 700:
		sim.tick(inp)
		v = (v + g) * R_BASE
		if v > 16.0: v = 16.0
		y += v
		if not near(sim.speed_y, v, 1e-12) or not near(sim.py, y, 1e-6):
			exact = false
	check("fall speed matches AS3 reference every tick (700 ticks)", exact, "sim v=%.12f ref v=%.12f" % [sim.speed_y, v])
	var term := g * R_BASE / (1.0 - R_BASE)
	check("terminal fall speed = g*d/(1-d) = %.6f px/tick" % term, near(sim.speed_y, term, 1e-3), "sim=%.6f (EE speedY=%.4f)" % [sim.speed_y, sim.speed_y * R_MULT])


func _jump_reference() -> float:
	# After the jump tick: v = -2*26/7.752; each tick v = (v + 2/7.752) * base_drag; y += v.
	var v := -2.0 * 26.0 / R_MULT
	var y := 0.0
	var apex := 0.0
	for i in 200:
		v = (v + 2.0 / R_MULT) * R_BASE
		y += v
		apex = minf(apex, y)
		if v > 0.0:
			break
	return -apex


func test_jump() -> void:
	print("[jump]")
	var l := make_level(8, 30)
	put(l, 3, 27, 255)
	var sim := new_sim(l)
	var inp := EEInput.new()
	run(sim, inp, 20)
	var y0 := sim.py
	check("resting on floor", sim.on_ground and y0 == 28.0 * 16.0, "y=%s" % y0)
	var jumped := [false]
	sim.sim_event.connect(func(k, _d): if k == &"jump": jumped[0] = true)
	inp.jump = true
	sim.tick(inp)
	inp.jump = false
	check("jump event + impulse -52/7.752", jumped[0] and near(sim.speed_y, -52.0 / R_MULT, 1e-12), "v=%.9f" % sim.speed_y)
	var apex := y0
	for i in 100:
		sim.tick(inp)
		apex = minf(apex, sim.py)
	var h := y0 - apex
	var ref := _jump_reference()
	check("jump apex matches AS3 reference", near(h, ref, 1e-6), "sim=%.6f px ref=%.6f px (%.3f blocks)" % [h, ref, h / 16.0])
	check("standard jump clears 3 blocks, not 4", h >= 48.0 and h < 64.0)
	# Physical: 3-high wall is climbable, 4-high is not.
	for wall_h in [3, 4]:
		var l2 := make_level(20, 20)
		for k in wall_h:
			put(l2, 8, 18 - k, 9)
		put(l2, 4, 18, 255)
		var s2 := new_sim(l2)
		var i2 := EEInput.new()
		i2.right = true; i2.jump = true
		run(s2, i2, 300)
		var over := s2.px > 8.0 * 16.0
		check("holding right+jump %s a %d-block wall" % ["clears" if wall_h == 3 else "does NOT clear", wall_h], over == (wall_h == 3), "x=%.2f" % s2.px)


func test_walk() -> void:
	print("[walk]")
	var l := make_level(300, 10)
	put(l, 2, 8, 255)
	var sim := new_sim(l)
	var inp := EEInput.new()
	run(sim, inp, 10)
	inp.right = true
	var v := 0.0
	var exact := true
	for i in 500:
		sim.tick(inp)
		v = (v + 1.0 / R_MULT) * R_BASE
		if not near(sim.speed_x, v, 1e-12):
			exact = false
	var term := (1.0 / R_MULT) * R_BASE / (1.0 - R_BASE)
	check("walk accel matches AS3 reference every tick", exact, "sim=%.9f ref=%.9f" % [sim.speed_x, v])
	check("walking max speed = %.5f px/tick" % term, near(sim.speed_x, term, 1e-3), "sim=%.5f (EE speedX=%.3f)" % [sim.speed_x, sim.speed_x * R_MULT])
	inp.right = false
	var s0 := sim.speed_x
	sim.tick(inp)
	var expect := (s0 + 0.0) * R_BASE * R_NOMOD
	check("release: base_drag*no_modifier_drag", near(sim.speed_x, expect, 1e-12), "%.9f vs %.9f" % [sim.speed_x, expect])
	run(sim, inp, 300)
	var fr := fmod(sim.px, 16.0)
	check("stops; EE grid snap only within 2px of a tile edge", sim.speed_x == 0.0 and (fr == 0.0 or (fr >= 2.0 and fr <= 14.0)), "x=%.4f (x%%16=%.4f)" % [sim.px, fr])
	# snap case: stop close to a tile boundary -> pulled onto it
	var l3 := make_level(40, 10)
	put(l3, 2, 8, 255)
	var s3 := new_sim(l3)
	run(s3, inp, 5)
	s3.px = 5.0 * 16.0 + 1.5
	run(s3, inp, 100)
	check("snap: x%16=1.5 slides back onto the grid (x -= tx/15, then >>0 under 0.2)", s3.px == 80.0, "x=%.6f" % s3.px)


func test_arrows_and_dots() -> void:
	print("[arrows / dots]")
	# Left arrow field: queue delay of 2 ticks before gravity turns left.
	var l := make_level(20, 12)
	for x in range(1, 10):
		for y in range(1, 11):
			put(l, x, y, 1)
	put(l, 6, 1, 255)
	var sim := new_sim(l)
	var inp := EEInput.new()
	var dirs := []
	for i in 30:
		sim.tick(inp)
		if sim.current_tile == 1 and dirs.size() < 3:
			dirs.append(sim.gravity_dir)
	check("arrow: gravity turns left on the 3rd tick inside (queue length 2)", dirs[0] == Vector2i(0, 1) and dirs[1] == Vector2i(0, 1) and dirs[2] == Vector2i(-1, 0), str(dirs))
	run(sim, inp, 200)
	check("falls left onto the wall and is grounded", sim.px == 16.0 and sim.on_ground and sim.speed_x == 0.0, "x=%s" % sim.px)
	inp.jump = true
	sim.tick(inp)
	inp.jump = false
	check("jump off a left-gravity wall pushes right (+52/7.752)", near(sim.speed_x, 52.0 / R_MULT, 1e-12), "vx=%.6f" % sim.speed_x)
	# Up arrow: falls up.
	var lu := make_level(10, 12)
	for y in range(1, 11):
		put(lu, 5, y, 2)
	put(lu, 5, 8, 255)
	var su := new_sim(lu)
	run(su, inp, 200)
	check("up arrow: rests on the ceiling", su.py == 16.0 and su.on_ground, "y=%s" % su.py)
	# Dot: one tick delay (double shift), then no gravity; momentum decays by base drag only.
	var ld := make_level(10, 40)
	for y in range(20, 39):
		put(ld, 5, y, 4)
	put(ld, 5, 2, 255)
	var sd := new_sim(ld)
	var d_after := []
	for i in 400:
		sd.tick(inp)
		if sd.current_tile == 4 and d_after.size() < 3:
			d_after.append([sd.gravity_dir, sd.speed_y])
	check("dot: gravity 0 from the 2nd tick inside (double queue shift)", d_after[0][0] == Vector2i(0, 1) and d_after[1][0] == Vector2i(0, 0), str(d_after))
	var s1: float = d_after[1][1]
	var s2: float = d_after[2][1]
	check("dot: speed decays by base_drag only", near(s2, s1 * R_BASE, 1e-12), "%.9f -> %.9f" % [s1, s2])


func test_portal() -> void:
	print("[portal]")
	var l := make_level(40, 20)
	put(l, 5, 8, 242, {"rotation": 0, "id": 1, "target": 2})
	put(l, 25, 8, 242, {"rotation": 0, "id": 2, "target": 1})
	put(l, 5, 3, 255)
	var sim := new_sim(l)
	var inp := EEInput.new()
	var evs := []
	sim.sim_event.connect(func(k, d): if k == &"portal": evs.append(d))
	run(sim, inp, 200)
	check("fell into portal id1 -> teleported to id2 once (no ping-pong)", evs.size() == 1 and evs[0]["from"] == Vector2i(5, 8) and evs[0]["to"] == Vector2i(25, 8), str(evs))
	check("landed below target portal", sim.on_ground and sim.px == 25.0 * 16.0 and sim.py == 18.0 * 16.0, "%s,%s" % [sim.px, sim.py])
	# Rotated portal: 0 -> 1 is dir 3 (270deg): speedX = -speedY*1.42, speedY = speedX*1.42
	var l2 := make_level(40, 30)
	put(l2, 5, 10, 242, {"rotation": 0, "id": 1, "target": 2})
	put(l2, 30, 10, 242, {"rotation": 1, "id": 2, "target": 1})
	put(l2, 5, 3, 255)
	var s2 := new_sim(l2)
	var got := [false]
	var prev_sy := 0.0
	s2.sim_event.connect(func(k, _d): if k == &"portal": got[0] = true)
	for i in 200:
		prev_sy = s2.speed_y
		s2.tick(inp)
		if got[0]:
			break
	var sy_before := (prev_sy + 2.0 / R_MULT) * R_BASE
	var expect_sx := (-(sy_before * R_MULT) * 1.42) / R_MULT
	check("portal rotation 0->1 maps down-velocity to left x1.42", got[0] and near(s2.speed_x, expect_sx, 1e-9) and s2.speed_y == 0.0, "vx=%.6f expect %.6f vy=%s" % [s2.speed_x, expect_sx, s2.speed_y])


func test_keys() -> void:
	print("[keys / doors / gates]")
	var l := make_level(40, 10)
	put(l, 3, 8, 255)
	put(l, 6, 8, 6)          # red key
	put(l, 10, 8, 23)        # red door (in the path)
	put(l, 20, 5, 26)        # red gate (elsewhere)
	var sim := new_sim(l)
	var inp := EEInput.new()
	check("red door solid, gate open before key", sim.is_tile_solid_now(10, 8) and not sim.is_tile_solid_now(20, 5))
	var st := {"t": 0, "pick": -1, "expire": -1}
	var door_evs := []
	sim.sim_event.connect(func(k, d):
		if k == &"key" and st["pick"] < 0: st["pick"] = st["t"]
		elif k == &"key_expired": st["expire"] = st["t"]
		elif k == &"door_state" and d["kind"] == &"red": door_evs.append(d))
	inp.right = true
	var passed := false
	for i in 800:
		st["t"] = sim.ticks() + 1
		sim.tick(inp)
		var pick: int = st["pick"]
		if sim.px > 10.0 * 16.0 + 16.0:
			passed = true
		if sim.px > 30.0 * 16.0:
			inp.right = false
		if pick > 0 and sim.ticks() == pick + 1:
			check("key active: door open, gate closed", sim.is_key_active(&"red") and not sim.is_tile_solid_now(10, 8) and sim.is_tile_solid_now(20, 5), "left=%.3fs" % sim.key_time_left(&"red"))
	check("walked through the open red door", passed)
	var pick: int = st["pick"]
	var expire: int = st["expire"]
	# Reference expiry: World.offset += 0.3 per tick; expires when (offset - t0)/30 >= 5.
	var off := 0.0
	var t0 := 0.0
	var ref_expire := -1
	for t in range(1, 2000):
		off += 0.3
		if t == pick: t0 = off
		if t > pick and ref_expire < 0 and (off - t0) / 30.0 >= 5.0:
			ref_expire = t
	check("key expires after the EE duration (offset/30 >= 5 s)", expire == ref_expire and expire - pick >= 499 and expire - pick <= 501, "picked t=%d expired t=%d (%d ticks) ref=%d" % [pick, expire, expire - pick, ref_expire])
	check("door closed again, gate open again", sim.is_tile_solid_now(10, 8) and not sim.is_tile_solid_now(20, 5) and not sim.is_key_active(&"red"))
	check("door_state events open->closed", door_evs.size() == 2 and door_evs[0]["open"] == true and door_evs[1]["open"] == false, str(door_evs))
	# Gate closing on the player is deferred until the player leaves (switchKey queue).
	# Fall through an open red gate onto a red key: the key must not activate (closing the
	# gate) while the box still overlaps the gate tile.
	var lg := make_level(20, 10)
	put(lg, 5, 1, 255)
	put(lg, 5, 7, 26)
	put(lg, 5, 8, 6)
	var sg := new_sim(lg)
	var key_tick := [-1, 0]
	sg.sim_event.connect(func(k, _d): if k == &"key" and key_tick[0] < 0: key_tick[0] = key_tick[1])
	var first_active := -1
	var bad := false
	var ig := EEInput.new()
	for i in 300:
		key_tick[1] = sg.ticks() + 1
		sg.tick(ig)
		if sg.is_key_active(&"red"):
			if first_active < 0: first_active = sg.ticks()
			if sg.py < 128.0: bad = true
	check("gate never closes on the player (switchKey overlap queue)", key_tick[0] > 0 and first_active >= key_tick[0] and not bad and sg.py == 128.0,
		"key touched t=%d, active t=%d (deferred %d ticks)" % [key_tick[0], first_active, first_active - key_tick[0]])


func test_coin_door() -> void:
	print("[coin door]")
	for with_coin in [true, false]:
		var l := make_level(10, 12)
		put(l, 5, 2, 255)
		put(l, 5 if with_coin else 8, 3, 100)
		put(l, 5, 6, 43, {"rotation": 1})
		var sim := new_sim(l)
		var inp := EEInput.new()
		var evs := []
		sim.sim_event.connect(func(k, d): if k == &"coin" or k == &"door_state": evs.append([k, d]))
		run(sim, inp, 300)
		if with_coin:
			check("coin collected -> coin door (1) opens -> fell through", sim.coins == 1 and sim.is_coin_collected(5, 3) and not sim.is_tile_solid_now(5, 6) and sim.py == 10.0 * 16.0, "coins=%d y=%s ev=%s" % [sim.coins, sim.py, str(evs)])
		else:
			check("no coin -> stands on the coin door", sim.coins == 0 and sim.is_tile_solid_now(5, 6) and sim.py == 5.0 * 16.0, "y=%s" % sim.py)


func test_god_mode() -> void:
	print("[god mode]")
	var l := make_level(10, 20)
	put(l, 5, 17, 255)
	for y in range(5, 15):
		put(l, 5, y, 9)
	var sim := new_sim(l)
	var inp := EEInput.new()
	run(sim, inp, 10)
	inp.god_toggle = true
	inp.up = true
	run(sim, inp, 200)
	check("god mode flies up through solids", sim.in_god_mode and sim.py < 5.0 * 16.0, "y=%.2f" % sim.py)
	inp.up = false
	inp.god_toggle = true
	sim.tick(inp)
	check("god mode off again", not sim.in_god_mode)


func test_scripted_run() -> void:
	print("[scripted run from spawn, real level]")
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := new_sim(lvl)
	var inp := EEInput.new()
	var evs := {}
	sim.sim_event.connect(func(k, _d): evs[k] = evs.get(k, 0) + 1)
	# (ticks, left, right, jump)
	var script := [[60, 0, 0, 0], [120, 0, 1, 0], [40, 0, 1, 1], [150, 1, 0, 0], [60, 1, 0, 1], [200, 0, 1, 1], [100, 0, 0, 0], [150, 1, 0, 1]]
	var ok := true
	var line := ""
	var t := 0
	for seg in script:
		inp.left = seg[1] == 1; inp.right = seg[2] == 1; inp.jump = seg[3] == 1
		for i in seg[0]:
			sim.tick(inp)
			t += 1
			if is_nan(sim.px) or is_nan(sim.py) or stuck(sim):
				ok = false
			if t % 20 == 0:
				line += "t=%d (%.1f,%.1f) v=(%.2f,%.2f) g=%s%s\n" % [t, sim.px, sim.py, sim.speed_x, sim.speed_y, sim.gravity_dir, " G" if sim.on_ground else ""]
	print(line)
	print("  events: ", evs)
	check("scripted run: no NaN, never inside a solid", ok)


func test_perf() -> void:
	print("[performance]")
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := new_sim(lvl)
	var inp := EEInput.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		if i % 37 == 0:
			inp.left = rng.randf() < 0.4; inp.right = rng.randf() < 0.5; inp.jump = rng.randf() < 0.5
			inp.up = rng.randf() < 0.1; inp.down = rng.randf() < 0.1
		sim.tick(inp)
	var us := float(Time.get_ticks_usec() - t0) / n
	check("tick cost well under 0.5 ms", us < 150.0, "%.1f us/tick over %d ticks, ended at (%.0f,%.0f)" % [us, n, sim.px, sim.py])


func test_replay() -> void:
	print("[replay]")
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := new_sim(lvl)
	var rep := EEReplay.new()
	var inp := EEInput.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3000:
		if i % 23 == 0:
			inp.left = rng.randf() < 0.4; inp.right = rng.randf() < 0.5; inp.jump = rng.randf() < 0.5
			inp.up = rng.randf() < 0.1; inp.down = rng.randf() < 0.1
			inp.jump_pressed = rng.randf() < 0.2
		inp.god_toggle = i == 1500 or i == 2000
		rep.record(inp)
		sim.tick(inp)
	var h1 := sim.state_hash()
	var fin := Vector4(sim.px, sim.py, sim.speed_x, sim.speed_y)
	rep.meta = {"level": "ex_crew_odyssey", "hash": h1}
	var path := "user://physics_test_replay.eerp"
	check("replay saved", rep.save(path) == OK)
	var bytes := FileAccess.get_file_as_bytes(path).size()
	var rep2 := EEReplay.load_file(path)
	check("replay loaded (%d ticks, %d bytes)" % [rep2.tick_count() if rep2 else -1, bytes], rep2 != null and rep2.tick_count() == 3000 and rep2.frames == rep.frames)
	var sim2 := new_sim(lvl)
	rep2.play_all(sim2)
	check("replay reproduces the run bit-exactly", sim2.state_hash() == h1 and Vector4(sim2.px, sim2.py, sim2.speed_x, sim2.speed_y) == fin and h1 == int(rep2.meta["hash"]),
		"final (%.4f,%.4f) v=(%.6f,%.6f) ticks=%d" % [sim2.px, sim2.py, sim2.speed_x, sim2.speed_y, sim2.ticks()])
	# replaying on the same (already used) sim instance: start() resets it
	rep2.play_all(sim)
	check("replay on a reused sim (reset) is identical", sim.state_hash() == h1)


func test_snapshot() -> void:
	print("[snapshot/restore]")
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := new_sim(lvl)
	var inp := EEInput.new()
	inp.right = true
	run(sim, inp, 400)
	var snap := sim.snapshot()
	inp.jump = true
	run(sim, inp, 300)
	var h := sim.state_hash()
	sim.restore(snap)
	inp.jump = true
	run(sim, inp, 300)
	check("restore() continues bit-identically", sim.state_hash() == h)
	# restoring an OLD snapshot after a divergent branch (coin pickup mutates tiles, queue mutates
	# every tick) must not leak anything from that branch
	var l := make_level(12, 12)
	put(l, 5, 2, 255)
	put(l, 5, 6, 100)
	put(l, 8, 10, 50)
	var s2 := new_sim(l)
	var i2 := EEInput.new()
	run(s2, i2, 5)
	var old := s2.snapshot()
	var h_old := s2.state_hash()
	run(s2, i2, 60)                   # falls through the coin
	i2.right = true
	run(s2, i2, 80)                   # bumps the secret block
	check("branch collected the coin", s2.coins == 1 and s2.is_coin_collected(5, 6))
	s2.restore(old)
	check("old snapshot restored exactly (coin back, hash equal)", s2.state_hash() == h_old and s2.coins == 0 and not s2.is_coin_collected(5, 6) and not s2.is_secret_revealed(8, 10))
	var fresh := new_sim(l)
	var i3 := EEInput.new()
	run(fresh, i3, 5)
	i2.right = false
	run(s2, i2, 200)
	run(fresh, i3, 200)
	check("continuation after restore == fresh run", s2.state_hash() == fresh.state_hash())


## Is the box overlapping any tile with this id?
func overlaps_id(sim: EESim, id: int) -> bool:
	var x0 := int(sim.px) >> 4
	var y0 := int(sim.py) >> 4
	for ty in range(y0, int(ceil((sim.py + 16.0) / 16.0))):
		for tx in range(x0, int(ceil((sim.px + 16.0) / 16.0))):
			if sim.get_tile(tx, ty) == id:
				return true
	return false


func test_key_door_stay_inside() -> void:
	print("[key door: stay inside past the timer]")
	# floor at row 9; red key (4,8); a 5-wide red door (8..12, 8); open to the right
	var l := make_level(40, 10)
	put(l, 2, 8, 255)
	put(l, 4, 8, 6)
	for x in range(8, 13):
		put(l, x, 8, 23)
	var sim := new_sim(l)
	var inp := EEInput.new()
	var ev := {"t": 0, "expired": -1, "door_close": -1}
	sim.sim_event.connect(func(k, d):
		if k == &"key_expired" and ev["expired"] < 0: ev["expired"] = ev["t"]
		elif k == &"door_state" and d["kind"] == &"red" and not d["open"] and ev["door_close"] < 0: ev["door_close"] = ev["t"])
	var tick := func(i: EEInput) -> void:
		ev["t"] = sim.ticks() + 1
		sim.tick(i)
	# walk right into the doors, then release and coast to a stop inside
	inp.right = true
	while sim.px < 8.0 * 16.0 and sim.ticks() < 400:
		tick.call(inp)
	inp.right = false
	for i in 150: tick.call(inp)
	var straddle := fmod(sim.px, 16.0) != 0.0
	check("stopped inside the red door (x=%.2f, straddling two door tiles: %s)" % [sim.px, straddle], overlaps_id(sim, 23) and sim.speed_x == 0.0)
	# wait well past the 5 s key duration while inside
	var ok := true
	for i in 700:
		tick.call(inp)
		if not sim.is_key_active(&"red") or stuck(sim) or ev["expired"] >= 0:
			ok = false
	var door_open := true
	for x in range(8, 13):
		if sim.is_tile_solid_now(x, 8): door_open = false
	check("7 s inside: key stays active, doors stay open, no key_expired, not stuck", ok and door_open)
	check("API while held open: is_key_active true, key_expiry_pending true, key_time_left 0, is_tile_solid_now false",
		sim.key_time_left(&"red") == 0.0 and sim.key_expiry_pending(&"red") and not sim.is_tile_solid_now(10, 8))
	# move around freely inside the door region without leaving it
	var free := true
	var x_before := sim.px
	inp.left = true
	for i in 6:
		tick.call(inp)
		if stuck(sim) or not overlaps_id(sim, 23): free = false
	inp.left = false
	var moved_left := sim.px < x_before
	for i in 60: tick.call(inp)
	check("moves freely inside the open door (still active, never stuck)", free and moved_left and overlaps_id(sim, 23) and sim.is_key_active(&"red") and ev["expired"] < 0,
		"x %.1f -> %.1f" % [x_before, sim.px])
	# walk out to the right; the key must expire on the first tick after the box fully leaves
	var left_tick := -1
	inp.right = true
	for i in 300:
		tick.call(inp)
		if left_tick < 0 and not overlaps_id(sim, 23):
			left_tick = sim.ticks()
		if left_tick > 0 and sim.ticks() > left_tick + 3:
			break
	inp.right = false
	check("walked through and out the far side", left_tick > 0 and sim.px >= 13.0 * 16.0, "x=%.1f" % sim.px)
	check("key_expired + door_state(closed) in the very tick the box leaves the doors, not before",
		ev["expired"] == left_tick and ev["door_close"] == left_tick,
		"left at t=%d, expired at t=%d, door closed at t=%d" % [left_tick, ev["expired"], ev["door_close"]])
	check("door solid again after leaving", sim.is_tile_solid_now(10, 8) and not sim.is_key_active(&"red"))
	# straddling two door tiles exactly (x = 9.5 tiles), key freshly taken
	var s2 := new_sim(l)
	var ev2 := {"t": 0, "expired": -1}
	s2.sim_event.connect(func(k, _d): if k == &"key_expired" and ev2["expired"] < 0: ev2["expired"] = ev2["t"])
	var i2 := EEInput.new()
	run(s2, i2, 20)
	s2.px = 4.0 * 16.0
	s2.tick(i2)
	s2.px = 9.0 * 16.0 + 8.0
	var ok2 := true
	for i in 700:
		ev2["t"] = s2.ticks() + 1
		s2.tick(i2)
		if not s2.is_key_active(&"red") or stuck(s2) or s2.is_tile_solid_now(9, 8) or s2.is_tile_solid_now(10, 8): ok2 = false
	check("straddling doors (9,8)+(10,8) for 7 s: both stay open, key active, not stuck", ok2 and ev2["expired"] < 0 and fmod(s2.px, 16.0) == 8.0,
		"x=%.2f" % s2.px)


func test_key_gate_deferred() -> void:
	print("[key gate: activation deferred while inside the gate]")
	# key (6,8), red gates (7,7),(7,8) right next to it. At x=100 the center is on the key tile
	# while the box overlaps the gate: activating the key would close the gate on the player.
	var l := make_level(20, 10)
	put(l, 2, 8, 255)
	put(l, 6, 8, 6)
	put(l, 7, 8, 26)
	put(l, 7, 7, 26)
	var sim := new_sim(l)
	var inp := EEInput.new()
	var ev := {"t": 0, "on": -1, "key": -1}
	sim.sim_event.connect(func(k, d):
		if k == &"key" and ev["key"] < 0: ev["key"] = ev["t"]
		elif k == &"door_state" and d["kind"] == &"red" and d["open"] and ev["on"] < 0: ev["on"] = ev["t"])
	run(sim, inp, 30)
	sim.px = 100.0
	var ok := true
	for i in 120:
		ev["t"] = sim.ticks() + 1
		sim.tick(inp)
		if sim.is_key_active(&"red") or sim.is_tile_solid_now(7, 8) or stuck(sim):
			ok = false
	check("touched key while overlapping the gate: key NOT active, gate stays open, not stuck", ev["key"] > 0 and ok and overlaps_id(sim, 26),
		"x=%.1f key touched t=%d" % [sim.px, ev["key"]])
	var left_tick := -1
	inp.left = true
	for i in 60:
		ev["t"] = sim.ticks() + 1
		sim.tick(inp)
		if left_tick < 0 and not overlaps_id(sim, 26): left_tick = sim.ticks()
		if ev["on"] > 0: break
	inp.left = false
	check("key activates (gate closes) in the very tick the box leaves the gate",
		left_tick > 0 and ev["on"] == left_tick and sim.is_key_active(&"red") and sim.is_tile_solid_now(7, 8),
		"left t=%d active t=%d" % [left_tick, ev["on"]])


func test_key_door_real_level() -> void:
	print("[key door: real level, demon body]")
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := new_sim(lvl)
	var inp := EEInput.new()
	# a red-door tile in the demon (x 280-340, y 130-199) resting on a solid non-door tile
	var spot := Vector2i(-1, -1)
	var cnt := 0
	for y in range(130, 199):
		for x in range(280, 340):
			if lvl.get_fg(x, y) == 23:
				cnt += 1
				if spot.x < 0 and lvl.get_fg(x, y + 1) != 23 and sim.is_tile_solid_now(x, y + 1) and lvl.get_fg(x, y - 1) == 23:
					spot = Vector2i(x, y)
	check("demon body has red doors (%d tiles); resting spot %s" % [cnt, spot], spot.x >= 0)
	if spot.x < 0:
		return
	var key: Vector2i = lvl.find_all(6)[0]
	sim.px = key.x * 16.0; sim.py = key.y * 16.0
	sim.tick(inp)
	check("red key taken", sim.is_key_active(&"red"))
	sim.px = spot.x * 16.0; sim.py = spot.y * 16.0
	sim.speed_x = 0.0; sim.speed_y = 0.0
	var ev := {"t": 0, "expired": -1}
	sim.sim_event.connect(func(k, _d): if k == &"key_expired" and ev["expired"] < 0: ev["expired"] = ev["t"])
	var ok := true
	for i in 800:
		ev["t"] = sim.ticks() + 1
		sim.tick(inp)
		if not sim.is_key_active(&"red") or stuck(sim) or not overlaps_id(sim, 23):
			ok = false
	check("8 s resting inside the demon's red door: key active, door open, not stuck", ok and not sim.is_tile_solid_now(spot.x, spot.y) and ev["expired"] < 0,
		"at %s pending=%s" % [Vector2i(int(sim.px) >> 4, int(sim.py) >> 4), sim.key_expiry_pending(&"red")])
	# wander (jumping left/right) until the box has left every red door
	var left_tick := -1
	var plan := [[1, 0, 1], [0, 1, 1], [1, 0, 0], [0, 1, 0]]
	for i in 3000:
		var a: Array = plan[(i / 40) % plan.size()]
		inp.left = a[0] == 1; inp.right = a[1] == 1; inp.jump = a[2] == 1
		ev["t"] = sim.ticks() + 1
		sim.tick(inp)
		if overlaps_id(sim, 23):
			if ev["expired"] >= 0: break     # expired while still inside: wrong
		elif left_tick < 0:
			left_tick = sim.ticks()
		if ev["expired"] >= 0: break
	check("after leaving the door the key expires in that same tick, never while inside",
		ev["expired"] > 0 and ev["expired"] == left_tick, "left t=%d expired t=%d at %s" % [left_tick, ev["expired"], Vector2i(int(sim.px) >> 4, int(sim.py) >> 4)])
