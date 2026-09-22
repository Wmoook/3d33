class_name VictoryScreen
extends Control
## Level-complete card (sim "complete" event, EE's brick-complete block 121): golden bloom, title,
## run stats (time, coins, deaths). Any key dismisses; the run continues like in EE.

signal closed

var title_text := "ODYSSEY COMPLETE"
var eyebrow_text := "THE  SOUL  RETURNS"
var subline := ""                     # e.g. "All 16 trials conquered"
var stat_keys: Array = ["time", "coins", "blue", "deaths"]
var stats := {"time": 0.0, "coins": 0, "coins_total": 0, "blue": 0, "blue_total": 0, "deaths": 0}
var _t := -1.0
var _out := -1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func show_stats(s: Dictionary) -> void:
	stats = s
	_t = 0.0
	_out = -1.0
	visible = true

func is_open() -> bool:
	return visible and _out < 0.0

## Returns true if the dismissal was accepted (after the stats have landed).
func dismiss() -> bool:
	if _t > 1.5 and _out < 0.0:
		_out = 0.0
		return true
	return false

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _out >= 0.0:
		_out += delta
		if _out > 0.8:
			visible = false
			closed.emit()
	queue_redraw()

func _k(s: float, d: float) -> float:
	var x := clampf((_t - s) / d, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _draw() -> void:
	var W := size.x
	var H := size.y
	var o := 1.0 if _out < 0.0 else 1.0 - clampf(_out / 0.8, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.015, 0.01, 0.62 * _k(0.0, 1.0) * o))
	var c := Vector2(W * 0.5, H * 0.42)
	for i in 10:
		draw_circle(c, (520.0 - i * 44.0) * (0.6 + 0.4 * _k(0.0, 1.6)), Color(1.0, 0.72, 0.3, 0.018 * _k(0.0, 1.2) * o))
	var a := _k(0.3, 1.4) * o
	var sp := lerpf(60.0, 20.0, _k(0.3, 2.0))
	var f := UITheme.title(0, 800)
	var vt := title_text
	var vp := Vector2(W * 0.5 - UITheme.spaced_width(f, vt, 96, sp) * 0.5, c.y)
	draw_string(UITheme.hud_medium(9), Vector2(0, c.y - 110), eyebrow_text, HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 1, 0.6 * _k(0.1, 1.0) * o))
	UITheme.draw_spaced(self, f, vp, vt, 96, sp, Color(1, 0.7, 0.3, 0.1 * a), 14)
	UITheme.draw_spaced(self, f, vp, vt, 96, sp, Color(1.0, 0.88, 0.6, a))
	if stats.get("new_best", false):
		var pb := 0.75 + 0.25 * sin(_t * 3.0)
		draw_string(UITheme.hud(8), Vector2(0, c.y + 84), "NEW  BEST  TIME", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(UITheme.GOLD, pb * _k(1.2, 0.6) * o))
	elif float(stats.get("best", -1.0)) > 0.0:
		var b: float = stats.best
		draw_string(UITheme.hud_medium(4), Vector2(0, c.y + 84), "BEST  %02d:%05.2f" % [int(b / 60.0), fmod(b, 60.0)], HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 1, 0.5 * _k(1.2, 0.6) * o))
	var rk := _k(1.0, 1.0) * o
	draw_line(Vector2(c.x - 300 * rk, c.y + 36), Vector2(c.x + 300 * rk, c.y + 36), Color(UITheme.GOLD, 0.7 * rk), 1.5, true)
	var t: float = stats.time
	var all_cols := {"time": ["TIME", "%02d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]],
		"coins": ["COINS", "%d / %d" % [stats.coins, stats.coins_total]],
		"trials": ["TRIALS", "%d / %d" % [stats.coins, stats.coins_total]],
		"blue": ["BLUE COINS", "%d / %d" % [stats.blue, stats.blue_total]],
		"deaths": ["DEATHS", str(stats.deaths)]}
	var cols := []
	for k in stat_keys:
		cols.append(all_cols[k])
	if subline != "":
		draw_string(UITheme.serif_italic(500), Vector2(0, c.y + 118), subline, HORIZONTAL_ALIGNMENT_CENTER, W, 30,
			Color(1, 0.94, 0.85, 0.85 * _k(1.1, 0.8) * o))
	var cw := 260.0
	var x0 := c.x - cw * cols.size() * 0.5
	for i in cols.size():
		var ka := _k(1.3 + i * 0.15, 0.8) * o
		var x := x0 + i * cw
		draw_string(UITheme.hud_medium(6), Vector2(x, c.y + 142), cols[i][0], HORIZONTAL_ALIGNMENT_CENTER, cw, 18, Color(1, 1, 1, 0.5 * ka))
		draw_string(UITheme.hud(), Vector2(x, c.y + 192), cols[i][1], HORIZONTAL_ALIGNMENT_CENTER, cw, 44, Color(1, 0.95, 0.85, ka))
	if _t > 2.5:
		var pk := (0.55 + 0.45 * sin(_t * 2.6)) * o
		draw_string(UITheme.hud(8), Vector2(0, H * 0.82), "ANY KEY   continue exploring          R   new run", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 1, pk))
		if stats.get("new_best", false):
			draw_string(UITheme.hud_medium(3), Vector2(0, H * 0.82 + 38), "your ghost will race you next time  -  H toggles it", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(1, 1, 1, 0.45 * o))
