extends Node
## Lists every visible 3D geometry near the FV spawn (actors + world) to identify stray objects.
const GameScript := preload("res://scripts/game/game.gd")
var game
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	GameScript.boot_options = {"no_save": true, "quality": 3, "level": "forgotten_veil", "skip_title": true}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await game.ready_to_play
	game.input_provider = func(_t: int) -> Dictionary: return {}
	await get_tree().create_timer(3.0).timeout
	var ball: Vector3 = game.actors.player.global_position
	print("PROBE ball ", ball, " sim ", game.sim.px / 16.0, ",", game.sim.py / 16.0)
	_scan(game, ball)
	get_tree().quit()
func _scan(n: Node, ball: Vector3) -> void:
	if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
		var g := n as GeometryInstance3D
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm:
				var c := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				for i in mini(c, 20000):
					var p: Vector3 = g.global_transform * mm.get_instance_transform(i).origin
					if absf(p.x - ball.x) < 2.5 and p.y - ball.y > -1.0 and p.y - ball.y < 5.0:
						print("PROBE MM ", n.get_path(), " inst ", i, " at ", p - ball)
		else:
			var p := g.global_position
			if absf(p.x - ball.x) < 3.0 and p.y - ball.y > -1.5 and p.y - ball.y < 6.0:
				print("PROBE ", n.get_class(), " ", n.get_path(), " at ", p - ball)
	for c in n.get_children():
		_scan(c, ball)
