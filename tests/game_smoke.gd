extends SceneTree
## Headless smoke test for the game shell: boots main.tscn with the title skipped, runs ~300 sim ticks
## of scripted input (right, jump, left, god-mode toggle), prints positions + module status.
## Run: $G --headless --audio-driver Dummy --path . -s res://tests/game_smoke.gd

const GameScript := preload("res://scripts/game/game.gd")

var game
var _log_ticks := {}
var _t0 := 0

func _init() -> void:
	GameScript.boot_options = {"skip_title": true, "no_save": true}
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	game.input_provider = _script_input
	root.add_child(game)
	game.ready_to_play.connect(_on_ready)
	_t0 = Time.get_ticks_msec()
	create_timer(90.0).timeout.connect(func():
		print("SMOKE FAIL: timeout, state=", game.debug_state())
		quit(1))

func _script_input(tick: int) -> Dictionary:
	var d := {}
	if tick < 120:
		d.right = true
	elif tick < 200:
		d.left = true
	d.jump = (tick >= 40 and tick < 60) or (tick >= 150 and tick < 165)
	d.god = tick == 230 or tick == 280
	if tick >= 231 and tick < 280:
		d.up = true
	return d

func _on_ready() -> void:
	print("SMOKE booted in %d ms, modules=%s" % [Time.get_ticks_msec() - _t0, game.modules])
	_run()

func _run() -> void:
	var last := -1
	while game.debug_state().tick < 300:
		await process_frame
		var s: Dictionary = game.debug_state()
		if s.tick / 25 != last:
			last = s.tick / 25
			print("tick %3d  pos=(%.1f, %.1f)  coins=%d  god=%s  zone=%s" % [s.tick, s.px, s.py, s.coins, s.god, s.zone])
	# exercise pause / minimap / restart paths
	game._pause()
	await process_frame
	game._resume()
	game.minimap.toggle()
	game.restart_run()
	await process_frame
	print("after restart: ", game.debug_state())
	print("SMOKE OK")
	quit(0)
