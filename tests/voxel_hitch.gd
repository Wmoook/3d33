extends Node
## Frame-time spikes caused by WorldVoxel after the level is playable: records every frame's wall time from
## ready_to_play until 4 s after the voxel landscape is uploaded (chunk upload + first draw of its materials).
##   bash tools_run_test.sh res://tests/voxel_hitch.tscn
const GameScript := preload("res://scripts/game/game.gd")
var game
var _last := 0
var _frames: Array[float] = []
var _marks := {}

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var novox := "novox" in OS.get_cmdline_user_args()
	if novox:
		WorldVoxel.enabled = false
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	var vx: WorldVoxel = (game.world as WorldView).voxel
	var t_start := Time.get_ticks_msec()
	_last = Time.get_ticks_usec()
	var t_end := -1
	while true:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_frames.append((now - _last) / 1000.0)
		_last = now
		if novox and not _marks.has("ready") and Time.get_ticks_msec() - t_start > 3000:
			_marks["ready"] = _frames.size()
			t_end = Time.get_ticks_msec() + 4000
		if not novox and vx.is_ready and not _marks.has("ready"):
			_marks["ready"] = _frames.size()
			t_end = Time.get_ticks_msec() + 4000
		if t_end > 0 and Time.get_ticks_msec() > t_end:
			break
		if _frames.size() > 5000:
			break
	var worst := 0.0
	var wi := 0
	var over16 := 0
	var over33 := 0
	for i in _frames.size():
		if _frames[i] > worst:
			worst = _frames[i]
			wi = i
		if _frames[i] > 16.7: over16 += 1
		if _frames[i] > 33.3: over33 += 1
	var r: int = _marks.get("ready", -1)
	var after := 0.0
	for i in range(maxi(r, 0), _frames.size()):
		after = maxf(after, _frames[i])
	print("HITCH frames %d, voxel ready at frame %d, worst %.1f ms at frame %d, worst after ready %.1f ms, >16.7: %d, >33.3: %d" % [_frames.size(), r, worst, wi, after, over16, over33])
	var around := []
	for i in range(maxi(r - 3, 0), mini(r + 12, _frames.size())):
		around.append(snappedf(_frames[i], 0.1))
	print("HITCH frames around ready: ", around)
	var spikes := []
	for i in _frames.size():
		if _frames[i] > 33.3:
			spikes.append("%d:%.0f" % [i, _frames[i]])
	print("HITCH spikes (frame:ms): ", spikes)
	get_tree().quit()
