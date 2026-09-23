extends Node3D
## Fast WorldVista preview WITHOUT the game: day sky + vista + a flat cut-out of the level painting at z=0
## (sky tiles transparent), from several vantages. Saves user://sky_solo_<spot>.png (1920x1080).
const SPOTS := {
	"spire_top": Vector2(200, 30), "spiregap": Vector2(222, 70), "falls": Vector2(150, 140),
	"pool": Vector2(150, 165), "logo": Vector2(320, 45), "keep": Vector2(300, 70), "grove_top": Vector2(40, 30),
	"wide": Vector2(200, 100),
}
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	get_window().size = Vector2i(1920, 1080)
	var lvl := EELevel.load_file("res://levels/forgotten_veil.eelvl")
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/world/day_sky.gdshader")
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_agx_contrast = 1.35
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.49
	env.adjustment_contrast = 1.16
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := Vector3(-0.30, 0.67, 0.68).normalized()
	var vista := WorldVista.new()
	add_child(vista)
	vista.build(lvl, sun, sm)
	_make_cutout(lvl)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.3
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	var only := OS.get_cmdline_user_args()
	for n in SPOTS:
		if only.size() > 0 and not (n in only):
			continue
		var p: Vector2 = SPOTS[n]
		var zd := 24.8 if n != "wide" else 160.0
		cam.global_position = Vector3(p.x, -p.y, zd)
		for i in 8:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://sky_solo_%s.png" % n)
	get_tree().quit()

func _make_cutout(lvl: EELevel) -> void:
	var mm := Image.load_from_file("res://assets/ee_ref_fv/minimap_ee.png")
	mm.convert(Image.FORMAT_RGBA8)
	for y in lvl.height:
		for x in lvl.width:
			var i := y * lvl.width + x
			if lvl.fg[i] == 0 and lvl.bg[i] in [531, 540, 541, 542]:
				mm.set_pixel(x, y, Color(0, 0, 0, 0))
	var q := QuadMesh.new()
	q.size = Vector2(lvl.width, lvl.height)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(lvl.width * 0.5, -lvl.height * 0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(mm)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
