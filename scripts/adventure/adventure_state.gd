class_name AdventureState
extends RefCounted
## Progress through the skill worlds: which world you're in, the skills you've
## collected (per world and overall), and which trials you've passed. Serialized
## into the save file. No health — mistakes are always recoverable.

var world_index: int = 0
var skills: Array = []                 # every command learned, in order (your kit)
var orbs_collected: Dictionary = {}    # world id -> [skill, ...] collected there
var passed: Dictionary = {}            # world id -> true (trial cleared)


func has_skill(skill: String) -> bool:
	return skills.has(skill)


func learn_skill(world_id: String, skill: String) -> bool:
	var here: Array = orbs_collected.get(world_id, [])
	if here.has(skill):
		return false
	here.append(skill)
	orbs_collected[world_id] = here
	if not skills.has(skill):
		skills.append(skill)
	return true


func collected_in(world_id: String) -> Array:
	return orbs_collected.get(world_id, [])


func has_orb(world_id: String, skill: String) -> bool:
	return collected_in(world_id).has(skill)


func is_passed(world_id: String) -> bool:
	return passed.has(world_id)


func mark_passed(world_id: String) -> void:
	passed[world_id] = true


func to_dict() -> Dictionary:
	return {"world_index": world_index, "skills": skills, "orbs_collected": orbs_collected, "passed": passed}


static func from_dict(d: Dictionary) -> AdventureState:
	var s := AdventureState.new()
	s.world_index = int(d.get("world_index", 0))
	s.skills = d.get("skills", [])
	s.orbs_collected = d.get("orbs_collected", {})
	s.passed = d.get("passed", {})
	return s
