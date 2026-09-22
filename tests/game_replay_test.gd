extends SceneTree
## Headless test of run recording + best-run ghost.
## A) EEReplay round-trip: record a scripted 2000-tick run, save, reload, replay on a fresh sim -> same final state.
## B) Game integration: play 600 scripted ticks, "complete" (save best to a test path), reload it from disk,
##    restart the run and replay the same inputs: the ghost sim must match the player tick-for-tick and the
##    first run's trajectory.
## Run: $G --headless --audio-driver Dummy --path . -s res://tests/game_replay_test.gd

const GameScript := preload("res://scripts/game/game.gd")
const TEST_BEST := "user://test_best.eerp"
var game
var fails := 0

func _init() -> void:
	_part_a()
	GameScript.boot_options = {"skip_title": true, "no_save": true}
	game = load("res://scenes/main.tscn").instantiate()
	game.input_provider = _pattern
	root.add_child(game)
	create_timer(120.0).timeout.connect(func():
		print("REPLAY FAIL: timeout")
		quit(1))
	_part_b()

static func _pattern(t: int) -> Dictionary:
	# walk right, hop, walk left, a god-mode flight segment, then fall back
	var d := {"right": (t % 400) < 220, "left": (t % 400) >= 260 and (t % 400) < 380}
	d.jump = (t % 90) < 12
	d.god = t == 300 or t == 420
	d.up = t > 300 and t < 380
	return d

func _part_a() -> void:
	var lvl := EELevel.load_file("res://levels/ex_crew_odyssey.eelvl")
	var sim := EESim.new(lvl)
	var rec := EEReplay.new()
	var inp := EEInput.new()
	for t in 2000:
		var d := _pattern(t)
		inp.left = d.left; inp.right = d.right; inp.up = d.get("up", false); inp.down = false
		inp.jump = d.jump; inp.jump_pressed = d.jump and not _pattern(t - 1).jump; inp.god_toggle = d.god
		rec.record(inp)
		sim.tick(inp)
	var h := sim.state_hash()
	rec.meta = {"ticks": 2000, "hash": h}
	var err := rec.save("user://test_roundtrip.eerp")
	var r2 := EEReplay.load_file("user://test_roundtrip.eerp")
	var sim2 := EESim.new(lvl)
	r2.play_all(sim2)
	var ok := err == OK and r2 != null and r2.tick_count() == 2000 and sim2.state_hash() == h \
		and sim2.px == sim.px and sim2.py == sim.py and int(r2.meta.ticks) == 2000
	print("A) round-trip %s: bytes=%d final=(%.1f,%.1f) hash %d vs %d" % ["OK" if ok else "FAIL",
		FileAccess.get_file_as_bytes("user://test_roundtrip.eerp").size(), sim2.px, sim2.py, sim2.state_hash(), h])
	if not ok:
		fails += 1

func _part_b() -> void:
	while game.state != 3:
		await process_frame
	var g = game.ghost
	if not g.available:
		print("B) FAIL: ghost module unavailable")
		quit(1)
		return
	g.best_path = TEST_BEST
	if FileAccess.file_exists(TEST_BEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BEST))
	g.best_ticks = -1
	g.best = null
	game.restart_run()
	var run1 := {}
	while game._play_ticks < 600:
		await physics_frame
		run1[game._play_ticks] = Vector2(game.sim.px, game.sim.py)
	# stop ticking the player while we "complete": pause the tree
	paused = true
	var n: int = game._play_ticks
	var new_best: bool = g.on_complete(n)
	var saved := FileAccess.file_exists(TEST_BEST)
	g.load_best()
	print("B) completed %d ticks: new_best=%s saved=%s reloaded best_ticks=%d frames=%d" % [n, new_best, saved, g.best_ticks, g.best.tick_count() if g.best else -1])
	if not (new_best and saved and g.best_ticks == n):
		fails += 1
	paused = false
	game.restart_run()
	var mism_ghost := 0
	var mism_run1 := 0
	var checked := 0
	while game._play_ticks < n:
		await physics_frame
		var t: int = game._play_ticks
		var p := Vector2(game.sim.px, game.sim.py)
		var q := Vector2(g.ghost_sim.px, g.ghost_sim.py)
		if p != q:
			mism_ghost += 1
		if run1.has(t) and run1[t] != p:
			mism_run1 += 1
		checked += 1
	g.update_visual(1.0, 0.016)
	print("B) replay sync: checked=%d ghost!=player: %d  run2!=run1: %d  ghost node=%s visible=%s" % [checked, mism_ghost, mism_run1, g.ghost_node.get_class(), g.ghost_node.visible])
	if mism_ghost > 0 or mism_run1 > 0 or checked < n - 5:
		fails += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BEST))
	print("REPLAY %s" % ("OK" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
