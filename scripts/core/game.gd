extends Node
## Composition root (autoload "Game"). Builds the systems, owns the active
## session and relays system signals to the EventBus. Game rules live in the
## subsystems (Shell, ChallengeManager, Progression, AchievementSystem).

const CAMPAIGN_SLOT := "campaign"
const PRACTICE_SLOT := "practice"
const ADVENTURE_SLOT := "adventure"
const PRACTICE_MACHINE := "sandbox"
const PLAYER := "player"
const AUTOSAVE_EVERY_LINES := 8

var registry: CommandRegistry
var library: ChallengeLibrary
var profile: PlayerProfile
var difficulty: DifficultySettings
var progression: Progression
var achievements: AchievementSystem
var challenges: ChallengeManager
var adventure: AdventureManager
var meta: MetaCommands
var session: ShellSession
var shell: Shell
var mode: String = "" # "campaign" | "practice"

var _lines_since_save := 0
var _completing := false
var _deferred_rank: Dictionary = {}
var _machine_id := ""
var _session_started_msec := 0


func _ready() -> void:
	registry = CommandRegistry.create_default()
	var p := SaveManager.load_profile()
	I18n.set_locale(str(p.settings.get("locale", I18n.DEFAULT_LOCALE)))
	library = ChallengeLibrary.load_default()
	meta = MetaCommands.new(self)
	_load_profile(p)


## Change the interface language. Reloads the content that was cached at boot
## (challenges, difficulty) so the next screen is in the new language; the menu
## rebuilds itself after this via EventBus.menu_requested. Terminal output is
## untouched — it is English on purpose.
func set_locale(code: String) -> void:
	I18n.set_locale(code)
	profile.settings["locale"] = I18n.locale()
	library = ChallengeLibrary.load_default()
	difficulty = DifficultySettings.load_id(profile.difficulty)
	save_now()


func _load_profile(p: PlayerProfile) -> void:
	profile = p
	difficulty = DifficultySettings.load_id(profile.difficulty)
	progression = Progression.new(profile)
	progression.xp_changed.connect(func(xp, rank, pr): EventBus.xp_changed.emit(xp, rank, pr))
	progression.rank_up.connect(_on_rank_up)
	achievements = AchievementSystem.load_default(profile)
	achievements.unlocked.connect(func(def): EventBus.achievement_unlocked.emit(def))
	challenges = ChallengeManager.new(library, profile, difficulty)
	challenges.machine_factory = func(machine_id: String) -> Machine: return MachineBuilder.load_machine(machine_id, registry.primary_names())
	challenges.challenge_started.connect(_on_challenge_started)
	challenges.challenge_completed.connect(_on_challenge_completed)
	challenges.hint_revealed.connect(_on_hint_revealed)
	challenges.narrate.connect(func(text, kind): EventBus.narrate.emit(text, kind))
	adventure = AdventureManager.new()
	adventure.machine_factory = func(machine_id: String) -> Machine: return MachineBuilder.load_machine(machine_id, registry.primary_names())
	adventure.narrate.connect(func(text, kind): EventBus.narrate.emit(text, kind))
	adventure.state_changed.connect(func(): EventBus.adventure_state_changed.emit())
	adventure.node_entered.connect(func(nid): EventBus.adventure_node.emit(nid))
	adventure.battle_won.connect(_on_battle_won)
	adventure.skill_learned.connect(func(skill, lesson): EventBus.skill_learned.emit(skill, lesson))
	adventure.adventure_won.connect(_on_adventure_won)


# --- lifecycle -------------------------------------------------------------------

func new_journey(difficulty_id: String, skip_basics: bool) -> void:
	var p := PlayerProfile.new()
	p.settings = profile.settings.duplicate() if profile != null else p.settings
	p.difficulty = difficulty_id
	p.started = true
	SaveManager.clear_world(CAMPAIGN_SLOT)
	_load_profile(p)
	mode = "campaign"
	var first: String = library.order[0]
	if skip_basics:
		var skip_to: String = JsonLoader.load_dict("res://data/difficulty.json").get("skip_basics_to", first)
		for cid in library.order:
			if cid == skip_to:
				break
			profile.skipped.append(cid)
			profile.unlock_commands(library.get_challenge(cid).unlocks)
		first = skip_to
	_boot_for(library.get_challenge(first))
	start_challenge(first)
	save_now()


func continue_journey() -> void:
	_load_profile(SaveManager.load_profile())
	mode = "campaign"
	var cid := profile.current_challenge
	if cid == "" or library.get_challenge(cid) == null:
		cid = library.first_incomplete(profile.completed)
	if cid == "":
		cid = library.order[-1]
	var world := SaveManager.load_world(CAMPAIGN_SLOT)
	var resume: bool = not world.is_empty() and world.get("challenge", "") == cid
	if resume:
		_restore_world(world)
	else:
		_boot_for(library.get_challenge(cid))
	start_challenge(cid, resume)


func start_practice() -> void:
	mode = "practice"
	challenges.current = null
	var world := SaveManager.load_world(PRACTICE_SLOT)
	if world.is_empty():
		_boot(PRACTICE_MACHINE)
	else:
		_restore_world(world)
	EventBus.session_changed.emit()


## Prepares Adventure (skill-worlds) mode for the 2D overworld. Returns true
## when a saved journey was resumed. The World2D scene drives everything.
func start_adventure2d() -> bool:
	mode = "adventure"
	challenges.current = null
	var world := AdventureWorld.load_default()
	for problem in world.validate():
		push_warning("adventure world: %s" % problem)
	var saved := SaveManager.load_world(ADVENTURE_SLOT)
	var state: AdventureState
	var resumed := false
	if not saved.is_empty() and saved.has("adv_state"):
		_restore_world(saved)
		state = AdventureState.from_dict(saved.adv_state)
		resumed = true
	else:
		_boot(world.machine)
		state = AdventureState.new()
	adventure.prepare(world, state, session)
	EventBus.adventure_started.emit()
	EventBus.session_changed.emit()
	return resumed


func start_challenge(challenge_id: String, resume: bool = false) -> void:
	var c := library.get_challenge(challenge_id)
	if c == null:
		push_error("Unknown challenge %s" % challenge_id)
		return
	if not resume and (session == null or (c.machine != "" and c.machine != _machine_id) or c.fresh_machine):
		_boot_for(c)
	challenges.begin(c, session, resume)
	EventBus.session_changed.emit()


func advance() -> void:
	var next_id := library.next_after(challenges.current.id) if challenges.current != null else ""
	if next_id == "":
		challenges.current = null
		profile.current_challenge = ""
		EventBus.campaign_finished.emit()
		save_now()
		return
	start_challenge(next_id)
	save_now()


func skip_current() -> void:
	if challenges.current == null:
		return
	var c := challenges.current
	if not profile.skipped.has(c.id) and not profile.completed.has(c.id):
		profile.skipped.append(c.id)
	profile.unlock_commands(c.unlocks)
	EventBus.narrate.emit("Skipped \"%s\". You can replay it later from the journey map." % c.title, "tip")
	challenges.completed_pending_next = true
	advance()


func _boot_for(c: Challenge) -> void:
	var machine_id := c.machine if c != null and c.machine != "" else "workstation"
	_boot(machine_id)


func _boot(machine_id: String) -> void:
	_machine_id = machine_id
	var m := MachineBuilder.load_machine(machine_id, registry.primary_names())
	session = ShellSession.new(m, PLAYER)
	shell = Shell.new(session, registry)
	_session_started_msec = Time.get_ticks_msec()


func _restore_world(world: Dictionary) -> void:
	_machine_id = world.get("machine_id", "workstation")
	var m := Machine.from_dict(world.get("machine", {}))
	session = ShellSession.new(m, PLAYER)
	session.cwd = world.get("cwd", session.home())
	session.env["PWD"] = session.cwd
	session.history = world.get("history", [])
	shell = Shell.new(session, registry)
	_session_started_msec = Time.get_ticks_msec()


# --- input -------------------------------------------------------------------------

## The single entry point for everything typed at the prompt.
func submit(line: String) -> void:
	var trimmed := line.strip_edges()
	if trimmed.begins_with(":"):
		var meta_outcome := meta.run(trimmed)
		EventBus.command_output.emit(meta_outcome)
		return
	if trimmed == "" and challenges.completed_pending_next and mode == "campaign":
		advance()
		return

	var user_before := session.user
	var machine_before := session.machine
	var outcome := shell.run_line(line)
	EventBus.command_output.emit(outcome)
	progression.record_outcome(outcome)
	achievements.check_outcome(outcome)
	if mode == "campaign":
		challenges.observe(outcome)
	elif mode == "adventure":
		adventure.observe(outcome)
	if user_before != session.user or machine_before != session.machine or outcome.has_event("cwd_changed") or outcome.has_event("root_shell") or outcome.has_event("adv_move"):
		EventBus.session_changed.emit()
	_lines_since_save += 1
	if _lines_since_save >= AUTOSAVE_EVERY_LINES:
		save_now()
	for e in outcome.events:
		if e.name == "open_editor":
			EventBus.editor_requested.emit(e.data)
			break
		elif e.name == "open_pager":
			EventBus.viewer_requested.emit({"mode": "page", "title": e.data.get("title", ""), "content": e.data.get("content", "")})
			break
		elif e.name == "open_follow":
			EventBus.viewer_requested.emit({"mode": "follow", "title": e.data.get("title", ""), "content": e.data.get("content", ""), "kind": e.data.get("kind", "sys")})
			break


## Called by the editor overlay when the player saves (^O or save-on-exit).
## Writes the buffer through the live session, then re-grades, so finishing a
## "fix this file" challenge in the editor completes it just like a command.
## Returns {ok, lines} or {ok=false, error} for the editor's status line.
func apply_edit(path: String, content: String) -> Dictionary:
	if session == null:
		return {"ok": false, "error": "no session"}
	var abs := session.resolve(path)
	var res := session.machine.vfs.write_file(abs, content, session.access(), false)
	if not res.ok:
		return {"ok": false, "error": res.error}
	var outcome := ExecutionOutcome.new()
	outcome.line = "nano %s" % path
	outcome.emit("file_edited", {"path": abs})
	if mode == "campaign":
		challenges.observe(outcome)
	elif mode == "adventure":
		adventure.observe(outcome)
	achievements.check_outcome(outcome)
	EventBus.session_changed.emit()
	_lines_since_save += 1
	if _lines_since_save >= AUTOSAVE_EVERY_LINES:
		save_now()
	var trimmed := content.trim_suffix("\n")
	var lines := 0 if content == "" else trimmed.split("\n").size()
	return {"ok": true, "lines": lines}


func replay_briefing() -> void:
	if challenges.current != null:
		_on_challenge_started(challenges.current)


func on_machine_reset() -> void:
	session = challenges._session
	shell.session = session
	profile.bump("resets")
	achievements.check_event("challenge_reset")
	EventBus.session_changed.emit()


func set_difficulty(difficulty_id: String) -> void:
	profile.difficulty = difficulty_id
	difficulty = DifficultySettings.load_id(difficulty_id)
	challenges.difficulty = difficulty
	save_now()


func save_now() -> void:
	if profile == null:
		return
	_lines_since_save = 0
	if _session_started_msec > 0:
		profile.bump("play_seconds", int((Time.get_ticks_msec() - _session_started_msec) / 1000))
		_session_started_msec = Time.get_ticks_msec()
	var worlds := {}
	if session != null and mode != "":
		var slot := PRACTICE_SLOT
		if mode == "campaign":
			slot = CAMPAIGN_SLOT
		elif mode == "adventure":
			slot = ADVENTURE_SLOT
		# While ssh'd into a remote host, record the local (login) machine, not
		# the remote — a reload should drop you back home, not onto the server.
		var world_data := {
			"machine_id": _machine_id,
			"machine": session.base_machine().to_dict(),
			"cwd": session.base_cwd(),
			"history": session.history.slice(-100),
			"challenge": challenges.current.id if challenges.current != null else "",
		}
		if mode == "adventure":
			world_data["adv_state"] = adventure.state.to_dict()
		worlds[slot] = world_data
	SaveManager.save(profile, worlds)


func reset_progress() -> void:
	var settings := profile.settings.duplicate()
	SaveManager.delete_save()
	var p := PlayerProfile.new()
	p.settings = settings
	_load_profile(p)
	session = null
	mode = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and mode != "":
		save_now()


# --- signal handlers ----------------------------------------------------------------

func _on_challenge_started(c: Challenge) -> void:
	EventBus.challenge_started.emit(c)


## Order matters for the player: "objective complete" first, then new
## commands, then any rank-up earned by that XP.
func _on_challenge_completed(c: Challenge, result: Dictionary) -> void:
	_completing = true
	var granted := progression.record_completion(c, result)
	result["granted"] = granted
	_completing = false
	EventBus.challenge_completed.emit(c, result)
	if not result.get("new_commands", []).is_empty():
		EventBus.commands_unlocked.emit(result.new_commands)
	if not _deferred_rank.is_empty():
		var rank := _deferred_rank
		_deferred_rank = {}
		_on_rank_up(rank)
	achievements.check_challenge(c.id)
	save_now()


func _on_hint_revealed(_c: Challenge, index: int, text: String) -> void:
	profile.bump("hints_used")
	EventBus.hint_revealed.emit(index, text)


func _on_battle_won(node_id: String, reward: Dictionary) -> void:
	# A trial is passed once (the manager guards re-entry), so its XP is awarded
	# once here, feeding the same rank ladder as the campaign.
	if int(reward.get("xp", 0)) > 0:
		progression.award(int(reward.xp))
	achievements.check_event("battle_won", {"node": node_id})
	save_now()


func _on_adventure_won() -> void:
	achievements.check_event("adventure_won")
	EventBus.adventure_won.emit()
	SaveManager.clear_world(ADVENTURE_SLOT)
	profile.bump("adventures_won")
	save_now()


func _on_rank_up(rank: Dictionary) -> void:
	if _completing:
		_deferred_rank = rank
		return
	achievements.check_rank(rank.name)
	EventBus.rank_up.emit(rank)
