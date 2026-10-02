class_name DifficultySettings
extends RefCounted
## One difficulty profile from data/difficulty.json.

const DATA_PATH := "res://data/difficulty.json"

var id: String = "beginner"
var label: String = "Beginner"
var description: String = ""
var show_tips: bool = true
var show_explanations: bool = true
var max_hints: int = 3
var allow_solution: bool = true
var allow_skip: bool = false
var inline_suggestions: bool = true
var xp_multiplier: float = 1.0
var time_bonus: bool = false


static func all() -> Array:
	var out: Array = []
	var data := JsonLoader.load_content_dict(DATA_PATH)
	for key in data.get("order", ["beginner", "normal", "expert"]):
		out.append(from_dict(key, data.get(key, {})))
	return out


static func load_id(difficulty_id: String) -> DifficultySettings:
	var data := JsonLoader.load_content_dict(DATA_PATH)
	if not data.has(difficulty_id):
		difficulty_id = "beginner"
	return from_dict(difficulty_id, data.get(difficulty_id, {}))


static func from_dict(key: String, d: Dictionary) -> DifficultySettings:
	var s := DifficultySettings.new()
	s.id = key
	s.label = d.get("label", key.capitalize())
	s.description = d.get("description", "")
	s.show_tips = d.get("show_tips", true)
	s.show_explanations = d.get("show_explanations", true)
	s.max_hints = int(d.get("max_hints", 3))
	s.allow_solution = d.get("allow_solution", true)
	s.allow_skip = d.get("allow_skip", false)
	s.inline_suggestions = d.get("inline_suggestions", true)
	s.xp_multiplier = float(d.get("xp_multiplier", 1.0))
	s.time_bonus = d.get("time_bonus", false)
	return s
