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
	var glyph := _glyph_texture(k)
	var centre := Vector3(c.x + 0.5, -c.y - 0.5, 0.0)
	var wall := _open_spot(c, k + 1)   # coins often sit in 1-tile nooks: put the rune where it can be seen
	# carved glyph on the back wall behind the coin (projects onto whatever is behind: bg wall / cave)
	var d := Decal.new()
	d.name = "TrialGlyph%d" % (k + 1)
	d.texture_albedo = glyph
	d.texture_emission = glyph
	d.emission_energy = 2.0
	d.modulate = col
	d.albedo_mix = 0.55
	d.size = Vector3(4.6, 4.5, 4.6)           # decal projects along its local -Y (depth 4.5)
	d.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # local -Y -> world -Z (into the back wall)
	d.position = Vector3(wall.x, wall.y, -3.4)   # only the back wall behind the room
	d.normal_fade = 0.4   # only faces looking at the camera (the back wall), never the cliffs
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.cull_mask = 1   # terrain layer only
	add_child(d)
	# pedestal ring on the top of the solid below the coin
	var py := _pedestal(c, terrain)
	if py >= 0:
		var ring := Decal.new()
		ring.name = "TrialRing%d" % (k + 1)
		ring.texture_albedo = _ring_texture()
		ring.texture_emission = ring.texture_albedo
		ring.emission_energy = 1.2
		ring.modulate = col
		ring.albedo_mix = 0.4
		ring.size = Vector3(2.2, 1.6, 3.0)
		ring.normal_fade = 0.6   # only the up-facing pedestal top
		ring.position = Vector3(c.x + 0.5, -py + 0.2, -0.6)
		ring.cull_mask = 1
		add_child(ring)
	# soft shaft of light onto the pedestal (shows in the volumetric fog)
	var s := SpotLight3D.new()
	s.name = "TrialShaft%d" % (k + 1)
	s.light_color = col.lerp(Color.WHITE, 0.4)
	s.light_energy = 1.6
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
