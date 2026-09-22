class_name ActorsView
extends Node3D
## Actors / VFX root: the 3D player ball, every interactive block visual, and event particles.
## Shell usage:
##   var actors := ActorsView.new(); add_child(actors); actors.build(lvl, sim)
##   each frame: actors.update_player(interpolated_ball_center_world, sim, delta)
## `sim` is an EESim (duck-typed so this also works with test mocks).

var level: EELevel
var sim
var player: FxPlayerBall
var blocks: FxInteractiveBlocks
var bursts: FxBursts
var overlays: FxOverlays
var life: FxAmbientLife

func build(lvl: EELevel, s) -> void:
	level = lvl
	sim = s
	bursts = FxBursts.new()
	bursts.name = "Bursts"
	add_child(bursts)
	blocks = FxInteractiveBlocks.new()
	blocks.name = "InteractiveBlocks"
	blocks.bursts = bursts
	add_child(blocks)
	blocks.build(lvl, s)
	overlays = FxOverlays.new()
	overlays.name = "Overlays"
	add_child(overlays)
	overlays.build(lvl)
	life = FxAmbientLife.new()
	life.name = "AmbientLife"
	add_child(life)
	life.build(lvl, overlays.maps)
	player = FxPlayerBall.new()
	player.name = "PlayerBall"
	player.bursts = bursts
	add_child(player)
	_no_shadows(self)
	if s != null:
		if "px" in s:
			player.position = EECoords.player_center(s.px, s.py)
		if s.has_signal("sim_event"):
			s.sim_event.connect(_on_sim_event)

## FX never cast shadows (each shadow-casting light would re-render them; the world's lights do cast).
func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)

## world_pos = interpolated ball CENTER in world space (EECoords.player_center(px, py)).
func update_player(world_pos: Vector3, s, delta: float) -> void:
	if s != null:
		sim = s
		blocks.sim = s
	player.update_from_sim(world_pos, s, delta)
	blocks.set_ball_pos(world_pos)
	if life:
		life.set_ball(world_pos)
	if overlays:
		overlays.set_ball(world_pos)

## Shell calls this every frame with the camera's global position (culling / pooled FX focus).
func update_camera(cam_pos: Vector3) -> void:
	if overlays:
		overlays.focus_override = cam_pos
	if life:
		life.set_focus(cam_pos)

## Ghost replay ball for the shell: hero look, desaturated, ~35% alpha, no lights/trail/bursts/events.
## Shell adds it to the tree and drives it with ghost.update_ghost(world_pos, ghost_sim, delta).
func create_ghost_ball() -> Node3D:
	var g := FxPlayerBall.new()
	g.name = "GhostBall"
	g.ghost = true
	g.ball_layer = 1
	return g

## Settings > Graphics "High-contrast gameplay glyphs".
func set_high_contrast(on: bool) -> void:
	set_glyph_boost(1.5 if on else 1.0)

## 1.0 = default, 1.5 = +50% size/emission on keys, arrows, dots (+ coins/portals).
func set_glyph_boost(amount: float) -> void:
	if blocks:
		blocks.set_glyph_boost(amount)

## Quality presets: the ball's carried light casts shadows (High/Ultra) or not (Low/Medium).
func set_ball_shadows(on: bool) -> void:
	if player:
		player.set_shadows(on)

func get_player_node() -> Node3D:
	return player

var _last_key_flash := 0
var _had_crown := false

func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	var p := player.global_position
	match kind:
		&"coin", &"blue_coin":
			if data.has("tile"):
				blocks.collect_coin_at(data.tile)
			player.on_happy(0.8)
		&"key":
			# Keys are dense painting pixels: touches are frequent, so the FX stay small and rate-limited.
			var color: StringName = StringName(data.get("color", &"red"))
			var tile = data.get("tile")
			blocks.key_triggered(color, tile)
			var kc: Color = FxInteractiveBlocks.KEY_COLORS.get(color, Color.WHITE)
			var at: Vector3 = p
			if tile is Vector2i:
				at = EECoords.tile_center(tile.x, tile.y)
			bursts.play(&"key", at, Vector3.UP, kc, 0.35)
			var now := Time.get_ticks_msec()
			if now - _last_key_flash > 350:
				_last_key_flash = now
				bursts.flash(at, kc, 2.2, 0.5, 5.0)
		&"crown":
			var tile = data.get("tile")
			if tile is Vector2i:
				blocks.flare(5, tile)
			if not _had_crown:
				_had_crown = true
				bursts.play(&"crown", p + Vector3(0, 0.5, 0), Vector3.UP, Color(1.0, 0.82, 0.3))
				bursts.flash(p, Color(1.0, 0.8, 0.35), 3.0, 0.5, 5.0)
				player.on_happy(1.2)
		&"complete":
			var at: Vector3 = p
			if data.has("tile"):
				at = EECoords.tile_center(data.tile.x, data.tile.y)
			bursts.play(&"crown", at, Vector3.UP, Color(0.75, 0.88, 1.0))
			bursts.play(&"coin_ring", at, Vector3.UP, Color(0.7, 0.85, 1.0))
			bursts.flash(at, Color(0.7, 0.85, 1.0), 5.0, 0.8, 8.0)
			player.on_happy(2.0)
		&"god_mode":
			bursts.play(&"coin_ring", p, Vector3.UP, Color(1.0, 0.95, 0.75))
		&"portal":
			blocks.portal_fx(data.get("from"), data.get("to"))
		&"death":
			player.on_death()
		&"respawn":
			player.on_respawn()
			_had_crown = false
		&"jump":
			player.on_jump()
		&"checkpoint":
			bursts.play(&"coin_ring", p, Vector3.UP, Color(0.6, 1.0, 0.7))
		_:
			pass
