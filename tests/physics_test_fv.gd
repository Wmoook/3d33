extends RefCounted
## Forgotten Veil mechanics tests (purple switches/doors/gates, speed boosts, cyan/magenta/yellow
## keys, pink one-way 1004, coin door 16, piano, invisible gravity 412/414, solidity of the level's
## decorative ids, portals 242/381), synthetic maps plus spots in the real level.
## Run from tests/physics_test.gd (shares its check/make_level/put/new_sim helpers).

var t   # the physics_test.gd SceneTree instance

func _init(harness) -> void:
	t = harness


func run_all() -> void:
	test_purple_switch()
	test_purple_switch_deferred()
	test_speed_boosts()
	test_color_keys()
	test_oneway_1004()
	test_coin_door_16()
	test_piano()
	test_invisible_gravity()
	test_solidity_table()
	test_fv_real_level()


func _events(sim: EESim, kinds: Array) -> Array:
	var evs := []
	sim.sim_event.connect(func(k, d): if kinds.has(k): evs.append([k, d]))
	return evs


func test_purple_switch() -> void:
	print("[purple switch 113 / door 184 / gate 185]")
	var l: EELevel = t.make_level(40, 10)
	t.put(l, 2, 8, 255)
	t.put(l, 5, 8, 113, {"rotation": 3})     # switch id 3
	t.put(l, 10, 8, 184, {"rotation": 3})    # door id 3, in the path
	t.put(l, 20, 5, 185, {"rotation": 3})    # gate id 3, floating
	t.put(l, 15, 5, 184, {"rotation": 4})    # door of another id
	var sim: EESim = t.new_sim(l)
	var evs := _events(sim, [&"switch", &"door_state"])
	var inp := EEInput.new()
	t.check("before: door 3 solid, gate 3 open, switch off", sim.is_tile_solid_now(10, 8) and not sim.is_tile_solid_now(20, 5) and not sim.is_switch_on(3))
	inp.right = true
	var passed := false
	for i in 300:
		sim.tick(inp)
		if sim.px > 11.0 * 16.0: passed = true
		if sim.px > 14.0 * 16.0: inp.right = false
	t.check("switch on: door 3 open, gate 3 closed, door 4 still closed, walked through", passed and sim.is_switch_on(3)
		and not sim.is_tile_solid_now(10, 8) and sim.is_tile_solid_now(20, 5) and sim.is_tile_solid_now(15, 5) and sim.get_tile_number(10, 8) == 3)
	t.check("events: switch{purple,3,on} + door_state{purple,3,open}", evs.size() == 2
		and evs[0][0] == &"switch" and evs[0][1] == {"kind": &"purple", "id": 3, "on": true}
		and evs[1][0] == &"door_state" and evs[1][1] == {"kind": &"purple", "id": 3, "open": true}, str(evs))
	# walk back over the switch: re-entering it toggles it off (Me.touchBlock: !switches[sid])
	inp.left = true
	for i in 300:
		sim.tick(inp)
		if sim.px < 3.0 * 16.0: inp.left = false
	t.check("re-entering the switch toggles it off; door 3 closed again", not sim.is_switch_on(3) and sim.is_tile_solid_now(10, 8)
		and evs.size() == 4 and evs[2][1]["on"] == false and evs[3][1]["open"] == false, str(evs.slice(2)))
	# switches survive death / respawn (only resetPlayer clears Player.switches)
	inp.left = false; inp.right = true
	for i in 60: sim.tick(inp)
	var was_on := sim.is_switch_on(3)
	sim.kill_player()
	for i in 80: sim.tick(EEInput.new())
	t.check("switch state survives death + respawn", was_on and sim.is_switch_on(3) and sim.deaths == 1)
	sim.reset()
	t.check("reset() clears switches", not sim.is_switch_on(3) and sim.is_tile_solid_now(10, 8))


func test_purple_switch_deferred() -> void:
	print("[purple switch: gate closing on the player is deferred]")
	var l: EELevel = t.make_level(20, 10)
	t.put(l, 2, 8, 255)
	t.put(l, 5, 8, 113, {"rotation": 1})
	t.put(l, 6, 8, 185, {"rotation": 1})
	var sim: EESim = t.new_sim(l)
	var evs := _events(sim, [&"switch"])
	var inp := EEInput.new()
	sim.tick(inp)
	# center on the switch tile (5), box overlapping the (open) gate tile 6
	sim.px = 5.0 * 16.0 + 6.0; sim.py = 8.0 * 16.0
	sim.speed_x = 0.0; sim.speed_y = 0.0
	sim.tick(inp)
	var deferred := not sim.is_switch_on(1) and not sim.is_tile_solid_now(6, 8)
	for i in 50: sim.tick(inp)
	t.check("pressed while overlapping gate: stays off (tilequeue retry)", deferred and not sim.is_switch_on(1) and evs.is_empty() and sim.px == 86.0)
	inp.left = true
	var left_tick := -1
	var on_tick := -1
	for i in 60:
		sim.tick(inp)
		if left_tick < 0 and sim.px + 16.0 <= 96.0: left_tick = sim.ticks()
		if on_tick < 0 and sim.is_switch_on(1): on_tick = sim.ticks()
	# Player.tick runs the tilequeue BEFORE moving, so it applies the tick after the box left.
	t.check("switch applies the tick after the box leaves the gate (Player.tilequeue order)", left_tick > 0 and on_tick == left_tick + 1
		and sim.is_tile_solid_now(6, 8) and evs.size() == 1, "left t=%d on t=%d" % [left_tick, on_tick])


func test_speed_boosts() -> void:
	print("[speed boosts 114-117]")
	var l: EELevel = t.make_level(60, 10)
	t.put(l, 2, 8, 255)
	for x in range(6, 40):
		t.put(l, x, 8, 115)
	var sim: EESim = t.new_sim(l)
	var inp := EEInput.new()
	inp.right = true
	var ok := true
	var n_in := 0
	var entered := false
	for i in 200:
		var x0 := sim.px
		sim.tick(inp)
		if sim.current_tile == 115:
			entered = true
			n_in += 1
			if sim.speed_x != 16.0: ok = false
			if n_in > 1 and (sim.px - x0 != 16.0 or sim.morx != 0 or sim.mory != 0): ok = false
		elif entered:
			break
	t.check("115: speed_x == physics_boost (16 px/tick) in every boost tick, 16 px per tick, no gravity", entered and ok and n_in >= 30, "ticks in boost %d" % n_in)
	t.check("115: leaves the boost row at full speed and drags down", sim.speed_x < 16.0 and sim.speed_x > 10.0, "vx=%.4f" % sim.speed_x)
	for c in [[114, Vector2i(30, 5), Vector2(-16, 0)], [116, Vector2i(5, 8), Vector2(0, -16)], [117, Vector2i(5, 2), Vector2(0, 16)]]:
		var lb: EELevel = t.make_level(40, 12)
		t.put(lb, c[1].x, c[1].y, 255)
		var sb: EESim = t.new_sim(lb)
		# the spawn tile is replaced by the boost (placeAtSpawn already ran)
		sb.tiles = sb.tiles.duplicate(); sb.tiles[c[1].y * lb.width + c[1].x] = c[0]
		sb.tick(EEInput.new())
		var ok_b: bool = (sb.speed_x == c[2].x and sb.px == c[1].x * 16.0 + c[2].x) if c[2].x != 0.0 else (sb.speed_y == c[2].y and sb.py == c[1].y * 16.0 + c[2].y)
		t.check("%d: boosted axis speed set to %s, moved 16 px" % [c[0], c[2]], ok_b, "v=(%s,%s) p=(%s,%s)" % [sb.speed_x, sb.speed_y, sb.px, sb.py])


func test_color_keys() -> void:
	print("[cyan/magenta/yellow keys 408-410, doors 1005-1007, gates 1008-1010]")
	for c in [[409, 1006, 1009, &"magenta"], [408, 1005, 1008, &"cyan"], [410, 1007, 1010, &"yellow"]]:
		var l: EELevel = t.make_level(40, 10)
		t.put(l, 2, 8, 255)
		t.put(l, 5, 8, c[0])
		t.put(l, 10, 8, c[1])
		t.put(l, 20, 5, c[2])
		var sim: EESim = t.new_sim(l)
		var evs := _events(sim, [&"key", &"key_expired", &"door_state"])
		var inp := EEInput.new()
		inp.right = true
		var passed := false
		var pick := -1
		var expire := -1
		var open_mid := false
		for i in 800:
			sim.tick(inp)
			if pick < 0 and sim.is_key_active(c[3]):
				pick = sim.ticks()
				open_mid = not sim.is_tile_solid_now(10, 8) and sim.is_tile_solid_now(20, 5)
			if pick > 0 and expire < 0 and not sim.is_key_active(c[3]): expire = sim.ticks()
			if sim.px > 11.0 * 16.0: passed = true
			if sim.px > 30.0 * 16.0: inp.right = false
		var kinds := evs.map(func(e): return e[0])
		t.check("%s key: door opens + gate closes, walked through, expires after 5 s" % c[3], passed and open_mid
			and expire - pick >= 499 and expire - pick <= 501 and sim.is_tile_solid_now(10, 8) and not sim.is_tile_solid_now(20, 5)
			and kinds == [&"key", &"door_state", &"door_state", &"key_expired"] and evs[0][1]["color"] == c[3],
			"%d ticks, %s" % [expire - pick, kinds])


func test_oneway_1004() -> void:
	print("[pink one-way 1004 (rotatable half: rotation from extra)]")
	# falling onto it: rot 1 (up), 0 (left), 2 (right) hold; rot 3 (down) lets you fall through
	var res := {}
	for rot in [0, 1, 2, 3]:
		var l: EELevel = t.make_level(10, 12)
		t.put(l, 5, 2, 255)
		t.put(l, 5, 8, 1004, {"rotation": rot})
		var sim: EESim = t.new_sim(l)
		t.run(sim, EEInput.new(), 200)
		res[rot] = sim.py
	t.check("falling onto 1004: rot 0/1/2 land on it, rot 3 falls through", res[0] == 112.0 and res[1] == 112.0 and res[2] == 112.0 and res[3] == 160.0, str(res))
	# rot 1 from below: jump through, land on top
	var lj: EELevel = t.make_level(10, 12)
	t.put(lj, 5, 10, 255)
	t.put(lj, 5, 8, 1004, {"rotation": 1})
	var sj: EESim = t.new_sim(lj)
	var ij := EEInput.new()
	t.run(sj, ij, 30)
	ij.jump = true
	t.run(sj, ij, 3)
	ij.jump = false
	t.run(sj, ij, 200)
	t.check("rot 1: jump through from below, land on top", sj.py == 7.0 * 16.0 and sj.on_ground, "y=%s" % sj.py)
	# rot 0 (left): passable moving left, a wall moving right
	for dir in [-1, 1]:
		var l: EELevel = t.make_level(20, 10)
		t.put(l, 14 if dir < 0 else 6, 8, 255)
		t.put(l, 10, 8, 1004, {"rotation": 0})
		var sim: EESim = t.new_sim(l)
		var inp := EEInput.new()
		inp.left = dir < 0; inp.right = dir > 0
		t.run(sim, inp, 150)
		if dir < 0:
			t.check("rot 0: walking left passes through", sim.px < 9.0 * 16.0, "x=%s" % sim.px)
		else:
			t.check("rot 0: walking right is blocked", sim.px == 9.0 * 16.0, "x=%s" % sim.px)


func test_coin_door_16() -> void:
	print("[coin door 43 needing 16 coins]")
	for n in [16, 15]:
		var l: EELevel = t.make_level(10, 30)
		t.put(l, 5, 1, 255)
		for k in n:
			t.put(l, 5, 2 + k, 100)
		t.put(l, 5, 20, 43, {"rotation": 16})
		var sim: EESim = t.new_sim(l)
		var evs := _events(sim, [&"door_state"])
		t.run(sim, EEInput.new(), 400)
		if n == 16:
			t.check("16 coins collected in a fall -> door 16 opens -> lands on the floor", sim.coins == 16 and sim.py == 27.0 * 16.0
				and evs.size() == 1 and evs[0][1] == {"kind": &"coin", "open": true, "count": 16}, "coins=%d y=%s %s" % [sim.coins, sim.py, evs])
		else:
			t.check("15 coins -> stands on door 16", sim.coins == 15 and sim.py == 19.0 * 16.0 and evs.is_empty(), "y=%s" % sim.py)


func test_piano() -> void:
	print("[piano 77: non-solid, note event]")
	for god in [false, true]:
		var l: EELevel = t.make_level(20, 10)
		t.put(l, 2, 8, 255)
		t.put(l, 6, 8, 77, {"rotation": 14})
		t.put(l, 7, 8, 77, {"rotation": 9})
		var sim: EESim = t.new_sim(l)
		if god: sim.set_god_mode(true)
		var evs := _events(sim, [&"piano"])
		var inp := EEInput.new()
		inp.right = true
		for i in 100:
			sim.tick(inp)
			if sim.px > 10.0 * 16.0: inp.right = false
		var notes := evs.map(func(e): return e[1]["note"])
		t.check("piano notes [14, 9] on entering each tile, walked through%s" % (" (god mode)" if god else ""), notes == [14, 9]
			and evs[0][1]["tile"] == Vector2i(6, 8) and sim.px > 8.0 * 16.0, str(evs))


func _trace(id: int, spawn: Vector2i, column: Array) -> Array:
	var l: EELevel = t.make_level(10, 20)
	for p in column:
		t.put(l, p.x, p.y, id)
	t.put(l, spawn.x, spawn.y, 255)
	var sim: EESim = t.new_sim(l)
	var out := []
	var evs := _events(sim, [&"blink"])
	sim.tiles = sim.tiles.duplicate(); sim.tiles[spawn.y * l.width + spawn.x] = id if column.has(spawn) else 0
	for i in 150:
		sim.tick(EEInput.new())
		out.append([sim.px, sim.py, sim.speed_x, sim.speed_y, sim.gravity_dir])
	return [out, sim, evs]


func test_invisible_gravity() -> void:
	print("[invisible gravity 412 (up) / 414 (dot)]")
	var col := []
	for y in range(1, 12): col.append(Vector2i(5, y))
	var a := _trace(412, Vector2i(5, 10), col)
	var b := _trace(2, Vector2i(5, 10), col)
	var sa: EESim = a[1]
	t.check("412 == up arrow 2 (identical trajectory), rests on the ceiling", a[0] == b[0] and sa.py == 16.0 and sa.on_ground and sa.gravity_dir == Vector2i(0, -1), "y=%s" % sa.py)
	t.check("412 blink event on entering", a[2].size() >= 1 and a[2][0][1]["id"] == 412, str(a[2].slice(0, 2)))
	var c := _trace(414, Vector2i(5, 5), [Vector2i(5, 5)])
	var d := _trace(4, Vector2i(5, 5), [Vector2i(5, 5)])
	var sc: EESim = c[1]
	t.check("414 == dot 4 (identical), zero-g hover", c[0] == d[0] and absf(sc.py - 80.0) < 16.0 and sc.speed_y == 0.0 and sc.gravity_dir == Vector2i.ZERO, "y=%s" % sc.py)


func test_solidity_table() -> void:
	print("[solidity per ItemId.isSolid]")
	var l: EELevel = t.make_level(4, 4)
	var sim: EESim = t.new_sim(l)
	var bad := []
	for id in [68, 69, 223, 224, 272, 85, 86, 87, 88, 89, 90, 77, 83, 44, 45, 47, 48, 35, 36, 34, 1004, 1006, 184, 185, 43, 113, 115, 409, 381, 242, 412, 414, 121, 100, 101, 255, 5, 6, 8, 25, 28]:
		# ItemId.isSolid, recomputed: 9-97 / 122-217 / 1001-1499, minus 77, 83 and climbables
		var ref := ((9 <= id and id <= 97) or (122 <= id and id <= 217) or (1001 <= id and id <= 1499)) and id != 77 and id != 83
		if (sim._flag(id) & EESim.F_SOLID != 0) != ref: bad.append(id)
	t.check("solid flags match ItemId.isSolid (68/69 & scifi 85-90 solid; 223/224/272/77 not)", bad.is_empty(), str(bad))
	var jt := []
	for id in [89, 90, 1004, 62, 88, 86]:
		if sim._flag(id) & EESim.F_JUMPTHRU != 0: jt.append(id)
	t.check("one-ways: 89, 90, 1004, 62 (canJumpThroughFromBelow); 86/88 plain solid", jt == [89, 90, 1004, 62], str(jt))


func test_fv_real_level() -> void:
	print("[Forgotten Veil real-level spots]")
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var sim: EESim = t.new_sim(lvl)
	var inp := EEInput.new()
	t.check("spawn (2,56)", sim.px == 32.0 and sim.py == 56.0 * 16.0)
	t.check("209 portals indexed (187 x 242 + 22 x 381)", sim._portals.size() == 209 and lvl.find_all(242).size() == 187 and lvl.find_all(381).size() == 22)
	t.check("16 gold + 8 blue coins; coin door (50,55) needs 16", lvl.find_all(100).size() == 16 and lvl.find_all(101).size() == 8 and sim.get_tile_number(50, 55) == 16)
	sim.coins = 15
	var solid15 := sim.is_tile_solid_now(50, 55)
	sim.coins = 16
	t.check("coin door (50,55): solid at 15 coins, open at 16", solid15 and not sim.is_tile_solid_now(50, 55))
	sim.reset()
	t.check("1004 at (199,88): one-way, rotation 0", sim.is_tile_one_way(199, 88) and sim.get_tile_number(199, 88) == 0)
	# purple switch id 1 at (199,42) -> purple doors id 1 (row 89) open; id 0 doors/gates untouched
	var evs := _events(sim, [&"switch", &"portal"])
	sim.tick(inp)                            # at spawn: clears lastPortal
	var closed_before := sim.is_tile_solid_now(190, 89)
	sim.px = 199.0 * 16.0; sim.py = 42.0 * 16.0; sim.speed_x = 0.0; sim.speed_y = 0.0
	sim.tick(inp)
	t.check("real switch (199,42) id 1 opens purple doors row 89; id-0 door (331,132) + gate (287,130) unchanged", closed_before
		and sim.is_switch_on(1) and not sim.is_tile_solid_now(190, 89) and sim.is_tile_solid_now(331, 132)
		and not sim.is_tile_solid_now(287, 130) and evs.size() == 1 and evs[0][1]["id"] == 1, str(evs))
	# invisible portal row under those doors: (190,90) id 400 -> 401 at (182,83)
	evs.clear()
	sim.px = 190.0 * 16.0; sim.py = 90.0 * 16.0; sim.speed_x = 0.0; sim.speed_y = 0.0
	sim.tick(inp)
	t.check("invisible portal (190,90) 400->401 lands on (182,83)", evs.size() == 1 and evs[0][1]["to"] == Vector2i(182, 83)
		and sim.px == 182.0 * 16.0 and sim.py >= 83.0 * 16.0, str(evs))
	# 242 portal (1,15) id 92 -> 93 at (195,39)
	evs.clear()
	for i in 3: sim.tick(inp)            # step off the (inert) arrival portal
	sim.px = 1.0 * 16.0; sim.py = 15.0 * 16.0; sim.speed_x = 0.0; sim.speed_y = 0.0
	sim.tick(inp)
	t.check("portal (1,15) 92->93 lands on (195,39)", evs.size() >= 1 and evs[0][1]["to"] == Vector2i(195, 39), str(evs))
	# magenta key (218,43) opens the magenta door (209,88)
	sim.px = 218.0 * 16.0; sim.py = 43.0 * 16.0
	sim.tick(inp)
	t.check("magenta key (218,43) opens magenta door (209,88)", sim.is_key_active(&"magenta") and not sim.is_tile_solid_now(209, 88))
	# cost: 3000 random-input ticks on this level
	var s2: EESim = t.new_sim(lvl)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var ri := EEInput.new()
	var t0 := Time.get_ticks_usec()
	for i in 3000:
		if i % 20 == 0:
			ri.left = rng.randf() < 0.4; ri.right = rng.randf() < 0.5; ri.jump = rng.randf() < 0.3
		s2.tick(ri)
	var us := float(Time.get_ticks_usec() - t0) / 3000.0
	t.check("tick cost on Forgotten Veil < 60 us", us < 60.0, "%.1f us/tick" % us)
