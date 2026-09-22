class_name ZoneCard
extends Control
## Cinematic area title card: thin gold rules sweep out from the center, the zone name resolves from wide
## letter-spacing to tight, italic subtitle fades in beneath, then everything dissolves.

const IN_T := 1.1
const HOLD_T := 2.8
const OUT_T := 1.4

var _name := ""
var _sub := ""
var _t := -1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_zone(zone_name: String, subtitle: String) -> void:
	_name = zone_name
	_sub = subtitle
	_t = 0.0

func is_showing() -> bool:
	return _t >= 0.0

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t > IN_T + HOLD_T + OUT_T:
		_t = -1.0
	queue_redraw()

func _draw() -> void:
	if _t < 0.0:
		return
	var total := IN_T + HOLD_T + OUT_T
	var a_in := _ease(clampf(_t / IN_T, 0.0, 1.0))
	var a_out := 1.0 - _ease(clampf((_t - IN_T - HOLD_T) / OUT_T, 0.0, 1.0))
	var a := a_in * a_out
	var cx := size.x * 0.5
	var cy := size.y * 0.24
	# soft dark band behind the text for legibility on bright scenes
	for i in 8:
		var h := 190.0 - i * 20.0
		var w := size.x * (0.9 - i * 0.06)
		draw_rect(Rect2(cx - w * 0.5, cy - h * 0.5 - 4, w, h), Color(0, 0, 0, 0.07 * a))
	var spacing := lerpf(34.0, 14.0, a_in) + (1.0 - a_out) * 10.0
	var f := UITheme.title(0, 700)
	var fs := 66
	var tw := UITheme.spaced_width(f, _name, fs, spacing)
	var gold := Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, a)
	# rules
	var rule_len := 170.0 * _ease(clampf((_t - 0.15) / IN_T, 0.0, 1.0))
	var gap := tw * 0.5 + 34.0
	var ry := cy - 20.0
	draw_line(Vector2(cx - gap - rule_len, ry), Vector2(cx - gap, ry), Color(gold, 0.7 * a), 1.5, true)
	draw_line(Vector2(cx + gap, ry), Vector2(cx + gap + rule_len, ry), Color(gold, 0.7 * a), 1.5, true)
	_diamond(Vector2(cx - gap - rule_len - 8, ry), 4.0, Color(gold, a))
	_diamond(Vector2(cx + gap + rule_len + 8, ry), 4.0, Color(gold, a))
	# name: glow passes then crisp text
	var p := Vector2(cx - tw * 0.5, cy)
	UITheme.draw_spaced(self, f, p + Vector2(0, 3), _name, fs, spacing, Color(0, 0, 0, 0.6 * a))
	UITheme.draw_spaced(self, f, p, _name, fs, spacing, Color(1.0, 0.7, 0.3, 0.07 * a), 10)
	UITheme.draw_spaced(self, f, p, _name, fs, spacing, Color(1.0, 0.75, 0.35, 0.14 * a), 4)
	UITheme.draw_spaced(self, f, p, _name, fs, spacing, Color(1.0, 0.96, 0.88, a))
	# subtitle
	if _sub != "":
		var sa := _ease(clampf((_t - 0.5) / IN_T, 0.0, 1.0)) * a_out
		var sf := UITheme.serif_italic(500)
		var sw := sf.get_string_size(_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		draw_string_outline(sf, Vector2(cx - sw * 0.5, cy + 48), _sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, 6, Color(0, 0, 0, 0.35 * sa))
		draw_string(sf, Vector2(cx - sw * 0.5, cy + 48), _sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.95, 0.9, 0.82, 0.85 * sa))
	if _t > total:
		_t = -1.0

func _diamond(c: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)

static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
