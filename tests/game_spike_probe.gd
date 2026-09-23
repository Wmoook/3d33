extends Node
## Frame-spike bisection (tools_run_test.sh): FV gameplay, idle, 6 s of frames per configuration; logs spikes,
## their period, and GPU/CPU render time at the spike frames.  -- off=hud,zone,world_focus,actors,audio,minimap,ui
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var off: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("off="):
			off = Array(a.trim_prefix("off=").split(",", false))
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true, "dbg_off": off}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	if "audio" in off:
		game.audio.process_mode = Node.PROCESS_MODE_DISABLED
		for c in game.audio.get_children():
			if c is AudioStreamPlayer:
				c.stop()
	if "minimap" in off:
		game.minimap.process_mode = Node.PROCESS_MODE_DISABLED
	if "ui" in off:
		game._ui.visible = false
		for c in game._ui.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _secs(3.0)
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
	var spikes: Array[int] = []
	for i in frames.size():
		if frames[i] > 40.0:
			spikes.append(i)
	var gaps := []
	for i in range(1, spikes.size()):
		gaps.append(spikes[i] - spikes[i - 1])
	var sdesc := []
	for i in spikes.slice(0, 12):
		sdesc.append("%d:%.0fms(gpu %.1f cpu %.1f)" % [i, frames[i], gpu[i], cpu[i]])
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= maxf(frames.size(), 1)
	print("SPIKE off=%s frames=%d avg=%.2fms spikes>40ms=%d gaps=%s" % [off, frames.size(), avg, spikes.size(), gaps.slice(0, 20)])
	print("SPIKE detail: ", sdesc)
	get_tree().quit()
func _secs(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await get_tree().process_frame
