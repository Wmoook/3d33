class_name GameSettings
extends RefCounted
## Persistent player settings (user://settings.cfg).

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]

var master := 0.9
var music := 0.7
var sfx := 0.85
var zoom := 30.0        # tiles visible horizontally (lead: ~30 default, 20-60 range)
var quality := 3        # 0..3
var fullscreen := false
var show_hints := true
var tutorial := {}       # first-run hints already learned (id -> true)
var persist := true      # tests turn this off

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master = cf.get_value("audio", "master", master)
	music = cf.get_value("audio", "music", music)
	sfx = cf.get_value("audio", "sfx", sfx)
	zoom = clampf(cf.get_value("video", "zoom2", zoom), 20.0, 60.0)
	quality = cf.get_value("video", "quality", quality)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	show_hints = cf.get_value("ui", "show_hints", show_hints)
	tutorial = cf.get_value("ui", "tutorial", tutorial)

func save_settings() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("video", "zoom2", zoom)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("ui", "show_hints", show_hints)
	cf.set_value("ui", "tutorial", tutorial)
	cf.save(PATH)

func set_value(key: String, v: Variant) -> void:
	set(key, v)
	save_settings()
	changed.emit()
