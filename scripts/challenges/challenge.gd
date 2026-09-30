class_name Challenge
extends RefCounted
## A challenge definition loaded from data/challenges/*.json.
## Pure data: no behaviour beyond small accessors.

var id: String = ""
var title: String = ""
var level_id: String = ""
var objective: String = ""
## Shown instead of `objective` in Expert mode (vaguer, like a real ticket).
var expert_objective: String = ""
var briefing: Array = []
var expert_briefing: Array = [] # optional: replaces briefing in Expert mode
var tips: Array = [] # Beginner-only nudges shown with the briefing
var hints: Array = []
var solution: String = ""
var explanation: String = "" # "What you just learned", shown on success
var xp: int = 100
var time_limit: int = 0 # seconds; Expert time bonus threshold (0 = none)
var unlocks: Array = []
var teaches: Array = [] # concept tags, for the codex / stats
var machine: String = "" # machine id to boot; "" keeps the current one
var fresh_machine: bool = false
var setup: Dictionary = {}
var success: Dictionary = {}
var reactions: Array = []
var protected_paths: Array = []


static func from_dict(d: Dictionary) -> Challenge:
	var c := Challenge.new()
	c.id = d.get("id", "")
	c.title = d.get("title", c.id)
	c.level_id = d.get("level", "")
	c.objective = d.get("objective", "")
	c.expert_objective = d.get("expert_objective", "")
	c.briefing = d.get("briefing", [])
	c.expert_briefing = d.get("expert_briefing", [])
	c.tips = d.get("tips", [])
	c.hints = d.get("hints", [])
	c.solution = d.get("solution", "")
	c.explanation = d.get("explanation", "")
	c.xp = int(d.get("xp", 100))
	c.time_limit = int(d.get("time_limit", 0))
	c.unlocks = d.get("unlocks", [])
	c.teaches = d.get("teaches", [])
	c.machine = d.get("machine", "")
	c.fresh_machine = d.get("fresh_machine", false)
	c.setup = d.get("setup", {})
	c.success = d.get("success", {})
	c.reactions = d.get("reactions", [])
	c.protected_paths = d.get("protected", [])
	return c


func objective_for(difficulty: String) -> String:
	if difficulty == "expert" and expert_objective != "":
		return expert_objective
	return objective


func briefing_for(difficulty: String) -> Array:
	if difficulty == "expert" and not expert_briefing.is_empty():
		return expert_briefing
	return briefing


func validate() -> Array:
	var problems: Array = []
	if id == "":
		problems.append("missing id")
	if objective == "":
		problems.append("%s: missing objective" % id)
	if success.is_empty():
		problems.append("%s: missing success condition" % id)
	if hints.is_empty():
		problems.append("%s: no hints" % id)
	return problems
