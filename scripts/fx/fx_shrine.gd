class_name FxShrine
extends Node3D
## Summit shrine for non-Odyssey levels: the finish block 121 becomes the winner's SILVER CROWN relic,
## floating and slowly turning above its peak inside a soft pillar of light that rises into the sky
## (visible from far away), with a gleam and wind-blown petals. On sim_event &"complete" it plays the
## CROWNING (driven by _process time; the sim is frozen meanwhile): 0-1.5 s the crown lifts and a surge of
## light runs up the pillar, 1.5-3.0 s it flies in an arc onto the ball's head, where the ball's own silver
## crown then snaps on (FxPlayerBall.hold_silver_crown / silver_snap).

const PILLAR_H := 70.0
const CROWN_SCALE := 1.25
const LIFT_T := 1.5
const FLY_T := 1.5

var lvl: EELevel
var sim
var player: FxPlayerBall
var bursts: FxBursts
var _shrines: Array = []     # {root, crown, pillar_mat, glint_mat, base: Vector3}
var _crowning := -1.0        # time since complete (-1 = idle)
var _active: Dictionary = {}
var _from := Vector3.ZERO

func build(level: EELevel, s, ball: FxPlayerBall, fx_bursts: FxBursts) -> void:
	lvl = level
	sim = s
	player = ball
	bursts = fx_bursts
	for t in lvl.find_all(121):
		_build_shrine(t)

func _build_shrine(t: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "SummitShrine"
	root.position = EECoords.tile_center(t.x, t.y, -0.15)
	add_child(root)
	# pillar of light from the peak into the sky
	var pillar := MeshInstance3D.new()
	pillar.name = "LightPillar"
	var pq := QuadMesh.new()
	pq.size = Vector2(3.2, PILLAR_H)
	pillar.mesh = pq
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://shaders/fx/light_pillar.gdshader")
	pillar.material_override = pm
	pillar.position = Vector3(0, PILLAR_H * 0.5 - 0.3, -0.6)
	pillar.extra_cull_margin = 200.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pillar)
	# soft dark backing so the silver reads against the bright sky
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(1.9, 1.9)
	back.mesh = bq
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/fx/glyph_halo.gdshader")
	bm.set_shader_parameter("strength", 0.7)
	back.material_override = bm
	back.scale = Vector3.ONE * 2.8
	back.position = Vector3(0, 0.55, -0.4)
	root.add_child(back)
	# the crown relic
	var crown := MeshInstance3D.new()
	crown.name = "CrownRelic"
	crown.mesh = FxMeshes.crown()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.93, 0.95, 1.0)
	metal.metallic = 1.0
	metal.roughness = 0.12
	metal.emission_enabled = true
	metal.emission = Color(0.75, 0.82, 1.0)
	metal.emission_energy_multiplier = 0.5
	var gem := StandardMaterial3D.new()
	gem.albedo_color = Color(0.35, 0.6, 1.0)
	gem.emission_enabled = true
	gem.emission = Color(0.4, 0.7, 1.0)
	gem.emission_energy_multiplier = 2.2
	crown.set_surface_override_material(0, metal)
	crown.set_surface_override_material(1, gem)
	crown.scale = Vector3.ONE * CROWN_SCALE
	root.add_child(crown)
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(2.6, 2.6)
	halo.mesh = hq
	var hm := ShaderMaterial.new()
	hm.shader = preload("res://shaders/fx/glow_sprite.gdshader")
	hm.set_shader_parameter("color", Color(0.8, 0.9, 1.0))
	hm.set_shader_parameter("intensity", 0.3)
	halo.material_override = hm
	halo.position = Vector3(0, 0.5, -0.3)
	root.add_child(halo)
	var glint := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(2.2, 2.2)
	glint.mesh = gq
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/fx/star_glint.gdshader")
	gm.set_shader_parameter("color", Color(0.9, 0.95, 1.0))
	gm.set_shader_parameter("period", 2.6)
	glint.material_override = gm
	glint.position = Vector3(0.3, 0.9, 0.3)
	root.add_child(glint)
	var l := OmniLight3D.new()
	l.light_color = Color(0.85, 0.9, 1.0)
	l.light_energy = 0.7
	l.omni_range = 5.0
	l.shadow_enabled = false
	l.position = Vector3(0, 0.6, 0.8)
	root.add_child(l)
	var petals := _petals()
	petals.position = Vector3(0, 0.2, 0.2)
	root.add_child(petals)
	var rise := _rising_sparks()
	rise.position = Vector3(0, 0.5, -0.2)
	root.add_child(rise)
	_shrines.append({"root": root, "crown": crown, "pillar": pm, "glint": gm, "halo": hm, "light": l,
		"base": Vector3(0, 0.55, 0), "rise": rise, "tile": t})

## Wind-blown petals streaming off the peak.
func _petals() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ShrinePetals"
	p.amount = 26
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-30, -10, -4), Vector3(40, 20, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.0, 0.6, 0.6)
	pm.direction = Vector3(-1, 0.35, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(-0.6, -0.12, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.3
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -120.0
	pm.angular_velocity_max = 120.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.78, 0.86), Color(1.0, 0.92, 0.95), Color(0.98, 0.7, 0.8)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_initial_ramp = gt
	var c := Curve.new()
	c.add_point(Vector2(0, 0)); c.add_point(Vector2(0.1, 1)); c.add_point(Vector2(0.85, 1)); c.add_point(Vector2(1, 0))
	var ct := CurveTexture.new(); ct.curve = c
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.2)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/leaf.gdshader")
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Sparks that stream up the pillar (a trickle always, a flood during the crowning).
func _rising_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "PillarSparks"
	p.amount = 60
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.visibility_aabb = AABB(Vector3(-4, -2, -3), Vector3(8, 60, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.3, 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, 1.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.95, 0.97, 1.0, 1), Color(1.0, 0.9, 0.7, 0)])
	var gt := GradientTexture1D.new(); gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.3)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/particle.gdshader")
	m.set_shader_parameter("intensity", 3.0)
	m.set_shader_parameter("streak", 1.0)
	q.material = m
	p.draw_pass_1 = q
	p.amount_ratio = 0.25
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## sim_event &"complete": start the crowning at the shrine that was touched (or the nearest one).
func on_complete(data: Dictionary) -> void:
	if _shrines.is_empty() or _crowning != -1.0:
		return   # already crowning / crowned (a restart resets via reset_if_needed)
	_active = _shrines[0]
	var tile = data.get("tile")
	if tile is Vector2i:
		for sh in _shrines:
			if sh.tile == tile:
				_active = sh
	_crowning = 0.0
	if player:
		player.hold_silver_crown = true
	_from = (_active.crown as Node3D).global_position
	if bursts:
		bursts.flash(_from, Color(0.85, 0.92, 1.0), 6.0, 1.2, 10.0)
		bursts.play(&"crown", _from, Vector3.UP, Color(0.85, 0.92, 1.0))

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for sh in _shrines:
		var c: MeshInstance3D = sh.crown
		if sh == _active and _crowning >= 0.0:
			continue
		c.position = sh.base + Vector3(0, sin(t * 1.3) * 0.08, 0)
		c.rotation.y = t * 0.7
	if _crowning < 0.0:
		return
	_crowning += minf(delta, 0.05)
	var k := _crowning
	var crown: MeshInstance3D = _active.crown
	var pm: ShaderMaterial = _active.pillar
	pm.set_shader_parameter("burst", clampf(1.0 - absf(k - 0.9) / 1.2, 0.0, 1.0))
	pm.set_shader_parameter("burst_h", clampf(k / 1.4, 0.0, 1.0))
	(_active.rise as GPUParticles3D).amount_ratio = 1.0 if k < 2.0 else 0.25
	if k < LIFT_T:
		var e := smoothstep(0.0, LIFT_T, k)
		crown.position = _active.base + Vector3(0, e * 1.3, 0)
		crown.rotation.y += delta * (0.7 + e * 6.0)
		crown.scale = Vector3.ONE * CROWN_SCALE * (1.0 + 0.25 * sin(e * PI))
		_from = crown.global_position
	elif k < LIFT_T + FLY_T:
		var f := (k - LIFT_T) / FLY_T
		var e := f * f * (3.0 - 2.0 * f)
		var target := _head_pos()
		var mid := _from.lerp(target, 0.5) + Vector3(0, 2.5, 0.8)
		var a := _from.lerp(mid, e)
		var b := mid.lerp(target, e)
		crown.global_position = a.lerp(b, e)
		crown.rotation.y += delta * (6.0 * (1.0 - e) + 0.8)
		crown.scale = Vector3.ONE * lerpf(CROWN_SCALE, 0.5, e)
		(_active.halo as ShaderMaterial).set_shader_parameter("intensity", 0.55 * (1.0 - e))
	else:
		crown.visible = false
		if player:
			player.silver_snap = true
			player.hold_silver_crown = false
			player.on_happy(2.0)
		if bursts:
			bursts.flash(_head_pos(), Color(0.9, 0.95, 1.0), 5.0, 0.8, 8.0)
			bursts.play(&"coin_ring", _head_pos(), Vector3.UP, Color(0.9, 0.95, 1.0))
		_crowning = -2.0   # done; reset_if_needed() brings the relic back after a restart

func _head_pos() -> Vector3:
	if player == null:
		return _from
	var up := player.global_transform.basis.y
	var fr = player.get("_frame")
	if fr is Node3D:
		up = (fr as Node3D).global_transform.basis.y.normalized()
	return player.global_position + up * 0.62

## Restart (respawn with the crown gone): the relic returns to its peak.
func reset_if_needed() -> void:
	if _crowning != -2.0 or sim == null:
		return
	if not bool(sim.get("has_silver_crown")):
		var crown: MeshInstance3D = _active.crown
		crown.visible = true
		crown.scale = Vector3.ONE * CROWN_SCALE
		(_active.halo as ShaderMaterial).set_shader_parameter("intensity", 0.55)
		_crowning = -1.0
		if player:
			player.silver_snap = false
