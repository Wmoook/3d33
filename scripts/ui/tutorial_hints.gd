class_name TutorialHints
extends Control
## First-run contextual hints: an elegant pill above the bottom edge that fades in when relevant and out once
## the player has done the thing (or after a while). Each hint is shown until completed once, then remembered
## in GameSettings.tutorial (so it never nags again).

signal completed(id: String)

const HINTS := {
	"move": {"keys": ["ARROWS / WASD", "SPACE"], "text": ["roll", "jump"], "icon": "ball", "timeout": 0.0},
	"keys": {"keys": [], "text": ["Keys open the doors of their colour  -  for five seconds"], "icon": "key", "timeout": 7.0},
	"arrows": {"keys": [], "text": ["Arrows change the direction of gravity"], "icon": "arrow", "timeout": 6.0},
	"god": {"keys": ["G"], "text": ["god mode: fly freely, press again to return"], "icon": "ball", "timeout": 5.0},
}

var done := {}           # id -> true (persisted by the game)
var _cur := ""
var _t := 0.0
var _a := 0.0
var _closing := false
var _queue: Array[String] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Show a hint if it was never completed. Lower-priority hints don't interrupt a visible one.
func offer(id: String) -> void:
	if done.has(id) or not HINTS.has(id) or id == _cur or id in _queue:
		return
	if _cur != "":
		_queue.append(id)   # shown after the current one
		return
	_cur = id
	_t = 0.0
	_closing = false

## Mark a hint as learned; fades it out if visible.
func complete(id: String) -> void:
	_queue.erase(id)
	if done.has(id):
		return
	done[id] = true
	completed.emit(id)
	if _cur == id:
		_closing = true

func is_showing(id: String) -> bool:
	return _cur == id and not _closing

func _process(delta: float) -> void:
	if _cur == "":
		_a = 0.0
		return
	_t += delta
	var to: float = HINTS[_cur].timeout
	if to > 0.0 and _t > to:
		complete(_cur)
	_a = move_toward(_a, 0.0 if _closing else 1.0, delta * (1.5 if _closing else 2.5))
	if _closing and _a <= 0.0:
		_cur = ""
		_closing = false
		while not _queue.is_empty():
			var nx: String = _queue.pop_front()
			if not done.has(nx):
				_cur = nx
				_t = 0.0
				break
	queue_redraw()

func _draw() -> void:
	if _cur == "" or _a <= 0.001:
		return
	var h: Dictionary = HINTS[_cur]
	var fk := UITheme.hud(3)
	var ft := UITheme.hud_medium(2)
	var parts: Array = []   # [kind, string, width]
	for i in h.text.size():
		if i < h.keys.size():
			parts.append(["key", h.keys[i], fk.get_string_size(h.keys[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 22])
		parts.append(["text", h.text[i], ft.get_string_size(h.text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x])
	var w := 64.0
	for p in parts:
		w += p[2] + 14.0
	w += 20.0
	var e := 1.0 - pow(1.0 - _a, 3.0)
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 150.0 + (1.0 - e) * 18.0, w, 54)
	var sb := UITheme.glass_box(27, 0.62 * e)
	sb.border_color = Color(UITheme.GOLD, 0.35 * e)
	draw_style_box(sb, r)
	_icon(h.icon, r.position + Vector2(34, 27), e)
	var x := r.position.x + 64.0
	for p in parts:
		if p[0] == "key":
			var kb := StyleBoxFlat.new()
			kb.bg_color = Color(1, 1, 1, 0.12 * e)
			kb.border_color = Color(1, 1, 1, 0.35 * e)
			kb.set_border_width_all(1)
			kb.set_corner_radius_all(6)
			draw_style_box(kb, Rect2(x, r.position.y + 11, p[2], 32))
			draw_string(fk, Vector2(x + 11, r.position.y + 34), p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, e))
		else:
			draw_string(ft, Vector2(x, r.position.y + 35), p[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.96, 0.9, 0.9 * e))
		x += p[2] + 14.0

func _icon(kind: String, c: Vector2, a: float) -> void:
	var g := Color(UITheme.GOLD, a)
	match kind:
		"ball":
			draw_circle(c, 12, Color(1.0, 0.8, 0.35, a))
			draw_arc(c + Vector2(0, 2), 5.5, 0.3, PI - 0.3, 10, Color(0.25, 0.15, 0.05, a), 2.0, true)
			draw_circle(c + Vector2(-4, -3), 1.6, Color(0.25, 0.15, 0.05, a))
			draw_circle(c + Vector2(4, -3), 1.6, Color(0.25, 0.15, 0.05, a))
		"key":
			var kc := Color(1.0, 0.35, 0.3, a)
			draw_arc(c + Vector2(-6, 0), 6.0, 0, TAU, 20, kc, 3.0, true)
			draw_line(c + Vector2(0, 0), c + Vector2(12, 0), kc, 3.0, true)
			draw_line(c + Vector2(8, 0), c + Vector2(8, 5), kc, 3.0, true)
			draw_line(c + Vector2(12, 0), c + Vector2(12, 5), kc, 3.0, true)
		"arrow":
			var pts := PackedVector2Array([c + Vector2(-10, -7), c + Vector2(4, -7), c + Vector2(4, -12), c + Vector2(13, 0),
				c + Vector2(4, 12), c + Vector2(4, 7), c + Vector2(-10, 7)])
			draw_colored_polygon(pts, g)
