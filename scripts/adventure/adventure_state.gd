class_name AdventureState
extends RefCounted
## The player's RPG progress: health, where they are, what they've cleared,
## and the story flags / keys they carry. Serialized into the save file.

var max_hp: int = 30
var hp: int = 30
var current: String = ""
var visited: Dictionary = {}   # node id -> true
var cleared: Dictionary = {}   # node id -> true (battle won)
var flags: Array = []          # story keys, e.g. "keycard", "sudo_access"
var deaths: int = 0
var xp_awarded: Dictionary = {} # node id -> true (so replays don't re-award)


func has_flag(flag: String) -> bool:
	return flags.has(flag)


func add_flag(flag: String) -> void:
	if flag != "" and not flags.has(flag):
		flags.append(flag)


func is_cleared(node_id: String) -> bool:
	return cleared.has(node_id)


func damage(amount: int) -> int:
	hp = maxi(0, hp - amount)
	return hp


func heal_full() -> void:
	hp = max_hp


func to_dict() -> Dictionary:
	return {"max_hp": max_hp, "hp": hp, "current": current, "visited": visited,
		"cleared": cleared, "flags": flags, "deaths": deaths, "xp_awarded": xp_awarded}


static func from_dict(d: Dictionary) -> AdventureState:
	var s := AdventureState.new()
	s.max_hp = int(d.get("max_hp", 30))
	s.hp = int(d.get("hp", s.max_hp))
	s.current = d.get("current", "")
	s.visited = d.get("visited", {})
	s.cleared = d.get("cleared", {})
	s.flags = d.get("flags", [])
	s.deaths = int(d.get("deaths", 0))
	s.xp_awarded = d.get("xp_awarded", {})
	return s
