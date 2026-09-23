extends Node3D
## Automated readability check: renders the gameplay plane with an orthographic camera in the terrain's
## solidity-mask mode (white = rendered solid mass, black = open) and compares every tile against the
## collision truth EESim.is_tile_solid_now(). Samples a 4x4 grid inside each tile inset by INSET (the
## allowed bevel / corner rounding), so a tile passes only if its interior is entirely correct.
## Run in a window:  godot --path . res://tests/world_solidity_check.tscn
## Writes user://world_solidity_mismatch.png (red = solid drawn open, cyan = open drawn solid).

const INSET := 0.15
const TILES_PER_SHOT_Y := 100.0

var world: WorldView
var sim: EESim
var cam: Camera3D

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var level_id := "odyssey"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			level_id = a.substr(6)
	var cfg := LevelCatalog.get_config(level_id)
	var lvl := EELevel.load_file(str(cfg.get("level_file", "res://levels/ex_crew_odyssey.eelvl")))
	world = WorldView.new()
	add_child(world)
	world.set_level_config(cfg)
	world.build(lvl)
	sim = EESim.new(lvl)
	world.set_sim(sim)
	world.set_debug_mode(3)
	world.doors.set_mask_mode(true)
	for n in [world.decor, world.lights, world.backdrop, world.trials, world.grass, world.foliage, world.keels, world.vista]:
		if n:
			n.visible = false   # decals / props / lights are not terrain mass
	world.atmosphere.post_layer.visible = false
	world.atmosphere.fog_volume.visible = false
	for p in world.atmosphere.particles.values():
		p.visible = false
	var env := world.get_environment()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.adjustment_enabled = false
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TILES_PER_SHOT_Y
	cam.near = 1.0
	cam.far = 100.0
	add_child(cam)
	cam.current = true
	_run(lvl)

func _run(lvl: EELevel) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var probe := get_viewport().get_texture().get_image()
	var vs := Vector2(probe.get_width(), probe.get_height())
	var ppt := vs.y / TILES_PER_SHOT_Y
	var tiles_x := vs.x / ppt
	print("viewport image ", vs, " px/tile ", ppt)
	var W := lvl.width
	var H := lvl.height
	var bad := Image.create(W, H, false, Image.FORMAT_RGB8)
	var solid_open := 0
	var open_solid := 0
	var checked := {}
	var y0 := 0.0
	while y0 < H:
		var x0 := 0.0
		while x0 < W:
			cam.position = Vector3(x0 + tiles_x * 0.5, -(y0 + TILES_PER_SHOT_Y * 0.5), 50.0)
			for f in 6:
				world.update_focus(cam.position * Vector3(1, 1, 0), 1.0 / 60.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if x0 == 0.0 and y0 == 0.0:
				img.save_png("user://world_solidity_shot0.png")
			for ty in range(int(y0), mini(H, int(y0 + TILES_PER_SHOT_Y))):
				for tx in range(int(x0), mini(W, int(x0 + tiles_x))):
					var k := ty * W + tx
					if checked.has(k):
						continue
					checked[k] = true
					if (ty == 0 or tx == 0 or tx == W - 1 or ty == H - 1) and not world.terrain.solid[k]:
						continue   # world border beside open air: invisible by design
					if lvl.fg[k] == 43 or lvl.fg[k] == 1004:
						continue   # coin door (actors) / one-way ledge
					var truth := sim.is_tile_solid_now(tx, ty)
					var ok := true
					for sj in 4:
						for si in 4:
							var fx := INSET + (1.0 - 2.0 * INSET) * si / 3.0
							var fy := INSET + (1.0 - 2.0 * INSET) * sj / 3.0
							var px := int((tx + fx - x0) * ppt)
							var py := int((ty + fy - y0) * ppt)
							if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
								continue
							var drawn := img.get_pixel(px, py).r > 0.5
							if drawn != truth:
								ok = false
					if not ok:
						if truth:
							solid_open += 1
							bad.set_pixel(tx, ty, Color(1, 0, 0))
						else:
							open_solid += 1
							bad.set_pixel(tx, ty, Color(0, 1, 1))
					else:
						bad.set_pixel(tx, ty, Color(0.3, 0.3, 0.3) if truth else Color(0, 0, 0))
			x0 += floorf(tiles_x) - 1.0
		y0 += TILES_PER_SHOT_Y - 1.0
	bad.resize(W * 4, H * 4, Image.INTERPOLATE_NEAREST)
	bad.save_png("user://world_solidity_mismatch.png")
	print("SOLIDITY mismatches: %d (solid drawn open: %d, open drawn solid: %d) of %d tiles" % [solid_open + open_solid, solid_open, open_solid, W * H])
	get_tree().quit()
