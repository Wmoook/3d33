class_name LevelCatalog
extends RefCounted
## Multi-level support. Each level is described by res://levels/config/<id>.json (see CONTRACTS.md "Multi-level").
## The chosen level id lives in LevelCatalog.current_id (static) and is set by the shell's level select.

const CONFIG_DIR := "res://levels/config"
static var current_id := "odyssey"

static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(CONFIG_DIR):
		if f.ends_with(".json") and not f.ends_with("_route.json"):
			var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_DIR + "/" + f))
			if cfg is Dictionary and cfg.has("id"):
				out.append(cfg)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 99)) < int(b.get("order", 99)))
	return out

static func get_config(id: String = "") -> Dictionary:
	var want := current_id if id == "" else id
	for c in all():
		if c.id == want:
			return c
	return {}

static func current() -> Dictionary:
	return get_config(current_id)
