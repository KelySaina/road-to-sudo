class_name AdventureWorld
extends RefCounted
## A story world loaded from data/adventure/*.json. Nodes are kept as raw
## dictionaries (one file, no class-per-node); accessors read the fields.

const DATA_PATH := "res://data/adventure/world.json"

var id: String = ""
var title: String = ""
var machine: String = "mainframe"
var start: String = ""
var max_hp: int = 30
var intro: Array = []
var outro: Array = []
var nodes: Dictionary = {}   # id -> raw node dict


static func load_default() -> AdventureWorld:
	return from_dict(JsonLoader.load_dict(DATA_PATH))


static func from_dict(d: Dictionary) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.id = d.get("id", "adventure")
	w.title = d.get("title", "Adventure")
	w.machine = d.get("machine", "mainframe")
	w.start = d.get("start", "")
	w.max_hp = int(d.get("max_hp", 30))
	w.intro = d.get("intro", [])
	w.outro = d.get("outro", [])
	w.nodes = d.get("nodes", {})
	return w


func node(node_id: String) -> Dictionary:
	return nodes.get(node_id, {})


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)


func node_name(node_id: String) -> String:
	return node(node_id).get("name", node_id)


func is_battle(node_id: String) -> bool:
	return node(node_id).get("type", "story") in ["battle", "boss"]


## {"exit key (direction)": "destination id"}
func exits(node_id: String) -> Dictionary:
	return node(node_id).get("exits", {})


func validate() -> Array:
	var problems: Array = []
	if not has_node(start):
		problems.append("start node '%s' does not exist" % start)
	for nid in nodes:
		for dir in exits(nid):
			if not has_node(exits(nid)[dir]):
				problems.append("%s: exit '%s' points to unknown node '%s'" % [nid, dir, exits(nid)[dir]])
		var n: Dictionary = node(nid)
		if is_battle(nid) and n.get("battle", {}).get("success", {}).is_empty():
			problems.append("%s: battle has no success condition" % nid)
	return problems
