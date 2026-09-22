class_name EEInput
extends RefCounted
## Held key states for one EE physics tick (like Bl.isKeyDown in the original).
## The shell fills this every _physics_process and passes it to EESim.tick().

var left := false
var right := false
var up := false
var down := false
## Space held.
var jump := false
## Optional: set true when Space was pressed since the previous tick (EE "isJustPressed").
## Lets a tap shorter than one tick still register. If never set, EESim derives the
## edge from `jump` (pressed now, not pressed last tick). EESim clears it after use.
var jump_pressed := false
## Optional: G was pressed since the previous tick (toggle god mode). Cleared after use.
var god_toggle := false

func clear() -> void:
	left = false; right = false; up = false; down = false
	jump = false; jump_pressed = false; god_toggle = false

func copy_from(o: EEInput) -> void:
	left = o.left; right = o.right; up = o.up; down = o.down
	jump = o.jump; jump_pressed = o.jump_pressed; god_toggle = o.god_toggle
