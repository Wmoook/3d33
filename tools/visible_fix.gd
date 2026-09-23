extends Node
## Mirror-project-only autoload (tools_run_test.sh, visible mode): tests call
## window_set_flag(NO_FOCUS, true) in _ready, which makes Windows show a blank window.
## Keep clearing it so the user can watch the test render.
func _process(_d: float) -> void:
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, false)
