class_name AchievementSystem
extends RefCounted
## Data-driven achievements (data/achievements.json).
##
## Trigger forms:
##   {"event": "pipe_used", "data_gte": {"length": 4}, "data_eq": {...}, "data_contains": {...}}
##   {"stat": "commands_run", "gte": 1}
##   {"command": "whoami"}           a successful run of that command
##   {"challenge": "t10_incident"}   challenge completed
##   {"rank": "Shell Apprentice"}
##   {"any": [trigger, ...]}

signal unlocked(achievement: Dictionary)

const DATA_PATH := "res://data/achievements.json"

var definitions: Array = []
var profile: PlayerProfile


static func load_default(p_profile: PlayerProfile) -> AchievementSystem:
	var a := AchievementSystem.new()
	a.profile = p_profile
	a.definitions = JsonLoader.load_array(DATA_PATH)
	return a


func is_unlocked(achievement_id: String) -> bool:
	return profile.achievements.has(achievement_id)


func check_outcome(outcome: ExecutionOutcome) -> void:
	for def in definitions:
		if not is_unlocked(def.id) and _outcome_matches(def.trigger, outcome):
			_unlock(def)
	check_stats()


func check_stats() -> void:
	for def in definitions:
		if not is_unlocked(def.id) and _stat_matches(def.trigger):
			_unlock(def)


func check_challenge(challenge_id: String) -> void:
	for def in definitions:
		if not is_unlocked(def.id) and _challenge_matches(def.trigger, challenge_id):
			_unlock(def)
	check_stats()


func check_rank(rank_name: String) -> void:
	for def in definitions:
		if not is_unlocked(def.id) and def.trigger.get("rank", "") == rank_name:
			_unlock(def)


func check_event(event_name: String, data: Dictionary = {}) -> void:
	var fake := ExecutionOutcome.new()
	fake.emit(event_name, data)
	check_outcome(fake)


func _unlock(def: Dictionary) -> void:
	profile.achievements[def.id] = int(Time.get_unix_time_from_system())
	unlocked.emit(def)


func _outcome_matches(trigger: Dictionary, outcome: ExecutionOutcome) -> bool:
	if trigger.has("any"):
		for t in trigger.any:
			if _outcome_matches(t, outcome):
				return true
		return false
	if trigger.has("command"):
		for r in outcome.records:
			if r.name == trigger.command and int(r.exit_code) == 0:
				return true
	if trigger.has("event"):
		for e in outcome.events:
			if e.name == trigger.event and _data_matches(trigger, e.data):
				return true
	return false


func _data_matches(trigger: Dictionary, data: Dictionary) -> bool:
	var eq: Dictionary = trigger.get("data_eq", {})
	for k in eq:
		if str(data.get(k, "")) != str(eq[k]):
			return false
	var gte: Dictionary = trigger.get("data_gte", {})
	for k in gte:
		if float(data.get(k, 0)) < float(gte[k]):
			return false
	var contains: Dictionary = trigger.get("data_contains", {})
	for k in contains:
		if not str(data.get(k, "")).contains(str(contains[k])):
			return false
	return true


func _stat_matches(trigger: Dictionary) -> bool:
	if trigger.has("any"):
		for t in trigger.any:
			if _stat_matches(t):
				return true
		return false
	if not trigger.has("stat"):
		return false
	return int(profile.stats.get(trigger.stat, 0)) >= int(trigger.get("gte", 1))


func _challenge_matches(trigger: Dictionary, challenge_id: String) -> bool:
	if trigger.has("any"):
		for t in trigger.any:
			if _challenge_matches(t, challenge_id):
				return true
		return false
	return trigger.get("challenge", "") == challenge_id


func unlocked_count() -> int:
	return profile.achievements.size()
