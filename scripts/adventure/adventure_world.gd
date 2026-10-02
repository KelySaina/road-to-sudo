class_name AdventureWorld
extends RefCounted
## Adventure content: an ordered list of WORLDS. Each world has skill orbs (a
## command to learn) and a trial (a real, state-checked challenge you solve with
## those skills). Loaded from data/adventure/worlds.json; worlds stay raw dicts.

const DATA_PATH := "res://data/adventure/worlds.json"

var id: String = ""
var title: String = ""
var machine: String = "mainframe"
var intro: Array = []
var outro: Array = []
var worlds: Array = []   # ordered list of raw world dicts


static func load_default() -> AdventureWorld:
	return from_dict(JsonLoader.load_content_dict(DATA_PATH))


static func from_dict(d: Dictionary) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.id = d.get("id", "adventure")
	w.title = d.get("title", "Adventure")
	w.machine = d.get("machine", "mainframe")
	w.intro = d.get("intro", [])
	w.outro = d.get("outro", [])
	w.worlds = d.get("worlds", [])
	return w


func count() -> int:
	return worlds.size()


func world_at(index: int) -> Dictionary:
	return worlds[index] if index >= 0 and index < worlds.size() else {}


func index_of(world_id: String) -> int:
	for i in worlds.size():
		if str(worlds[i].get("id", "")) == world_id:
			return i
	return -1


func world_name(index: int) -> String:
	return str(world_at(index).get("name", "World %d" % (index + 1)))


func orbs(index: int) -> Array:
	return world_at(index).get("orbs", [])


func trial(index: int) -> Dictionary:
	return world_at(index).get("trial", {})


func is_final(index: int) -> bool:
	return bool(world_at(index).get("final", false)) or index == worlds.size() - 1


func validate() -> Array:
	var problems: Array = []
	if worlds.is_empty():
		problems.append("no worlds defined")
	for i in worlds.size():
		var wd: Dictionary = worlds[i]
		if orbs(i).is_empty():
			problems.append("%s: no skill orbs" % wd.get("id", i))
		if trial(i).get("success", {}).is_empty():
			problems.append("%s: trial has no success condition" % wd.get("id", i))
		if trial(i).get("hints", []).is_empty():
			problems.append("%s: trial has no hints" % wd.get("id", i))
	return problems
