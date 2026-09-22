class_name WorldLights
extends Node3D
## World light rig: moon, emissive-cluster lights (fire / lava / gems / corruption / ice / water) derived
## from the level art, flicker, a soft focus fill light, and shadow budget management (only the lights
## nearest the focus cast shadows).

const SHADOW_BUDGET := 2   # + key light + moon = at most 4 shadowed lights
const BIN := 6   # tiles per clustering bin

var moon: DirectionalLight3D
var focus_light: OmniLight3D
## Big soft shadowed key light up-left in front of the scene: sculpts every bevel and throws the
## foreground's shadow onto the recessed walls (the main "3D diorama" read).
var key_light: SpotLight3D
var key_energy := 1.0
var key_color := Color(1, 0.9, 0.8)
var cluster_lights: Array[OmniLight3D] = []
var _base_energy := PackedFloat32Array()
var _flicker := PackedFloat32Array()   # 0 = steady, >0 = flicker amount
var _phase := PackedFloat32Array()
var _time := 0.0
var _focus := Vector3.ZERO
var _shadow_timer := 0.0
## Multiplier from the atmosphere (e.g. dim the fill light on the surface).
var focus_fill_energy := 0.6
var moon_energy := 1.0
## Daytime level: the directional light is the sun.
var day := false
var sun_scale := 1.0

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 90.0
	moon.shadow_blur = 1.5
	moon.light_angular_distance = 1.0
	moon.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	moon.light_volumetric_fog_energy = 1.6
	add_child(moon)

	focus_light = OmniLight3D.new()
	focus_light.name = "FocusFill"
	focus_light.light_color = Color(1.0, 0.86, 0.7)
	focus_light.omni_range = 20.0
	focus_light.omni_attenuation = 1.6
	focus_light.light_energy = 0.6
	focus_light.light_specular = 0.2
	focus_light.shadow_enabled = false
	focus_light.shadow_caster_mask = ~WorldBackdrop.OCCLUDER_LAYER & 0xFFFFF
	focus_light.light_volumetric_fog_energy = 0.0
	add_child(focus_light)

	key_light = SpotLight3D.new()   # one shadow frustum instead of an omni cube
	key_light.name = "KeyLight"
	key_light.spot_range = 80.0
	key_light.spot_attenuation = 0.6
	key_light.spot_angle = 80.0              # cone edge always far outside the ~40-tile view
	key_light.spot_angle_attenuation = 0.35
	key_light.light_energy = 1.0
	key_light.light_size = 1.5
	key_light.shadow_enabled = true
	key_light.shadow_blur = 1.6
	key_light.shadow_bias = 0.04
	key_light.shadow_normal_bias = 1.5
	key_light.light_volumetric_fog_energy = 0.35
	key_light.shadow_caster_mask = ~WorldBackdrop.OCCLUDER_LAYER & 0xFFFFF
	add_child(key_light)

	if day:
		# the sun: warm, higher, stronger, soft shadows; god rays through the ruins via volumetric fog
		moon.name = "Sun"
		moon.light_color = Color(1.0, 0.86, 0.66)
		moon.shadow_blur = 0.8
		moon.rotation_degrees = Vector3(-42.0, -24.0, 0.0)
		moon.light_angular_distance = 1.5
		moon.light_volumetric_fog_energy = 2.2
		sun_scale = 1.8
	_make_cluster_lights(lvl, terrain)
	if WorldPalette.is_odyssey():
		_make_demon()

## Groups emissive tiles into BIN x BIN bins and places one light per sufficiently lit bin.
func _make_cluster_lights(lvl: EELevel, terrain: WorldTerrain) -> void:
	var W := lvl.width
	var H := lvl.height
	var bins := {}   # key -> [count, sumx, sumy, r, g, b, kind]
	for y in H:
		for x in W:
			var i := y * W + x
			if not terrain.solid[i]:
				continue
			var m: int = terrain.mat_ids[i]
			var kind := -1
			match m:
				WorldPalette.M_FIRE: kind = 0
				WorldPalette.M_GEM: kind = 1
				WorldPalette.M_CORRUPT: kind = 2
				WorldPalette.M_ICE, WorldPalette.M_GLASS: kind = 3
				WorldPalette.M_WATER: kind = 4
			if kind < 0:
				continue
			# only tiles exposed to air emit into the scene
			var exposed := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < W and ny < H and not terrain.solid[ny * W + nx]:
					exposed = true
					break
			if not exposed and kind != 0 and kind != 1:
				continue
			var bs := BIN if kind != 2 else BIN * 2
			var key := Vector3i(x / bs, y / bs, kind)
			if not bins.has(key):
				bins[key] = [0, 0.0, 0.0, 0.0, 0.0, 0.0]
			var e: Array = bins[key]
			var c := WorldPalette.base_color(lvl.fg[i])
			e[0] += 1; e[1] += x + 0.5; e[2] += y + 0.5
			e[3] += c.r; e[4] += c.g; e[5] += c.b
	for key in bins:
		var e: Array = bins[key]
		var cnt: int = e[0]
		var kind: int = key.z
		var min_cnt: int = [3, 4, 10, 5, 12][kind]
		if cnt < min_cnt:
			continue
		var col := Color(e[3] / cnt, e[4] / cnt, e[5] / cnt)
		var l := OmniLight3D.new()
		var pos := Vector3(e[1] / cnt, -e[2] / cnt, 1.4)
		var energy := 1.0
		var rng := 9.0
		var flick := 0.0
		match kind:
			0:
				col = col.lerp(Color(1.0, 0.55, 0.2), 0.4)
				energy = clampf(0.9 + cnt * 0.07, 1.0, 3.2) * 0.7
				rng = clampf(6.0 + cnt * 0.35, 7.0, 16.0)
				flick = 0.22
				pos.z = 1.6
			1:
				col = col.lerp(Color.WHITE, 0.15)
				energy = clampf(0.4 + cnt * 0.03, 0.5, 1.6)
				rng = 8.0
				pos.z = 2.0
			2:
				col = Color(0.75, 0.3, 1.0)
				energy = 0.9
				rng = 13.0
				flick = 0.08
				pos.z = 2.5
			3:
				col = Color(0.55, 0.8, 1.0)
				energy = 0.7
				rng = 9.0
				pos.z = 1.8
			4:
				col = Color(0.3, 0.55, 1.0)
				energy = 0.7
				rng = 12.0
				flick = 0.05
				pos.z = 2.5
		l.position = pos
		l.light_color = col
		l.light_energy = energy
		l.omni_range = rng
		l.omni_attenuation = 1.3
		l.light_specular = 0.6 if kind < 3 else 0.15
		l.light_volumetric_fog_energy = 1.2 if kind == 0 else 0.7
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 45.0
		l.distance_fade_length = 12.0
		l.distance_fade_shadow = 25.0
		l.shadow_bias = 0.05
		l.shadow_normal_bias = 1.0
		l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		l.shadow_caster_mask = ~WorldBackdrop.OCCLUDER_LAYER & 0xFFFFF
		add_child(l)
		cluster_lights.append(l)
		_base_energy.append(energy)
		_flicker.append(flick)
		_phase.append(randf() * 100.0)

## The hero figure: the demon rising from the lake gets glowing eyes and a cold rim light from the water.
const DEMON_EYES := [Vector2(301.5, 147.5), Vector2(304.3, 148.3)]
var demon_eye_lights: Array[OmniLight3D] = []

func _make_demon() -> void:
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.75, 0.55)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.35, 0.2)
	eye_mat.emission_energy_multiplier = 3.5
	var k := 0
	for e: Vector2 in DEMON_EYES:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22 if k == 0 else 0.16
		sm.height = sm.radius * 1.4
		m.mesh = sm
		m.material_override = eye_mat
		m.position = Vector3(e.x, -e.y, 0.95)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.name = "DemonEye%d" % k
		add_child(m)
		var l := OmniLight3D.new()
		l.position = Vector3(e.x, -e.y, 1.6)
		l.light_color = Color(1.0, 0.35, 0.2)
		l.light_energy = 0.9
		l.omni_range = 2.8
		l.light_volumetric_fog_energy = 2.0
		l.shadow_caster_mask = ~WorldBackdrop.OCCLUDER_LAYER & 0xFFFFF
		add_child(l)
		demon_eye_lights.append(l)
		k += 1
	# cold rim from the lake: behind-below the figure, grazing its silhouette
	for p in [Vector3(318.0, -186.0, -2.5), Vector3(292.0, -176.0, -2.0), Vector3(322.0, -150.0, -2.5)]:
		var rim := OmniLight3D.new()
		rim.position = p
		rim.light_color = Color(0.35, 0.6, 1.0)
		rim.light_energy = 3.0
		rim.omni_range = 22.0
		rim.omni_attenuation = 1.2
		rim.light_specular = 1.0
		rim.distance_fade_enabled = true
		rim.distance_fade_begin = 60.0
		rim.distance_fade_length = 15.0
		rim.shadow_caster_mask = ~WorldBackdrop.OCCLUDER_LAYER & 0xFFFFF
		rim.name = "DemonRim"
		add_child(rim)

func update_focus(world_pos: Vector3, delta: float) -> void:
	_focus = world_pos
	focus_light.position = world_pos + Vector3(0.0, 1.5, 3.0)
	focus_light.light_energy = focus_fill_energy
	key_light.position = world_pos + Vector3(-11.0, 13.0, 17.0)
	key_light.look_at(world_pos + Vector3(2.0, -2.0, -2.0), Vector3.UP)
	key_light.light_energy = key_energy
	key_light.light_color = key_color
	moon.light_energy = 2.2 * moon_energy * sun_scale
	moon.visible = moon_energy > 0.01
	_shadow_timer -= delta
	if _shadow_timer <= 0.0:
		_shadow_timer = 0.5
		_assign_shadows()

func _assign_shadows() -> void:
	var order := []
	for i in cluster_lights.size():
		var d := cluster_lights[i].position.distance_squared_to(_focus)
		order.append([d, i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for k in order.size():
		var li: OmniLight3D = cluster_lights[order[k][1]]
		var want: bool = k < SHADOW_BUDGET and order[k][0] < 400.0
		# hysteresis: keep an already-shadowed light while it stays reasonably close (avoids flip-flopping
		# cube-shadow re-renders while moving)
		if li.shadow_enabled and not want and order[k][0] < 520.0 and k < SHADOW_BUDGET + 1:
			want = true
		if li.shadow_enabled != want:
			li.shadow_enabled = want

func _process(delta: float) -> void:
	_time += delta
	for i in demon_eye_lights.size():
		demon_eye_lights[i].light_energy = 0.9 * (0.8 + 0.2 * sin(_time * 1.3 + i))
	for i in cluster_lights.size():
		var f := _flicker[i]
		if f <= 0.0:
			continue
		var ph := _phase[i] + _time
		var n := sin(ph * 7.1) * 0.5 + sin(ph * 13.7 + 1.3) * 0.3 + sin(ph * 23.3 + 2.1) * 0.2
		cluster_lights[i].light_energy = _base_energy[i] * (1.0 + f * n)
