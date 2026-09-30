class_name ChallengeLibrary
extends RefCounted
## Loads levels (ordered chapters) and challenges from data/.
## A level file lists challenge ids in play order; challenges live one per file.

const LEVELS_DIR := "res://data/levels/"
const CHALLENGES_DIR := "res://data/challenges/"

var levels: Array = [] # [{"id", "title", "subtitle", "challenges": [ids], "machine"}], sorted
var challenges: Dictionary = {} # id -> Challenge
var order: Array = [] # flattened campaign order


static func load_default() -> ChallengeLibrary:
	var lib := ChallengeLibrary.new()
	lib.load_from(LEVELS_DIR, CHALLENGES_DIR)
	return lib


func load_from(levels_dir: String, challenges_dir: String) -> void:
	for path in JsonLoader.list_json_files(challenges_dir):
		var data := JsonLoader.load_dict(path)
		if data.is_empty():
			continue
		var c := Challenge.from_dict(data)
		for problem in c.validate():
			push_warning("%s: %s" % [path, problem])
		challenges[c.id] = c
	for path in JsonLoader.list_json_files(levels_dir):
		var lvl := JsonLoader.load_dict(path)
		if not lvl.is_empty():
			levels.append(lvl)
	levels.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for lvl in levels:
		for cid in lvl.get("challenges", []):
			if challenges.has(cid):
				order.append(cid)
				if challenges[cid].level_id == "":
					challenges[cid].level_id = lvl.id
			else:
				push_warning("Level %s references unknown challenge %s" % [lvl.id, cid])


func get_challenge(challenge_id: String) -> Challenge:
	return challenges.get(challenge_id, null)


func get_level(level_id: String) -> Dictionary:
	for lvl in levels:
		if lvl.id == level_id:
			return lvl
	return {}


func next_after(challenge_id: String) -> String:
	var idx := order.find(challenge_id)
	if idx == -1 or idx + 1 >= order.size():
		return ""
	return order[idx + 1]


## First challenge in campaign order that isn't completed.
func first_incomplete(completed: Dictionary) -> String:
	for cid in order:
		if not completed.has(cid):
			return cid
	return ""


func position_of(challenge_id: String) -> Dictionary:
	for lvl in levels:
		var ids: Array = lvl.get("challenges", [])
		var idx := ids.find(challenge_id)
		if idx != -1:
			return {"level": lvl, "index": idx, "count": ids.size()}
	return {}
