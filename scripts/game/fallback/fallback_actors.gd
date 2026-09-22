extends Node3D
## PLACEHOLDER for ActorsView (scripts/fx/actors_view.gd): a glowing sphere for the player.

var _ball: MeshInstance3D

func build(_lvl, _sim) -> void:
	_ball = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2)
	m.emission_energy_multiplier = 1.5
	s.material = m
	_ball.mesh = s
	add_child(_ball)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.5)
	l.omni_range = 6.0
	l.light_energy = 1.5
	l.position = Vector3(0, 0, 0.8)
	_ball.add_child(l)

func update_player(world_pos: Vector3, _sim, _delta: float) -> void:
	if _ball:
		_ball.position = world_pos

func get_player_node() -> Node3D:
	return _ball
