class_name FxKeels
extends Node3D
## Floating-island life under FV's levitating ruins (world adds rock keels with levitation runes): fine dust
## and grit trickling from keel undersides, a very soft rune shimmer (screen wobble) beneath them, and the
## odd tiny pebble falling away. Sites = undersides of solid clusters with sunlit sky straight below
## (derived from the level; world may later hand over exact keel tips via set_keel_sites()). Pooled: only
## the POOL sites nearest the camera get emitters. Never placed where gameplay blocks sit below.

const POOL := 6
const NEAR := 30.0
const CHUNK := 8
const DROP := 6              # open sky tiles required below the underside
const HAZE_SHADER := preload("res://shaders/fx/heat_haze.gdshader")
const MIX_SHADER := preload("res://shaders/fx/soft_mix.gdshader")

var lvl: EELevel
var light: FxLightMap
var keel_depth := 0.0        # how far below the tile bottom world's keel tip hangs (tiles)
var _sites: Array = []       # {pos: Vector3 (underside centre, world), w: float}
var _slots: Array = []       # {dust, grit, haze, site: int}
var _assign_t := 0.0
var focus_override := Vector3(INF, 0, 0)

func build(level: EELevel, light_map: FxLightMap) -> void:
	lvl = level
	light = light_map
	_find_sites()
	for i in POOL:
		var slot := {"dust": _dust(), "pebbles": _pebbles(), "haze": _haze(), "site": -1}
		add_child(slot.dust)
		add_child(slot.pebbles)
		add_child(slot.haze)
		_slots.append(slot)
	print("FxKeels: %d floating undersides" % _sites.size())

## Exact keels from world (WorldKeels.keel_sites): [{tip, width, depth, rune}]; tips sit at z -3.6, so FX stay
## deep behind the gameplay air (world: keep FX behind z -1.0 in air tiles).
func set_keel_sites(sites: Array) -> void:
	_sites.clear()
	for s in sites:
		var tip: Vector3 = s.tip
		_sites.append({"pos": Vector3(tip.x, tip.y, maxf(tip.z, -3.6)), "w": float(s.get("width", 4.0)) * 0.6})
	print("FxKeels: using %d world keels" % _sites.size())

func _open(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < lvl.width and y < lvl.height and FxOverlayMaps.is_open(lvl, x, y)

func _clear_below(x: int, y: int) -> bool:
	# y = first air tile under the underside: sunlit sky, no gameplay/deco blocks for DROP tiles
	for k in DROP:
		if not _open(x, y + k) or lvl.get_fg(x, y + k) != 0:
			return false
		if light and light.at(x, y + k) == FxLightMap.DARK:
			return false
	return true

func _find_sites() -> void:
	var bins := {}
	for y in range(1, lvl.height - DROP - 1):
		for x in lvl.width:
			if _open(x, y) or not _open(x, y + 1):
				continue
			if not _clear_below(x, y + 1):
				continue
			var k := Vector2i(x / CHUNK, y / CHUNK)
			if not bins.has(k):
				bins[k] = {"n": 0, "sx": 0.0, "ymax": 0, "x0": 9999, "x1": -1}
			var b: Dictionary = bins[k]
			b.n += 1
			b.sx += x + 0.5
			b.ymax = maxi(b.ymax, y + 1)
			b.x0 = mini(b.x0, x)
			b.x1 = maxi(b.x1, x + 1)
	for k in bins:
		var b: Dictionary = bins[k]
		if b.n < 3:
			continue
		_sites.append({"pos": Vector3(b.sx / b.n, -float(b.ymax), -0.3), "w": float(b.x1 - b.x0)})

# ------------------------------------------------------------------------------------------ emitters

func _ramp(cols: Array, offs: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## Fine dust and grit sifting down, drifting with the breeze and fading into the air.
func _dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "KeelDust"
	p.amount = 60
	p.lifetime = 4.5
	p.preprocess = 4.5
	p.randomness = 0.6
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-6, -9, -2), Vector3(12, 10, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.5, 0.05, 0.3)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.05, -0.35, 0)   # a trail falling ~3-5 tiles before it fades
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.08
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = _ramp([Color(1.0, 0.9, 0.7, 0.0), Color(1.0, 0.9, 0.7, 0.9), Color(0.95, 0.88, 0.75, 0.5), Color(0.95, 0.9, 0.8, 0.0)], [0.0, 0.1, 0.6, 1.0])   # warm sunlit grit
	p.process_material = pm
	# additive glint so sunlit grit reads brighter than the pale sky (a mix sprite vanished against it)
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fx/particle.gdshader")
	m.set_shader_parameter("intensity", 2.2)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## The odd tiny pebble breaking away and tumbling down.
func _pebbles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "KeelPebbles"
	p.amount = 2
	p.lifetime = 2.2
	p.randomness = 1.0
	p.emitting = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	p.visibility_aabb = AABB(Vector3(-4, -30, -2), Vector3(8, 31, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.2, 0.05, 0.2)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -12, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(0.28, 0.25, 0.22, 1.0), Color(0.28, 0.25, 0.22, 1.0), Color(0.3, 0.27, 0.24, 0.0)], [0.0, 0.8, 1.0])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.08)
	var m := ShaderMaterial.new()
	m.shader = MIX_SHADER
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Rune shimmer: a feathered screen-wobble under the keel (no colour of its own, so no visible edges).
func _haze() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "KeelShimmer"
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 3.0)
	q.center_offset = Vector3(0, -1.5, 0)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = HAZE_SHADER
	m.set_shader_parameter("strength", 0.0025)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

# ------------------------------------------------------------------------------------------ runtime

func _process(delta: float) -> void:
	_assign_t -= delta
	if _assign_t > 0.0 or _sites.is_empty():
		return
	_assign_t = 0.25
	var cam := get_viewport().get_camera_3d()
	var f := focus_override
	if f.x == INF:
		if cam == null:
			return
		f = cam.global_position
	# priority: keels actually on screen first, ordered by projected distance to the view centre;
	# off-screen ones (by world distance) only fill leftover slots
	var vp := get_viewport().get_visible_rect().size
	var centre := vp * 0.5
	var near: Array = []
	for i in _sites.size():
		var p: Vector3 = _sites[i].pos
		var d := Vector2(p.x - f.x, p.y - f.y).length()
		if d > NEAR + 10.0:
			continue
		var score := 10000.0 + d
		if cam and not cam.is_position_behind(p):
			var sp := cam.unproject_position(p + Vector3(0, -1.5, 0))   # the trickle below the tip
			if sp.x > -40.0 and sp.y > -40.0 and sp.x < vp.x + 40.0 and sp.y < vp.y + 40.0:
				score = sp.distance_to(centre)
		near.append([score, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var want := {}
	for k in mini(near.size(), POOL):
		want[near[k][1]] = true
	# keep slots whose site is still wanted, hand the rest to new sites
	var free: Array = []
	for s in _slots:
		if s.site >= 0 and want.has(s.site):
			want.erase(s.site)
		else:
			free.append(s)
	for s in free:
		if want.is_empty():
			s.site = -1
			s.dust.emitting = false
			s.pebbles.emitting = false
			s.haze.visible = false
			continue
		var idx: int = want.keys()[0]
		want.erase(idx)
		s.site = idx
		var site: Dictionary = _sites[idx]
		var tip: Vector3 = site.pos + Vector3(0, -keel_depth, 0)
		var w: float = clampf(site.w, 1.5, 8.0)
		s.dust.position = tip
		(s.dust.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(w * 0.35, 0.05, 0.3)
		s.dust.restart()
		s.dust.emitting = true
		s.pebbles.position = tip
		s.pebbles.emitting = true
		s.haze.position = tip + Vector3(0, -0.1, 0.1)
		s.haze.scale = Vector3(w / 4.0 + 0.3, 1.0, 1.0)
		s.haze.visible = true
