class_name WorldTrials
extends Node3D
## Trial chambers (Forgotten Veil's 16 EE challenge rooms): every gold coin (id 100) is the reward at the
## end of a room. The room = the enclosed air around the coin (flood fill, capped). Each trial gets its own
## carved glowing glyph on the back wall behind the coin, a soft shaft of light down onto the coin's
## pedestal, a faint rune ring on the pedestal top, and a per-tile trial map for get_trial_at().

const MAX_ROOM := 900       # flood cap (tiles)
const MAX_RADIUS := 22      # tiles from the coin
const PALETTE := [Color(1.0, 0.78, 0.35), Color(0.45, 0.9, 1.0), Color(0.75, 1.0, 0.55), Color(1.0, 0.55, 0.85)]

var W := 0
var H := 0
var trial_map := PackedByteArray()   # 0 none, 1..16
var coins: Array[Vector2i] = []
var rune_pos: Array[Vector4] = []   # world xy of each rune centre
var rune_col: Array[Vector4] = []
var sim: Object
var _terrain: WorldTerrain
var _state := PackedFloat32Array()   # 0 open trial, 1 conquered
var _flare := PackedFloat32Array()   # seconds since conquered (for the one-off flare)
const RUNE_SIZE := 4.6

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	W = lvl.width
	H = lvl.height
	trial_map.resize(W * H)
	trial_map.fill(0)
	coins = lvl.find_all(100)
	coins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.x != b.x else a.y < b.y)
	for k in coins.size():
		_flood(coins[k], k + 1, terrain)
	for k in coins.size():
		_decorate(coins[k], k, terrain)
	_terrain = terrain
	_state.resize(coins.size())
	_flare.resize(coins.size())
	_flare.fill(99.0)
	_push_to_terrain()

## Uploads rune atlas, per-tile trial map, centres and colours to the terrain material.
func _push_to_terrain() -> void:
	var m := _terrain.material
	var n := 4
	var cell := 128
	var atlas := Image.create(n * cell, n * cell, false, Image.FORMAT_L8)
	for k in coins.size():
		var g := _glyph_texture(k).get_image()
		g.clear_mipmaps()
		g.convert(Image.FORMAT_RGBA8)
		var l := Image.create(cell, cell, false, Image.FORMAT_L8)
		for y in cell:
			for x in cell:
				l.set_pixel(x, y, Color(g.get_pixel(x, y).a, 0, 0))
		atlas.blit_rect(l, Rect2i(0, 0, cell, cell), Vector2i((k % n) * cell, (k / n) * cell))
	atlas.generate_mipmaps()
	m.set_shader_parameter("rune_atlas", ImageTexture.create_from_image(atlas))
	m.set_shader_parameter("trial_tex", ImageTexture.create_from_image(Image.create_from_data(W, H, false, Image.FORMAT_R8, trial_map)))
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	for k in 16:
		pos.append(rune_pos[k] if k < rune_pos.size() else Vector4())
		col.append(rune_col[k] if k < rune_col.size() else Vector4())
	m.set_shader_parameter("rune_pos", pos)
	m.set_shader_parameter("rune_col", col)
	m.set_shader_parameter("rune_size", RUNE_SIZE)
	_push_state()

func _push_state() -> void:
	var st := PackedFloat32Array()
	st.resize(16)
	for k in mini(16, coins.size()):
		# < 1: open trial (breathing), 1..2: conquered (flare decays from 2 to 1 over ~1.5 s)
		st[k] = 0.0 if _state[k] < 0.5 else 1.0 + clampf(1.0 - _flare[k] / 1.5, 0.0, 1.0)
	_terrain.material.set_shader_parameter("rune_state", st)

func _process(delta: float) -> void:
	if sim == null or not sim.has_method(&"is_coin_collected") or _terrain == null:
		return
	var changed := false
	for k in coins.size():
		var done: bool = sim.is_coin_collected(coins[k].x, coins[k].y)
		if done and _state[k] < 0.5:
			_state[k] = 1.0
			_flare[k] = 0.0
			changed = true
		elif not done and _state[k] > 0.5:
			_state[k] = 0.0
			changed = true
		if _flare[k] < 2.0:
			_flare[k] += delta
			changed = true
	if changed:
		_push_state()

func trial_count() -> int:
	return coins.size()

func get_trial_at(tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0 or tile.x >= W or tile.y >= H:
		return 0
	return trial_map[tile.y * W + tile.x]

func _flood(c: Vector2i, idx: int, terrain: WorldTerrain) -> void:
	var start := c.y * W + c.x
	var q := PackedInt32Array([start])
	var seen := {start: true}
	var qi := 0
	while qi < q.size() and q.size() < MAX_ROOM:
		var i := q[qi]; qi += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			if absi(nx - c.x) > MAX_RADIUS or absi(ny - c.y) > MAX_RADIUS:
				continue
			var j := ny * W + nx
			if seen.has(j) or terrain.solid[j] or terrain.sky[j]:
				continue
			seen[j] = true
			q.append(j)
	for i in q:
		if trial_map[i] == 0:
			trial_map[i] = idx

## Most open spot of this trial's room within 7 tiles of the coin (centre of the largest 5x5 air patch).
func _open_spot(c: Vector2i, idx: int) -> Vector2:
	var best := Vector2(c.x + 0.5, -c.y + 0.7)
	var best_n := -1
	for dy in range(-7, 8):
		for dx in range(-7, 8):
			var x := c.x + dx
			var y := c.y + dy
			if get_trial_at(Vector2i(x, y)) != idx:
				continue
			var n := 0
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					if get_trial_at(Vector2i(x + ox, y + oy)) == idx:
						n += 1
			n = n * 100 - (dx * dx + dy * dy)
			if n > best_n:
				best_n = n
				best = Vector2(x + 0.5, -y - 0.5)
	return best

## Nearest solid tile straight below the coin (the pedestal), within 12 tiles.
func _pedestal(c: Vector2i, terrain: WorldTerrain) -> int:
	for dy in range(1, 12):
		var y := c.y + dy
		if y >= H:
			break
		if terrain.solid[y * W + c.x]:
			return y
	return -1

func _decorate(c: Vector2i, k: int, terrain: WorldTerrain) -> void:
	var col: Color = PALETTE[k % PALETTE.size()]
	var centre := Vector3(c.x + 0.5, -c.y - 0.5, 0.0)
	var wall := _open_spot(c, k + 1)   # coins often sit in 1-tile nooks: put the rune where it can be seen
	# the carved rune itself lives in the terrain shader (back-wall layers only, depth-correct)
	rune_pos.append(Vector4(wall.x, wall.y, 0.0, 0.0))
	rune_col.append(Vector4(col.r, col.g, col.b, 1.0))
	# pedestal ring on the top of the solid below the coin
	var py := _pedestal(c, terrain)
	if py >= 0:
		var ring := Decal.new()
		ring.name = "TrialRing%d" % (k + 1)
		ring.texture_albedo = _ring_texture()
		ring.texture_emission = ring.texture_albedo
		ring.emission_energy = 0.35
		ring.modulate = col
		ring.albedo_mix = 0.7
		ring.modulate = col.darkened(0.55)
		ring.size = Vector3(2.2, 1.6, 3.0)
		ring.normal_fade = 0.6   # only the up-facing pedestal top
		ring.position = Vector3(c.x + 0.5, -py + 0.2, -0.6)
		ring.cull_mask = 1
		add_child(ring)
	# soft shaft of light onto the pedestal (shows in the volumetric fog)
	var s := SpotLight3D.new()
	s.name = "TrialShaft%d" % (k + 1)
	s.light_color = col.lerp(Color.WHITE, 0.4)
	s.light_energy = 1.1
	s.spot_range = 9.0
	s.spot_angle = 16.0
	s.spot_angle_attenuation = 1.6
	s.light_volumetric_fog_energy = 4.0
	s.shadow_enabled = false
	s.distance_fade_enabled = true
	s.distance_fade_begin = 50.0
	s.distance_fade_length = 10.0
	s.position = centre + Vector3(0.0, 6.0, 1.0)
	s.shadow_caster_mask = ~WorldBackdrop.OCCLUDER_LAYER & 0xFFFFF
	add_child(s)
	s.look_at(centre + Vector3(0.0, -1.0, 0.0), Vector3.FORWARD)

## A unique carved rune per trial: outer ring + seeded symmetric strokes and dots.
func _glyph_texture(k: int) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + k * 97
	var segs: Array = []
	var npts := 5 + (k % 3)
	var pts: Array[Vector2] = []
	for i in npts:
		var a := TAU * float(i) / npts + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.18, 0.36)
		pts.append(Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2.ZERO)
	for i in 6 + k % 4:
		var a: Vector2 = pts[rng.randi() % pts.size()]
		var b: Vector2 = pts[rng.randi() % pts.size()]
		if a != b:
			segs.append([a, b])
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5)
			var dmin := absf(p.length() - 0.44) - 0.018       # outer ring
			dmin = minf(dmin, absf(p.length() - 0.40) - 0.006)
			for sgm in segs:
				var a: Vector2 = sgm[0]
				var b: Vector2 = sgm[1]
				for mirror in [1.0, -1.0]:
					var am := Vector2(a.x * mirror, a.y)
					var bm := Vector2(b.x * mirror, b.y)
					var ab := bm - am
					var t := clampf((p - am).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					dmin = minf(dmin, (p - (am + ab * t)).length() - 0.016)
			for q in pts:
				dmin = minf(dmin, (p - Vector2(q.x, q.y)).length() - 0.03)
			var a := clampf(1.0 - dmin / 0.01, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

var _ring: ImageTexture
func _ring_texture() -> ImageTexture:
	if _ring:
		return _ring
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5)
			var d := absf(p.length() - 0.4)
			var ticks := 0.5 + 0.5 * cos(atan2(p.y, p.x) * 12.0)
			var a := clampf(1.0 - d / 0.035, 0.0, 1.0) * (0.55 + 0.45 * ticks)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_ring = ImageTexture.create_from_image(img)
	return _ring
