class_name Progression
extends RefCounted
## XP, ranks and statistics. Ranks can require a challenge as well as XP,
## so grinding XP alone never makes you "sudo".

signal xp_changed(xp: int, rank: Dictionary, progress: float)
signal rank_up(rank: Dictionary)

const DATA_PATH := "res://data/progression.json"

static var _data: Dictionary = {}

var profile: PlayerProfile


func _init(p_profile: PlayerProfile) -> void:
	profile = p_profile


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JsonLoader.load_content_dict(DATA_PATH)
	return _data


static func ranks() -> Array:
	return data().get("ranks", [{"name": "Newbie", "xp": 0}])


## XP for a finished challenge. The bonus shrinks with every hint used and
## vanishes with the solution; the base reward is always granted.
static func score_challenge(challenge: Challenge, hints_used: int, solution_seen: bool, difficulty: DifficultySettings, elapsed: float) -> Dictionary:
	var rules: Dictionary = data().get("xp_rules", {})
	var bonus_table: Array = rules.get("bonus_by_hints", [50, 25, 10, 0])
	var base: int = challenge.xp
	var bonus: int = 0 if solution_seen else int(bonus_table[mini(hints_used, bonus_table.size() - 1)])
	var time_bonus := 0
	if difficulty.time_bonus and challenge.time_limit > 0 and elapsed <= challenge.time_limit and not solution_seen:
		time_bonus = int(rules.get("time_bonus", 25))
	var total := int(round((base + bonus + time_bonus) * difficulty.xp_multiplier))
	return {"base": base, "bonus": bonus, "time_bonus": time_bonus, "multiplier": difficulty.xp_multiplier,
		"total": total, "hints": hints_used, "solution": solution_seen}


func rank_for(xp_value: int) -> Dictionary:
	var best: Dictionary = ranks()[0]
	for r in ranks():
		if xp_value < int(r.get("xp", 0)):
			break
		var needs: String = r.get("requires", "")
		if needs != "" and not profile.completed.has(needs):
			break
		best = r
	return best


func current_rank() -> Dictionary:
	return rank_for(profile.xp)


func next_rank() -> Dictionary:
	var cur := current_rank()
	var list := ranks()
	var idx := list.find(cur)
	return list[idx + 1] if idx != -1 and idx + 1 < list.size() else {}


func progress_to_next() -> float:
	var cur := current_rank()
	var nxt := next_rank()
	if nxt.is_empty():
		return 1.0
	var span := float(int(nxt.xp) - int(cur.xp))
	return clampf((profile.xp - int(cur.xp)) / span, 0.0, 1.0) if span > 0 else 1.0


func award(amount: int) -> void:
	if amount <= 0:
		return
	var before := current_rank()
	profile.xp += amount
	var after := current_rank()
	xp_changed.emit(profile.xp, after, progress_to_next())
	if after.name != before.name:
		rank_up.emit(after)


## Stores the completion and returns the XP actually granted (replays give none).
func record_completion(challenge: Challenge, result: Dictionary) -> int:
	var granted := 0
	if not profile.completed.has(challenge.id):
		granted = int(result.total)
		profile.completed[challenge.id] = {
			"xp": granted, "hints": result.hints, "solution": result.solution,
			"at": int(Time.get_unix_time_from_system()), "seconds": int(result.get("elapsed", 0)),
		}
		profile.bump("challenges_completed")
		if int(result.hints) == 0 and not result.solution:
			profile.bump("no_hint_solves")
	profile.skipped.erase(challenge.id)
	result["new_commands"] = profile.unlock_commands(challenge.unlocks)
	award(granted)
	# Rank gates may open without XP changing (a required challenge was just done).
	xp_changed.emit(profile.xp, current_rank(), progress_to_next())
	return granted


func record_outcome(outcome: ExecutionOutcome) -> void:
	if outcome.line.strip_edges() == "":
		return
	profile.bump("lines_entered")
	for r in outcome.records:
		if int(r.depth) == 0:
			profile.bump("commands_run")
	if outcome.exit_code != 0:
		profile.bump("errors")
	for e in outcome.events:
		match e.name:
			"pipe_used": profile.bump("pipes")
			"redirect_used": profile.bump("redirects")
			"permission_denied": profile.bump("permission_denied")
			"file_deleted": profile.bump("files_deleted")
			"sudo_attempt": profile.bump("sudo_attempts")
			"manual_read": profile.bump("manuals_read")
