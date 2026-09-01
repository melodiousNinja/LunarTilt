class_name SettingsStore
extends Node

## Global quality/feature toggles. Read by the main scene and physics.
## Kept intentionally tiny so the game boots cleanly and tests stay focused.

## Show the drag-to-aim trajectory guide. Online ranked later disables it.
var show_guide: bool = true:
	set(value):
		show_guide = value
		save()

## Master scale for shot power (m/s per drag pixel). Tuned so max pull
## (~300 px) roughly reaches the far gutter region.
var power_scale: float = 0.011:
	set(value):
		power_scale = value
		save()

var _path := "user://settings.cfg"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) == OK:
		show_guide = cfg.get_value("ui", "show_guide", show_guide)
		power_scale = float(cfg.get_value("physics", "power_scale", power_scale))


func reset_defaults() -> void:
	show_guide = true
	power_scale = 0.011


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "show_guide", show_guide)
	cfg.set_value("physics", "power_scale", power_scale)
	cfg.save(_path)