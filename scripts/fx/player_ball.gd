class_name FxPlayerBall
extends Node3D
## The 3D hero ball. Node origin = ball center (world units). Driven by ActorsView.update_player().
## Hierarchy: self (position) -> _frame (rotates so local -y = gravity) -> _body (squash/stretch) + crown.
## Face state is procedural in player_ball.gdshader; this script animates its uniforms.

const BALL_SHADER := preload("res://shaders/fx/player_ball.gdshader")
const AURA_SHADER := preload("res://shaders/fx/god_aura.gdshader")
const RADIUS := 0.5
## Visual layer used only by the ball, so its own key light can target it exclusively.
const BALL_LAYER := 1 << 19
## Render layer used by this ball's own lights (set before adding to the tree; tests give each ball its own).
var ball_layer := BALL_LAYER

var bursts: FxBursts

var _frame: Node3D
var _body: MeshInstance3D
var _mat: ShaderMaterial
var _env_light: OmniLight3D
var _key_light: OmniLight3D
var _rim_light: OmniLight3D
var _halo: MeshInstance3D
var _crown: MeshInstance3D
var _silver_crown: MeshInstance3D
var _aura: MeshInstance3D
var _aura_mat: ShaderMaterial
var _trail: FxTrail

# motion state
var _has_prev := false
var _prev_pos := Vector3.ZERO
var _vel := Vector3.ZERO           # world units / s (smoothed)
var _grav := Vector2(0, -1)        # world-space gravity dir (y up), last non-zero
var _grav_angle := 0.0
var _roll := 0.0
var _roll_vel := 0.0
var _on_ground := false
var _was_ground := false
# squash spring (positive = stretched along gravity axis)
var _sq := 0.0
var _sq_v := 0.0
# expression state
var _blink_t := 2.0
var _blink := 0.0
var _squeeze := 0.0
var _happy := 0.0
var _happy_t := 0.0
var _wide := 0.0
var _gasp := 0.0
var _grin := 0.0
var _dead := 0.0
var _look := Vector2.ZERO
var _god := 0.0
var _crown_k := 0.0
var _silver_k := 0.0
# death / respawn
var _dying := false
var _death_t := 0.0
var _materialize := 1.0
var _glow_flash := 0.0
## Ghost replay ball: translucent + desaturated, no lights/trail/bursts/aura. Set before adding to the tree.
var ghost := false
## Ball-light shadows (quality presets switch this via ActorsView.set_ball_shadows).
var shadows_default := true
## Ghost fade (shell sets 0..1 at replay start/end).
var modulate_alpha := 1.0:
	set(v):
		modulate_alpha = clampf(v, 0.0, 1.0)
		if _mat and ghost:
			_mat.set_shader_parameter("ghost_alpha", ghost_alpha * modulate_alpha)
			visible = modulate_alpha > 0.001
var ghost_alpha := 0.35
## Test hook: when non-empty, these uniform values override the automatic expression.
var face_override := {}

func _ready() -> void:
	_frame = Node3D.new()
	add_child(_frame)
	_body = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = RADIUS
	sph.height = RADIUS * 2.0
	sph.radial_segments = 96
	sph.rings = 48
	_body.mesh = sph
	_mat = ShaderMaterial.new()
	_mat.shader = _ghost_shader() if ghost else BALL_SHADER
	_body.material_override = _mat
	_body.layers = ball_layer
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.add_child(_body)

	# Light the ball carries: lights the world around it (not the ball itself) with shadows.
	_env_light = OmniLight3D.new()
	_env_light.light_color = Color(1.0, 0.8, 0.5)
	_env_light.light_energy = 1.0
	_env_light.omni_range = 6.0
	_env_light.omni_attenuation = 2.0
	# Shadows on at High/Ultra (world supplies a cheap shadow-only terrain proxy); presets toggle set_shadows().
	_env_light.shadow_enabled = shadows_default
	_env_light.shadow_bias = 0.06
	# dual-paraboloid = 2 shadow passes instead of 6; the world's moon-occluder curtain (layer 20) never casts
	_env_light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	_env_light.shadow_caster_mask = 0xFFFFFFFF & ~(1 << 19)
	_env_light.light_cull_mask = 0xFFFFF & ~ball_layer
	_env_light.position = Vector3(0, 0.15, 1.1)
	add_child(_env_light)
	# Soft character key light: only lights the ball (layer), from front-top-left.
	_key_light = OmniLight3D.new()
	_key_light.light_color = Color(1.0, 0.96, 0.9)
	_key_light.light_energy = 1.0
	_key_light.omni_range = 4.0
	_key_light.omni_attenuation = 1.0
	_key_light.light_specular = 1.2
	_key_light.shadow_enabled = false
	_key_light.light_cull_mask = ball_layer
	_key_light.position = Vector3(-0.9, 1.1, 1.6)
	add_child(_key_light)
	# Cool back/rim light (ball layer only) so the silhouette always separates from dark caves.
	_rim_light = OmniLight3D.new()
	_rim_light.light_color = Color(0.72, 0.84, 1.0)
	_rim_light.light_energy = 2.6
	_rim_light.omni_range = 2.6
	_rim_light.omni_attenuation = 1.2
	_rim_light.shadow_enabled = false
	_rim_light.light_cull_mask = ball_layer
	_rim_light.position = Vector3(0.7, 0.9, -1.1)
	add_child(_rim_light)
	# Soft warm presence glow behind the ball.
	_halo = MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(2.4, 2.4)
	_halo.mesh = hq
	var hm := ShaderMaterial.new()
	hm.shader = preload("res://shaders/fx/glow_sprite.gdshader")
	hm.set_shader_parameter("color", Color(1.0, 0.7, 0.25))
	hm.set_shader_parameter("intensity", 0.07)
	_halo.material_override = hm
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0, 0, -0.6)
	add_child(_halo)

	_crown = _make_crown(false)
	_silver_crown = _make_crown(true)

	_aura = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 4.2)
	_aura.mesh = q
	_aura_mat = ShaderMaterial.new()
	_aura_mat.shader = AURA_SHADER
	_aura_mat.set_shader_parameter("ball_r", RADIUS / 4.2 * 1.02)
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.position = Vector3(0, 0, -0.05)
	_aura.visible = false
	add_child(_aura)

	_trail = FxTrail.new()
	add_child(_trail)

	if ghost:
		for n in [_env_light, _key_light, _rim_light, _halo, _aura, _trail]:
			n.queue_free()
		_env_light = null
		_trail = null
		bursts = null

func set_shadows(on: bool) -> void:
	shadows_default = on
	if _env_light:
		_env_light.shadow_enabled = on

static var _ghost_sh: Shader
## The hero shader, but alpha-blended and desaturated (built once from the hero code).
static func _ghost_shader() -> Shader:
	if _ghost_sh == null:
		var code := BALL_SHADER.code
		code = code.replace("render_mode blend_mix, depth_draw_opaque,", "render_mode blend_mix, depth_draw_always,")
		code = code.replace("uniform float dissolve = 0.0;", "uniform float dissolve = 0.0;
uniform float ghost_alpha = 0.35;")
		code = code.replace("	ALBEDO = col;", "	col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))), 0.7);
	ALBEDO = col;")
		code = code.replace("	EMISSION = emis;", "	EMISSION = emis * 0.4;
	ALPHA = ghost_alpha;")
		_ghost_sh = Shader.new()
		_ghost_sh.code = code
	return _ghost_sh

## Drive a ghost ball from a second EESim (called by the shell every frame).
func update_ghost(world_pos: Vector3, ghost_sim, delta: float) -> void:
	update_from_sim(world_pos, ghost_sim, delta)

func _make_crown(silver: bool) -> MeshInstance3D:
	var c := MeshInstance3D.new()
	c.mesh = FxMeshes.crown()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.86, 0.87, 0.92) if silver else Color(1.0, 0.74, 0.22)
	metal.metallic = 1.0
	metal.roughness = 0.3
	metal.emission_enabled = true
	metal.emission = Color(0.35, 0.4, 0.5) if silver else Color(0.55, 0.3, 0.02)
	metal.emission_energy_multiplier = 0.35
	metal.rim_enabled = true
	metal.rim = 0.6
	var gem := StandardMaterial3D.new()
	gem.albedo_color = Color(0.3, 0.6, 1.0) if silver else Color(0.9, 0.08, 0.12)
	gem.metallic = 0.0
	gem.roughness = 0.05
	gem.emission_enabled = true
	gem.emission = gem.albedo_color
	gem.emission_energy_multiplier = 0.45
	c.set_surface_override_material(0, metal)
	c.set_surface_override_material(1, gem)
	c.scale = Vector3.ONE * 0.52
	c.rotation_degrees = Vector3(-16, 0, 8)
	c.layers = ball_layer
	c.visible = false
	_frame.add_child(c)
	return c

## Called every render frame with the interpolated ball center.
func update_from_sim(world_pos: Vector3, sim, delta: float) -> void:
	delta = maxf(delta, 1e-4)
	var raw_step := world_pos - _prev_pos if _has_prev else Vector3.ZERO
	var teleported := raw_step.length() > 3.0
	if teleported:
		raw_step = Vector3.ZERO
		if _trail:
			_trail.clear()
	global_position = world_pos
	_prev_pos = world_pos
	_has_prev = true
	if _pending_respawn_fx and bursts:
		_pending_respawn_fx = false
		bursts.play(&"respawn", world_pos, Vector3.UP)
		bursts.flash(world_pos, Color(1.0, 0.85, 0.5), 5.0, 0.6, 7.0)

	# --- read sim ---
	var god := bool(_sget(sim, "in_god_mode", false))
	var dead := bool(_sget(sim, "is_dead", false))
	var on_ground := bool(_sget(sim, "on_ground", false))
	var gd = _sget(sim, "gravity_dir", Vector2i(0, 1))
	var sx := float(_sget(sim, "speed_x", raw_step.x / delta * 1.6))
	var sy := float(_sget(sim, "speed_y", -raw_step.y / delta * 1.6))
	var ee_vel := Vector2(sx, -sy)  # world y-up, EE speed units
	if god:
		gd = Vector2i(0, 1)
	if gd != Vector2i.ZERO:
		_grav = Vector2(gd.x, -gd.y).normalized()
	_on_ground = on_ground

	# --- gravity frame ---
	var target_ang := atan2(_grav.x, -_grav.y)
	_grav_angle = lerp_angle(_grav_angle, target_ang, 1.0 - exp(-delta * 9.0))
	_frame.rotation = Vector3(0, 0, _grav_angle)

	# --- rolling (gear-locked while grounded, coasting in the air) ---
	var step2 := Vector2(raw_step.x, raw_step.y)
	if on_ground and not god:
		var dth := (step2.x * _grav.y - step2.y * _grav.x) / RADIUS
		_roll += dth
		_roll_vel = dth / delta
	elif god:
		_roll_vel = lerpf(_roll_vel, 0.0, 1.0 - exp(-delta * 4.0))
		_roll += _roll_vel * delta
	else:
		_roll_vel *= exp(-delta * 0.6)
		_roll += _roll_vel * delta
	_mat.set_shader_parameter("pattern_angle", _grav_angle - _roll)

	# --- velocity in gravity frame ---
	var c := cos(-_grav_angle)
	var s := sin(-_grav_angle)
	var v_local := Vector2(ee_vel.x * c - ee_vel.y * s, ee_vel.x * s + ee_vel.y * c)
	var fall_speed := -v_local.y  # along gravity, EE units
	var look_t := Vector2(clampf(v_local.x / 5.5, -1, 1), clampf(v_local.y / 10.0, -1, 1))
	if god:
		look_t *= 0.6
	_look = _look.lerp(look_t, 1.0 - exp(-delta * 8.0))

	# --- landing / jump squash ---
	if on_ground and not _was_ground and not god:
		var impact := absf(fall_speed) if absf(fall_speed) > 0.5 else _last_fall
		_on_land(impact)
	_was_ground = on_ground
	if not on_ground:
		_last_fall = maxf(fall_speed, 0.0)
	var stretch_target := 0.0
	if not on_ground and not god:
		stretch_target = clampf(absf(fall_speed) / 13.5, 0.0, 1.0) * 0.14
	var k := 380.0
	var damp := 20.0
	# fixed substeps keep the stiff spring stable through frame hitches (loading, alt-tab)
	var steps := clampi(ceili(minf(delta, 0.1) / (1.0 / 240.0)), 1, 24)
	var h := minf(delta, 0.1) / steps
	for _i in steps:
		var acc := -k * (_sq - stretch_target) - damp * _sq_v
		_sq_v = clampf(_sq_v + acc * h, -12.0, 12.0)
		_sq = clampf(_sq + _sq_v * h, -0.38, 0.3)
	var a := _sq
	var sxz := 1.0 / sqrt(maxf(1.0 + a, 0.2))
	_body.scale = Vector3(sxz, 1.0 + a, sxz)
	_body.position = Vector3(0, minf(a, 0.0) * RADIUS * 0.9, 0)
	var head_y := RADIUS * (1.0 + a) + _body.position.y

	# --- expression ---
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = randf_range(2.2, 5.5)
		if randf() < 0.18:
			_blink_t = 0.22  # double blink
	_blink = maxf(_blink - delta / 0.14, 0.0)
	var eye_open := 1.0 - sin(_blink * PI)
	_squeeze = maxf(_squeeze - delta * 3.0, 0.0)
	_happy_t -= delta
	_happy = move_toward(_happy, 1.0 if _happy_t > 0.0 else 0.0, delta * 6.0)
	var scared := clampf((fall_speed - 10.0) / 3.0, 0.0, 1.0) if not on_ground and not god else 0.0
	_wide = move_toward(_wide, scared, delta * 5.0)
	_gasp = move_toward(_gasp, scared, delta * 4.0)
	var speed_h := absf(v_local.x)
	var grin_t := clampf((speed_h - 5.0) / 1.6, 0.0, 1.0) * (1.0 if on_ground else 0.5)
	grin_t = maxf(grin_t, _happy)
	if god:
		grin_t = 0.35
	_grin = move_toward(_grin, grin_t, delta * 3.0)
	_dead = move_toward(_dead, 1.0 if (dead or _dying) else 0.0, delta * 10.0)

	var face := {
		"look": _look, "eye_open": eye_open, "squeeze": _squeeze, "happy": _happy * (1.0 - _squeeze),
		"wide": _wide, "dead": _dead, "grin": _grin * (1.0 - _gasp), "gasp": _gasp,
	}
	for key in face_override:
		face[key] = face_override[key]
	for key in face:
		_mat.set_shader_parameter(key, face[key])

	# --- god aura, crowns ---
	_god = move_toward(_god, 1.0 if god else 0.0, delta * 4.0)
	if not ghost:
		_aura.visible = _god > 0.01
		_halo.visible = not _dying
		_aura_mat.set_shader_parameter("intensity", _god * 0.6)
		_aura.scale = Vector3.ONE * (0.8 + 0.2 * _god)
	var has_crown := bool(_sget(sim, "has_crown", false))
	var has_silver := bool(_sget(sim, "has_silver_crown", false))
	_crown_k = move_toward(_crown_k, 1.0 if has_crown else 0.0, delta * 5.0)
	_silver_k = move_toward(_silver_k, 1.0 if (has_silver and not has_crown) else 0.0, delta * 5.0)
	_place_crown(_crown, _crown_k, head_y, delta)
	_place_crown(_silver_crown, _silver_k, head_y, delta)

	# --- trail ---
	var spd := ee_vel.length()
	if _trail:
		_trail.push(world_pos, clampf((spd - 3.5) / 5.0, 0.0, 1.0) * 0.8 * (0.0 if god or _dying else 1.0), delta)

	# --- death / materialize ---
	if _dying:
		_death_t += delta
		var d := clampf((_death_t - 0.08) / 0.18, 0.0, 1.0)
		_mat.set_shader_parameter("dissolve", d)
		_body.visible = d < 0.999
	_materialize = minf(_materialize + delta / 0.45, 1.0)
	if not _dying and _materialize < 1.0:
		var m := _materialize
		_mat.set_shader_parameter("dissolve", 1.0 - m)
		_body.visible = true
		_frame.scale = Vector3.ONE * (0.6 + 0.4 * _ease_out_back(m))
	elif not _dying:
		_mat.set_shader_parameter("dissolve", 0.0)
		_frame.scale = Vector3.ONE
	_glow_flash = maxf(_glow_flash - delta * 3.5, 0.0)
	_mat.set_shader_parameter("glow", _glow_flash + (1.0 - _materialize) * 1.5)
	if _env_light:
		_env_light.light_energy = (1.0 + _glow_flash * 2.0) * (0.25 if _dying else 1.0)

var _last_fall := 0.0
var _pending_respawn_fx := false

func _place_crown(c: MeshInstance3D, k: float, head_y: float, delta: float) -> void:
	c.visible = k > 0.01
	if not c.visible:
		return
	var bob := sin(Time.get_ticks_msec() * 0.004) * 0.015
	c.position = Vector3(0.03, head_y - 0.13 + bob + (1.0 - k) * 0.6, 0.02)
	c.scale = Vector3.ONE * 0.5 * _ease_out_back(k)
	c.rotation.y += delta * 0.6

func _on_land(impact: float) -> void:
	var k := clampf(impact / 13.5, 0.0, 1.0)
	_sq_v -= 2.0 + k * 9.0
	if k > 0.35:
		_squeeze = maxf(_squeeze, clampf(k * 1.2, 0.0, 1.0))
	if bursts and k > 0.12:
		var down3 := Vector3(_grav.x, _grav.y, 0)
		var foot := global_position + down3 * RADIUS * 0.9
		bursts.play(&"dust", foot, -down3, Color.WHITE, k * 1.2)
		if k > 0.6:
			bursts.play(&"sparks", foot, -down3, Color.WHITE, k)

## Event hooks (ActorsView forwards sim events)
func on_jump() -> void:
	_sq_v += 3.5
	if bursts and _on_ground:
		var down3 := Vector3(_grav.x, _grav.y, 0)
		bursts.play(&"dust", global_position + down3 * RADIUS * 0.9, -down3, Color.WHITE, 0.35)

func on_happy(duration := 0.9) -> void:
	_happy_t = duration
	_glow_flash = maxf(_glow_flash, 0.5)

func on_death() -> void:
	_dying = true
	_death_t = 0.0
	_glow_flash = 0.5
	if bursts:
		bursts.play(&"shards", global_position, Vector3.UP)
		bursts.play(&"death_sparks", global_position, Vector3.UP)
		bursts.flash(global_position, Color(1.0, 0.55, 0.2), 4.0, 0.5, 8.0)
	if _trail:
		_trail.clear()

func on_respawn() -> void:
	_dying = false
	_materialize = 0.0
	_body.visible = true
	_sq = 0.0
	_sq_v = 0.0
	_roll_vel = 0.0
	_has_prev = false
	if _trail:
		_trail.clear()
	# The new position arrives with the next update_from_sim(); fire the FX there.
	_pending_respawn_fx = true

static func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

static func _sget(o, prop: String, def):
	if o == null:
		return def
	var v = o.get(prop)
	return def if v == null else v
