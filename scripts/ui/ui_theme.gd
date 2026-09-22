class_name UITheme
## Shared fonts, palette and widget styling for the shell UI.
## Fonts (SIL OFL, assets/ui/fonts): Cinzel (titles), Cormorant Garamond Italic (flavor), Rajdhani (HUD numerals).

const GOLD := Color(1.0, 0.82, 0.45)
const GOLD_DEEP := Color(0.78, 0.52, 0.18)
const BLUE_COIN := Color(0.45, 0.78, 1.0)
const INK := Color(0.93, 0.92, 0.88)
const INK_DIM := Color(0.93, 0.92, 0.88, 0.55)
const GLASS := Color(0.035, 0.04, 0.06, 0.55)
const KEY_COLORS := {&"red": Color(1.0, 0.3, 0.28), &"green": Color(0.35, 1.0, 0.45), &"blue": Color(0.35, 0.6, 1.0)}

static var _cache := {}

static func _file(path: String) -> Font:
	if _cache.has(path):
		return _cache[path]
	var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	_cache[path] = f
	return f

static func _var(key: String, base_path: String, weight: int, spacing: int = 0) -> Font:
	if _cache.has(key):
		return _cache[key]
	var fv := FontVariation.new()
	fv.base_font = _file(base_path)
	if weight > 0:
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing
	_cache[key] = fv
	return fv

static func title(spacing: int = 0, weight: int = 700) -> Font:
	return _var("title_%d_%d" % [spacing, weight], "res://assets/ui/fonts/Cinzel.ttf", weight, spacing)

static func serif_italic(weight: int = 500) -> Font:
	return _var("ital_%d" % weight, "res://assets/ui/fonts/CormorantGaramond-Italic.ttf", weight)

static func hud(spacing: int = 0) -> Font:
	return _var("hud_%d" % spacing, "res://assets/ui/fonts/Rajdhani-SemiBold.ttf", 0, spacing)

static func hud_medium(spacing: int = 0) -> Font:
	return _var("hudm_%d" % spacing, "res://assets/ui/fonts/Rajdhani-Medium.ttf", 0, spacing)

## Animated letter-spacing WITHOUT creating a new FontVariation per spacing value (each new variation is a new
## glyph cache = rasterization hitches on the frame a card animates). Draws glyph by glyph with a fixed font.
static func spaced_width(f: Font, text: String, fs: int, spacing: float) -> float:
	var w := 0.0
	for i in text.length():
		w += f.get_char_size(text.unicode_at(i), fs).x + spacing
	return w - spacing

## outline > 0 draws the outline pass instead of the fill.
static func draw_spaced(ci: CanvasItem, f: Font, pos: Vector2, text: String, fs: int, spacing: float, color: Color, outline: int = 0) -> void:
	var x := pos.x
	for i in text.length():
		var c := text.unicode_at(i)
		if outline > 0:
			ci.draw_char_outline(f, Vector2(x, pos.y), text[i], fs, outline, color)
		else:
			ci.draw_char(f, Vector2(x, pos.y), text[i], fs, color)
		x += f.get_char_size(c, fs).x + spacing

## Rasterize every glyph the animated cards use, at their sizes, once (called behind the loading screen),
## so the first zone card / title / victory never stalls on glyph uploads.
static func warm_glyphs(ci: CanvasItem) -> void:
	var caps := "ABCDEFGHIJKLMNOPQRSTUVWXYZ'-.,!"
	var lower := "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ.,'!-"
	var digits := "0123456789:./%+ BESTIMCOINSDEATH"
	var faint := Color(1, 1, 1, 0.004)
	for pair in [[title(0, 700), 66], [title(0, 800), 164], [title(0, 800), 96], [title(0, 700), 58]]:
		ci.draw_string(pair[0], Vector2(-4000, -4000), caps, HORIZONTAL_ALIGNMENT_LEFT, -1, pair[1], faint)
		ci.draw_string_outline(pair[0], Vector2(-4000, -4000), caps, HORIZONTAL_ALIGNMENT_LEFT, -1, pair[1], 10, faint)
	for sz in [32, 42, 28, 30]:
		ci.draw_string(serif_italic(500), Vector2(-4000, -4000), lower, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, faint)
	for sz in [44, 42, 24, 26, 20, 22]:
		ci.draw_string(hud(), Vector2(-4000, -4000), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, faint)

## One soft, feathered black scrim (elliptical gaussian falloff, no edges). Draw it scaled to the text:
## draw_scrim(ci, center, size, alpha). Reads on bright skies without showing any panel shape.
static func scrim_tex() -> Texture2D:
	if _cache.has("scrim"):
		return _cache["scrim"]
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (x + 0.5 - w * 0.5) / (w * 0.5)
			var dy := (y + 0.5 - h * 0.5) / (h * 0.5)
			var d2 := dx * dx + dy * dy
			var a := clampf(exp(-d2 * 3.2) - exp(-3.2), 0.0, 1.0) / (1.0 - exp(-3.2))
			img.set_pixel(x, y, Color(0, 0, 0, a))
	var t := ImageTexture.create_from_image(img)
	_cache["scrim"] = t
	return t

static func draw_scrim(ci: CanvasItem, center: Vector2, sz: Vector2, alpha: float) -> void:
	if alpha <= 0.001:
		return
	ci.draw_texture_rect(scrim_tex(), Rect2(center - sz * 0.5, sz), false, Color(1, 1, 1, alpha))

static func glass_box(radius: int = 14, alpha: float = 0.55) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GLASS.r, GLASS.g, GLASS.b, alpha)
	sb.set_corner_radius_all(radius)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	return sb

## Menu theme: flat text buttons with a gold underline glow on focus/hover, slim sliders.
static func menu_theme() -> Theme:
	if _cache.has("menu_theme"):
		return _cache["menu_theme"]
	var th := Theme.new()
	th.default_font = hud_medium(2)
	th.default_font_size = 26
	var empty := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 0.85, 0.5, 0.07)
	hover.border_color = GOLD
	hover.border_width_left = 3
	hover.set_corner_radius_all(4)
	hover.content_margin_left = 22
	hover.content_margin_right = 16
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	var normal := hover.duplicate() as StyleBoxFlat
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = Color(1, 1, 1, 0)
	for s in [&"normal", &"disabled"]:
		th.set_stylebox(s, &"Button", normal)
	for s in [&"hover", &"pressed", &"focus", &"hover_pressed"]:
		th.set_stylebox(s, &"Button", hover)
	th.set_color(&"font_color", &"Button", INK_DIM)
	th.set_color(&"font_hover_color", &"Button", GOLD)
	th.set_color(&"font_focus_color", &"Button", GOLD)
	th.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	th.set_color(&"font_hover_pressed_color", &"Button", Color.WHITE)
	th.set_constant(&"h_separation", &"Button", 10)
	th.set_font(&"font", &"Button", hud(4))
	th.set_font_size(&"font_size", &"Button", 30)
	# Slider
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD
	th.set_stylebox(&"slider", &"HSlider", track)
	th.set_stylebox(&"grabber_area", &"HSlider", fill)
	th.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	th.set_icon(&"grabber", &"HSlider", _dot_tex(22, Color.WHITE))
	th.set_icon(&"grabber_highlight", &"HSlider", _dot_tex(26, GOLD))
	th.set_stylebox(&"focus", &"HSlider", empty)
	th.set_color(&"font_color", &"Label", INK)
	th.set_font(&"font", &"Label", hud_medium(2))
	th.set_font_size(&"font_size", &"Label", 24)
	_cache["menu_theme"] = th
	return th

static func _dot_tex(size: int, c: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - 1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

## Draws a gold coin (or blue) centered at c, facing ratio sx (spin: 1 = face-on). Used by HUD + minimap legend.
static func draw_coin(ci: CanvasItem, c: Vector2, r: float, sx: float, blue: bool, flash: float = 0.0) -> void:
	var base := BLUE_COIN if blue else GOLD
	var deep := Color(0.12, 0.35, 0.75) if blue else GOLD_DEEP
	sx = maxf(absf(sx), 0.3)
	ci.draw_set_transform(c, 0.0, Vector2(sx, 1.0))
	# glow
	for i in 4:
		ci.draw_circle(Vector2.ZERO, r * (1.55 - i * 0.12), Color(base.r, base.g, base.b, 0.035 + flash * 0.08))
	ci.draw_circle(Vector2.ZERO, r, deep)
	ci.draw_circle(Vector2.ZERO, r * 0.84, base.lerp(Color.WHITE, 0.1 + flash * 0.5))
	ci.draw_circle(Vector2.ZERO, r * 0.62, base.lerp(deep, 0.35))
	ci.draw_arc(Vector2.ZERO, r * 0.72, deg_to_rad(200), deg_to_rad(290), 16, Color(1, 1, 1, 0.75), r * 0.12, true)
	# emblem: a small star/diamond
	var s := r * 0.3
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s * 0.6, 0), Vector2(0, s), Vector2(-s * 0.6, 0)]),
		base.lerp(Color.WHITE, 0.55))
	ci.draw_set_transform(Vector2.ZERO)
