class_name WorldAtmosphere
extends Node3D
## WorldEnvironment + post + atmosphere zones. Zone weights are measured around the focus position from
## the zone map, smoothed over time, and blend every environment parameter (ambient, exposure, glow,
## grading, sky, moon, fill light, ambient particles). Volumetric fog is spatial (FogVolume + fog shader
## sampling per-region fog fields), so each cave keeps its own haze wherever the camera is.

var environment: Environment
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var post_layer: CanvasLayer
var fog_volume: FogVolume
var particles := {}   # name -> GPUParticles3D
var weights := PackedFloat32Array()
var _terrain: WorldTerrain
var _zones: WorldZones
var _lights: WorldLights
var _first := true
## Daytime level (config time_of_day == "day"): painted day sky instead of the night sky.
var day := false
var _sky_cave := -1.0
var _sky_amb := Vector3(-1, -1, -1)

## Per-zone look. ambient: Color, amb_e, exposure, glow, sat, contrast, sky (bg energy), moon, fill,
## fill_col, particles: {name: amount}
var PRESETS := {
	WorldPalette.Z_SURFACE: {"key": 0.55, "key_col": Color(0.6, 0.7, 1.0), "ambient": Color(0.69, 0.72, 0.83), "amb_e": 1.00, "exposure": 1.05, "glow": 0.75,
		"sat": 1.08, "contrast": 1.06, "sky": 1.0, "moon": 1.0, "fill": 0.77, "fill_col": Color(0.8, 0.85, 1.0),
		"parts": {"fireflies": 1.0}},
	WorldPalette.Z_EARTH: {"key": 3.08, "key_col": Color(1.0, 0.82, 0.66), "ambient": Color(0.80, 0.69, 0.67), "amb_e": 1.00, "exposure": 1.62, "glow": 0.9,
		"sat": 1.1, "contrast": 1.1, "sky": 0.15, "moon": 0.0, "fill": 1.98, "fill_col": Color(1.0, 0.8, 0.62),
		"parts": {"dust": 1.0}},
	WorldPalette.Z_HELL: {"key": 1.96, "key_col": Color(1.0, 0.6, 0.4), "ambient": Color(0.86, 0.66, 0.59), "amb_e": 0.45, "exposure": 1.00, "glow": 1.35,
		"sat": 1.18, "contrast": 1.14, "sky": 0.0, "moon": 0.0, "fill": 1.10, "fill_col": Color(1.0, 0.6, 0.35),
		"parts": {"dust": 0.6}},
	WorldPalette.Z_CORRUPT: {"key": 2.52, "key_col": Color(0.85, 0.7, 1.0), "ambient": Color(0.74, 0.63, 0.83), "amb_e": 1.00, "exposure": 1.56, "glow": 1.2,
		"sat": 1.15, "contrast": 1.12, "sky": 0.0, "moon": 0.0, "fill": 1.65, "fill_col": Color(0.85, 0.65, 1.0),
		"parts": {"dust": 0.5}},
	WorldPalette.Z_ICE: {"key": 2.80, "key_col": Color(0.8, 0.9, 1.0), "ambient": Color(0.74, 0.82, 0.93), "amb_e": 1.00, "exposure": 1.49, "glow": 1.0,
		"sat": 1.0, "contrast": 1.08, "sky": 0.0, "moon": 0.0, "fill": 1.76, "fill_col": Color(0.75, 0.88, 1.0),
		"parts": {"dust": 0.4}},
	WorldPalette.Z_LAKE: {"key": 2.66, "key_col": Color(0.7, 0.82, 1.0), "ambient": Color(0.65, 0.70, 0.86), "amb_e": 1.00, "exposure": 1.49, "glow": 1.1,
		"sat": 1.12, "contrast": 1.1, "sky": 0.0, "moon": 0.0, "fill": 1.76, "fill_col": Color(0.7, 0.8, 1.0),
		"parts": {"dust": 0.4}},
	WorldPalette.Z_TORNADO: {"key": 2.80, "key_col": Color(0.9, 0.92, 1.0), "ambient": Color(0.75, 0.77, 0.81), "amb_e": 1.00, "exposure": 1.49, "glow": 0.9,
		"sat": 0.9, "contrast": 1.1, "sky": 0.0, "moon": 0.0, "fill": 1.76, "fill_col": Color(0.9, 0.92, 1.0),
		"parts": {"dust": 0.8}},
	WorldPalette.Z_BONES: {"key": 3.08, "key_col": Color(1.0, 0.85, 0.65), "ambient": Color(0.78, 0.72, 0.67), "amb_e": 1.00, "exposure": 1.62, "glow": 0.95,
		"sat": 1.05, "contrast": 1.12, "sky": 0.0, "moon": 0.0, "fill": 1.98, "fill_col": Color(1.0, 0.82, 0.6),
		"parts": {"dust": 1.0}},
	WorldPalette.Z_DEEP: {"key": 2.80, "key_col": Color(1.0, 0.75, 0.68), "ambient": Color(0.82, 0.65, 0.66), "amb_e": 1.00, "exposure": 1.56, "glow": 1.0,
		"sat": 1.12, "contrast": 1.12, "sky": 0.0, "moon": 0.0, "fill": 1.87, "fill_col": Color(1.0, 0.7, 0.62),
		"parts": {"dust": 0.8}},
	# --- daytime ruins (Forgotten Veil) ---
	WorldPalette.Z_DAY: {"key": 0.9, "key_col": Color(1.0, 0.95, 0.86), "ambient": Color(0.62, 0.74, 1.0), "amb_e": 0.75,
		"exposure": 1.0, "glow": 0.35, "sat": 1.22, "contrast": 1.16, "sky": 1.0, "moon": 1.0, "fill": 0.3,
		"fill_col": Color(1.0, 0.95, 0.85), "parts": {"dust": 0.35}},
	WorldPalette.Z_RUINS: {"key": 2.2, "key_col": Color(0.9, 0.95, 1.0), "ambient": Color(0.6, 0.68, 0.8), "amb_e": 0.7,
		"exposure": 1.3, "glow": 0.5, "sat": 1.12, "contrast": 1.14, "sky": 0.0, "moon": 1.0, "fill": 1.6,
		"fill_col": Color(0.85, 0.92, 1.0), "parts": {"dust": 1.0}},
	WorldPalette.Z_WATERWAY: {"key": 2.0, "key_col": Color(0.8, 0.92, 1.0), "ambient": Color(0.55, 0.72, 0.85), "amb_e": 0.75,
		"exposure": 1.25, "glow": 0.6, "sat": 1.15, "contrast": 1.14, "sky": 0.0, "moon": 1.0, "fill": 1.5,
		"fill_col": Color(0.75, 0.9, 1.0), "parts": {"dust": 0.5}},
}

## Fog per zone: albedo, density, emission, mist
var FOG := {
	WorldPalette.Z_SURFACE: [Color(0.55, 0.62, 0.85), 0.018, Color(0.0, 0.0, 0.0), 0.0],
	WorldPalette.Z_EARTH: [Color(0.75, 0.5, 0.4), 0.045, Color(0.012, 0.005, 0.003), 0.02],
	WorldPalette.Z_HELL: [Color(1.0, 0.55, 0.3), 0.06, Color(0.045, 0.011, 0.002), 0.05],
	WorldPalette.Z_CORRUPT: [Color(0.7, 0.45, 1.0), 0.065, Color(0.03, 0.008, 0.05), 0.08],
	WorldPalette.Z_ICE: [Color(0.75, 0.88, 1.0), 0.06, Color(0.008, 0.014, 0.025), 0.12],
	WorldPalette.Z_LAKE: [Color(0.45, 0.6, 1.0), 0.065, Color(0.006, 0.012, 0.035), 0.15],
	WorldPalette.Z_TORNADO: [Color(0.8, 0.82, 0.9), 0.07, Color(0.01, 0.01, 0.014), 0.06],
	WorldPalette.Z_BONES: [Color(0.85, 0.7, 0.5), 0.05, Color(0.012, 0.007, 0.003), 0.05],
	WorldPalette.Z_DEEP: [Color(0.9, 0.45, 0.45), 0.055, Color(0.02, 0.004, 0.004), 0.05],
	WorldPalette.Z_DAY: [Color(0.85, 0.9, 1.0), 0.0015, Color(0.0, 0.0, 0.0), 0.0],
	WorldPalette.Z_RUINS: [Color(0.75, 0.78, 0.82), 0.016, Color(0.0, 0.0, 0.0), 0.02],
	WorldPalette.Z_WATERWAY: [Color(0.7, 0.85, 0.95), 0.009, Color(0.004, 0.01, 0.014), 0.03],
}

func build(lvl: EELevel, terrain: WorldTerrain, lights: WorldLights, zones: WorldZones) -> void:
	_terrain = terrain
	_zones = zones
	_lights = lights
	weights.resize(WorldPalette.Z_COUNT)
	_make_environment()
	_make_fog(lvl, terrain)
	_make_post()
	_make_particles()

func _make_environment() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	if day:
		sky_mat.shader = load("res://shaders/world/day_sky.gdshader")
		sky_mat.set_shader_parameter("sun_dir", _lights.moon.transform.basis.z.normalized())
	else:
		sky_mat.shader = load("res://shaders/world/night_sky.gdshader")
		sky_mat.set_shader_parameter("moon_dir", Vector3(0.24, 0.13, -1.0).normalized())
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL   # radiance refresh spread over frames (no per-frame cubemap)
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_agx_contrast = 1.25
	environment.tonemap_exposure = 1.1
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.6
	environment.ssao_detail = 0.6
	environment.ssao_light_affect = 0.15
	environment.ssil_enabled = true
	environment.ssil_radius = 6.0
	environment.ssil_intensity = 1.4
	environment.ssr_enabled = true
	environment.ssr_max_steps = 96
	environment.ssr_fade_in = 0.1
	environment.ssr_fade_out = 2.5
	environment.ssr_depth_tolerance = 0.4
	environment.glow_enabled = true
	environment.glow_normalized = false
	environment.glow_intensity = 0.9
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.1
	environment.glow_hdr_scale = 2.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.set("glow_levels/1", 0.0)
	environment.set("glow_levels/2", 0.25)
	environment.set("glow_levels/3", 0.8)
	environment.set("glow_levels/4", 1.0)
	environment.set("glow_levels/5", 0.35)
	environment.set("glow_levels/6", 0.1)
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0
	environment.volumetric_fog_albedo = Color(0.7, 0.7, 0.8)
	environment.volumetric_fog_length = 110.0
	environment.volumetric_fog_detail_spread = 0.8
	environment.volumetric_fog_anisotropy = 0.45
	environment.volumetric_fog_ambient_inject = 0.25
	environment.volumetric_fog_sky_affect = 0.0
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.08
	if day:
		environment.ssao_intensity = 2.2
		environment.ssao_radius = 1.2
		environment.tonemap_agx_contrast = 1.35
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

## Low-res (1 texel / 2 tiles) fog fields from the zone map, blurred so regions melt into each other.
func _make_fog(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var fw := W / 2
	var fh := H / 2
	var field := Image.create(fw, fh, false, Image.FORMAT_RGBAF)
	var emit := Image.create(fw, fh, false, Image.FORMAT_RGBAF)
	for y in fh:
		for x in fw:
			var i := (y * 2) * W + x * 2
			var z: int = terrain.zones[i]
			var f: Array = FOG[z]
			var dens: float = f[1]
			if terrain.sky[i]:
				dens *= 0.6
			var c: Color = f[0]
			field.set_pixel(x, y, Color(c.r, c.g, c.b, dens))
			var e: Color = f[2]
			emit.set_pixel(x, y, Color(e.r, e.g, e.b, f[3]))
	# blur (downsample + upsample)
	for img in [field, emit]:
		img.resize(fw / 6, fh / 6, Image.INTERPOLATE_CUBIC)
		img.resize(fw, fh, Image.INTERPOLATE_CUBIC)
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://shaders/world/zone_fog.gdshader")
	fmat.set_shader_parameter("fog_field", ImageTexture.create_from_image(field))
	fmat.set_shader_parameter("fog_emit", ImageTexture.create_from_image(emit))
	fmat.set_shader_parameter("level_size", Vector2(W, H))
	fog_volume = FogVolume.new()
	fog_volume.name = "ZoneFog"
	fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog_volume.size = Vector3(W + 40, H + 40, 16.0)
	fog_volume.position = Vector3(W * 0.5, -H * 0.5, -6.0)
	fog_volume.material = fmat
	add_child(fog_volume)

## Post effect as a full-rect canvas item on its own CanvasLayer (POST_LAYER): hint_screen_texture there
## is the final 3D frame including all transparent effects.
const POST_LAYER := -10

func _make_post() -> void:
	post_layer = CanvasLayer.new()
	post_layer.name = "PostFX"
	post_layer.layer = POST_LAYER
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/world/post.gdshader")
	rect.material = m
	if day:
		m.set_shader_parameter("vignette", 0.19)
		m.set_shader_parameter("grain", 0.012)
	post_layer.add_child(rect)
	add_child(post_layer)

func _particle_system(pname: String, amount: int, color: Color, energy: float, size: float, gravity: Vector3,
		vel: float, lifetime: float, turbulence: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "P_" + pname
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -30, -10), Vector3(80, 60, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 20.0, 3.5)
	pm.gravity = gravity
	pm.initial_velocity_min = vel * 0.3
	pm.initial_velocity_max = vel
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.turbulence_enabled = turbulence > 0.0
	pm.turbulence_noise_strength = turbulence
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.add_point(0.15, Color(1, 1, 1, 1))
	grad.add_point(0.75, Color(1, 1, 1, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy)
	mat.albedo_texture = _soft_dot()
	mat.disable_receive_shadows = true
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount_ratio = 0.0
	add_child(p)
	particles[pname] = p
	return p

var _dot_tex: Texture2D
func _soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

## Ambient motes only; zone FX (embers, snow, spores, bubbles, wind debris) belong to the actors layer.
func _make_particles() -> void:
	_particle_system("dust", 500, Color(1.0, 0.85, 0.65), 0.35, 0.09, Vector3(0, -0.02, 0), 0.15, 9.0, 0.4)
	_particle_system("fireflies", 160, Color(0.75, 1.0, 0.45), 2.2, 0.1, Vector3(0, 0.0, 0), 0.25, 9.0, 0.7)

func _measure(world_pos: Vector3) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(WorldPalette.Z_COUNT)
	var W := _terrain.W
	var H := _terrain.H
	var cx := int(floor(world_pos.x))
	var cy := int(floor(-world_pos.y))
	var total := 0.0
	for j in range(-4, 5):
		for i in range(-6, 7):
			var x := clampi(cx + i * 3, 0, W - 1)
			var y := clampi(cy + j * 3, 0, H - 1)
			var fall := 1.0 / (1.0 + (i * i + j * j) * 0.08)
			w[_zones.visual[y * W + x]] += fall
			total += fall
	for k in w.size():
		w[k] /= total
	return w

func update_focus(world_pos: Vector3, delta: float) -> void:
	var target := _measure(world_pos)
	var a := 1.0 if _first else clampf(delta * 1.2, 0.0, 1.0)
	_first = false
	for k in weights.size():
		weights[k] = lerpf(weights[k], target[k], a)
	var amb := Color(0, 0, 0)
	var amb_e := 0.0; var expo := 0.0; var glow := 0.0; var sat := 0.0; var con := 0.0
	var skye := 0.0; var moon := 0.0; var fill := 0.0
	var fill_col := Color(0, 0, 0)
	var key := 0.0
	var key_col := Color(0, 0, 0)
	var parts := {}
	for k in weights.size():
		var wk := weights[k]
		if wk <= 0.0001:
			continue
		var pr: Dictionary = PRESETS[k]
		amb += pr["ambient"] * wk
		amb_e += pr["amb_e"] * wk
		expo += pr["exposure"] * wk
		glow += pr["glow"] * wk
		sat += pr["sat"] * wk
		con += pr["contrast"] * wk
		skye += pr["sky"] * wk
		moon += pr["moon"] * wk
		fill += pr["fill"] * wk
		fill_col += pr["fill_col"] * wk
		key += pr["key"] * wk
		key_col += pr["key_col"] * wk
		for pn in pr["parts"]:
			parts[pn] = parts.get(pn, 0.0) + pr["parts"][pn] * wk
	environment.ambient_light_color = amb
	environment.ambient_light_energy = amb_e * lerpf(1.35, 1.0, weights[WorldPalette.Z_SURFACE] + weights[WorldPalette.Z_DAY])
	# sky radiance params only when they change noticeably (each change re-bakes the radiance cubemap)
	var surf := weights[WorldPalette.Z_SURFACE] + weights[WorldPalette.Z_DAY]   # open sky (night or day)
	var cave := clampf(1.0 - surf, 0.0, 1.0)
	var amb_v := Vector3(amb.r, amb.g, amb.b)
	if absf(cave - _sky_cave) > 0.03 or amb_v.distance_to(_sky_amb) > 0.03:
		_sky_cave = cave
		_sky_amb = amb_v
		sky_mat.set_shader_parameter("cave_amount", cave)
		sky_mat.set_shader_parameter("cave_top", amb_v * 0.9)
		sky_mat.set_shader_parameter("cave_bottom", amb_v * 0.08)
	environment.tonemap_exposure = expo
	environment.glow_intensity = glow * 0.6
	environment.adjustment_saturation = sat * 1.22
	environment.adjustment_contrast = con
	environment.background_energy_multiplier = 1.0   # (it also scales sky ambient; sky brightness is in the shader)
	_lights.moon_energy = moon
	_lights.focus_fill_energy = fill
	_lights.focus_light.light_color = fill_col
	_lights.key_energy = key
	_lights.key_color = key_col
	for pn in particles:
		var p: GPUParticles3D = particles[pn]
		var r: float = clampf(parts.get(pn, 0.0) * 1.3, 0.0, 1.0)
		p.amount_ratio = r
		p.emitting = r > 0.02
		p.global_position = Vector3(world_pos.x, world_pos.y, 0.5)
