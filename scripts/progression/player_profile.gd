class_name PlayerProfile
extends RefCounted
## Everything that persists about the player. Serialized by SaveManager.

const VERSION := 1

var xp: int = 0
var difficulty: String = "beginner"
var started: bool = false
var current_challenge: String = ""
var completed: Dictionary = {} # id -> {"xp", "hints", "solution", "at", "seconds"}
var skipped: Array = []
var hints_used: Dictionary = {} # id -> hints revealed so far
var solutions_seen: Array = []
var unlocked_commands: Array = ["help", "man", "clear", "history"]
var achievements: Dictionary = {} # id -> unix time
var stats: Dictionary = {}
var settings: Dictionary = {}
var created_at: int = 0


func _init() -> void:
	created_at = int(Time.get_unix_time_from_system())
	stats = default_stats()
	settings = default_settings()


static func default_stats() -> Dictionary:
	return {
		"lines_entered": 0, "commands_run": 0, "errors": 0, "pipes": 0,
		"redirects": 0, "permission_denied": 0, "files_deleted": 0,
		"sudo_attempts": 0, "manuals_read": 0, "hints_used": 0,
		"resets": 0, "no_hint_solves": 0, "challenges_completed": 0, "adventures_won": 0,
		"play_seconds": 0,
	}


static func default_settings() -> Dictionary:
	return {"text_speed": "fast", "font_size": 17, "show_clock": true}


## Returns the commands that were not unlocked before.
func unlock_commands(names: Array) -> Array:
	var fresh: Array = []
	for n in names:
		if not unlocked_commands.has(n):
			unlocked_commands.append(n)
			fresh.append(n)
	return fresh


func bump(stat: String, amount: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + amount


func to_dict() -> Dictionary:
	return {
		"version": VERSION, "xp": xp, "difficulty": difficulty, "started": started,
		"current_challenge": current_challenge, "completed": completed, "skipped": skipped,
		"hints_used": hints_used, "solutions_seen": solutions_seen,
		"unlocked_commands": unlocked_commands, "achievements": achievements,
		"stats": stats, "settings": settings, "created_at": created_at,
	}


static func from_dict(d: Dictionary) -> PlayerProfile:
	var p := PlayerProfile.new()
	p.xp = int(d.get("xp", 0))
	p.difficulty = d.get("difficulty", "beginner")
	p.started = d.get("started", false)
	p.current_challenge = d.get("current_challenge", "")
	p.completed = d.get("completed", {})
	p.skipped = d.get("skipped", [])
	p.hints_used = d.get("hints_used", {})
	p.solutions_seen = d.get("solutions_seen", [])
	p.unlocked_commands = d.get("unlocked_commands", p.unlocked_commands)
	p.achievements = d.get("achievements", {})
	var stats_in: Dictionary = d.get("stats", {})
	for k in stats_in:
		p.stats[k] = stats_in[k]
	var settings_in: Dictionary = d.get("settings", {})
	for k in settings_in:
		p.settings[k] = settings_in[k]
	p.created_at = int(d.get("created_at", p.created_at))
	return p
