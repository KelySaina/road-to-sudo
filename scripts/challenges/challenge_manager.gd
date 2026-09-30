class_name ChallengeManager
extends RefCounted
## Runs the active challenge: applies setup, watches every executed line,
## hands out hints, fires reactions, and decides when the objective is met.
## Knows nothing about UI; talks through signals.

signal challenge_started(challenge: Challenge)
signal challenge_completed(challenge: Challenge, result: Dictionary)
signal hint_revealed(challenge: Challenge, index: int, text: String)
## Narrative text for the terminal. kind: "story", "tip", "reaction", "warning", "success"
signal narrate(text: String, kind: String)

var library: ChallengeLibrary
var profile: PlayerProfile
## func(machine_id: String) -> Machine. Builds a pristine machine for :reset
## after a resumed session (when no in-memory snapshot exists).
var machine_factory: Callable
var difficulty: DifficultySettings
var current: Challenge = null
var completed_pending_next: bool = false

var _session: ShellSession
var _log_start: int = 0
var _events: Array = []
var _fired_reactions: Dictionary = {}
var _hints_shown: int = 0
var _solution_shown: bool = false
var _started_msec: int = 0
var _commands_this_attempt: int = 0
var _snapshot: Dictionary = {}
var _snapshot_cwd: String = ""


func _init(p_library: ChallengeLibrary, p_profile: PlayerProfile, p_difficulty: DifficultySettings) -> void:
	library = p_library
	profile = p_profile
	difficulty = p_difficulty


func is_active() -> bool:
	return current != null and not completed_pending_next


## Prepares the session for a challenge. The caller (Game) has already
## booted the right machine; setup mutates it. `resume` skips the setup so
## a saved, half-finished attempt continues exactly where it was.
func begin(challenge: Challenge, session: ShellSession, resume: bool = false) -> void:
	current = challenge
	completed_pending_next = false
	_session = session
	_events = []
	_fired_reactions = {}
	_hints_shown = int(profile.hints_used.get(challenge.id, 0))
	_solution_shown = profile.solutions_seen.has(challenge.id)
	_started_msec = Time.get_ticks_msec()
	_commands_this_attempt = 0
	_log_start = session.command_log.size()
	if resume:
		_snapshot = {}
	else:
		_apply_setup(challenge.setup, session)
		_snapshot = session.machine.to_dict()
		_snapshot_cwd = session.cwd
	profile.current_challenge = challenge.id
	challenge_started.emit(challenge)


func _apply_setup(setup: Dictionary, session: ShellSession) -> void:
	var m := session.machine
	if setup.has("restore"):
		_restore_pristine(setup.restore, session)
	var files: Dictionary = {}
	var raw_files: Dictionary = setup.get("files", {})
	for p in raw_files:
		files[ConditionEvaluator._path(p, session)] = raw_files[p]
	MachineBuilder.apply_files(m.vfs, files)
	for p in setup.get("remove", []):
		m.vfs.remove(ConditionEvaluator._path(p, session), null, true)
	for proc in setup.get("processes", []):
		var pr: Dictionary = proc.duplicate()
		if not m.find_process(int(pr.get("pid", -1))).is_empty():
			continue
		pr["pid"] = int(pr.get("pid", m.next_pid + 1))
		m.next_pid = maxi(m.next_pid, pr.pid)
		m.processes.append(pr)
	if setup.has("services"):
		MachineBuilder.apply_services(m, setup.services)
	if setup.has("packages"):
		MachineBuilder.apply_packages(m, setup.packages)
	if setup.has("cwd"):
		session.set_cwd(ConditionEvaluator._path(setup.cwd, session))


## Copies paths from the machine's original definition, so a challenge still
## works if the player deleted or broke something earlier.
func _restore_pristine(paths: Array, session: ShellSession) -> void:
	var machine_id := current.machine if current.machine != "" else "workstation"
	var pristine := MachineBuilder.load_machine(machine_id)
	for p in paths:
		var abs_path := ConditionEvaluator._path(p, session)
		var node := pristine.vfs.get_node_at(abs_path)
		if node == null:
			continue
		var parent := session.machine.vfs.ensure_dir(PathUtils.dirname(abs_path))
		parent.children[node.name] = node.deep_copy()


## Called by Game after every submitted line.
func observe(outcome: ExecutionOutcome) -> void:
	if not is_active():
		return
	_commands_this_attempt += 1
	_events.append_array(outcome.events)
	_check_protected(outcome)
	var state := _state(outcome)
	_run_reactions(state)
	if ConditionEvaluator.evaluate(current.success, state):
		_complete()


func _state(outcome: ExecutionOutcome = null) -> Dictionary:
	return {
		"session": _session,
		"log_start": _log_start,
		"events": _events,
		"last_records": outcome.records if outcome != null else [],
	}


func _check_protected(outcome: ExecutionOutcome) -> void:
	for e in outcome.events:
		if e.name != "file_deleted":
			continue
		for p in current.protected_paths:
			var protected_abs := ConditionEvaluator._path(p, _session)
			if e.data.path == protected_abs or protected_abs.begins_with(str(e.data.path) + "/"):
				narrate.emit("%s was deleted.\n\n...\n\nWait.\n\nWas that intentional?" % PathUtils.basename(protected_abs), "warning")
				narrate.emit("There is no recycle bin in a terminal. Real servers won't forgive this —\nhere, `:reset` rewinds the machine to the start of the challenge.", "tip")
				_events.append({"name": "protected_deleted", "data": {"path": protected_abs}})
				outcome.emit("protected_deleted", {"path": protected_abs})


func _run_reactions(state: Dictionary) -> void:
	for i in current.reactions.size():
		var r: Dictionary = current.reactions[i]
		if _fired_reactions.has(i):
			continue
		var only: Array = r.get("difficulty", [])
		if not only.is_empty() and not only.has(difficulty.id):
			continue
		if ConditionEvaluator.evaluate(r.get("when", {}), state):
			_fired_reactions[i] = true
			narrate.emit(r.get("say", ""), r.get("kind", "reaction"))


func _complete() -> void:
	completed_pending_next = true
	var elapsed := (Time.get_ticks_msec() - _started_msec) / 1000.0
	var result := Progression.score_challenge(current, _hints_shown, _solution_shown, difficulty, elapsed)
	result["first_time"] = not profile.completed.has(current.id)
	result["elapsed"] = elapsed
	result["commands"] = _commands_this_attempt
	result["next"] = library.next_after(current.id)
	challenge_completed.emit(current, result)


# --- player-requested help -------------------------------------------------------

func hints_available() -> int:
	if current == null:
		return 0
	return mini(current.hints.size(), difficulty.max_hints)


func hints_shown() -> int:
	return _hints_shown


func request_hint() -> String:
	if current == null:
		return ""
	if _hints_shown >= hints_available():
		return ""
	var text: String = current.hints[_hints_shown]
	_hints_shown += 1
	profile.hints_used[current.id] = _hints_shown
	hint_revealed.emit(current, _hints_shown, text)
	return text


func can_reveal_solution() -> bool:
	return current != null and difficulty.allow_solution and _hints_shown >= hints_available()


func reveal_solution() -> String:
	if not can_reveal_solution():
		return ""
	_solution_shown = true
	if not profile.solutions_seen.has(current.id):
		profile.solutions_seen.append(current.id)
	return current.solution


## Restores the machine as it was when the challenge began. After a resumed
## session there is no snapshot: rebuild the pristine machine and re-run setup.
func reset() -> bool:
	if current == null:
		return false
	if _snapshot.is_empty():
		if not machine_factory.is_valid():
			return false
		_session.machine = machine_factory.call(current.machine if current.machine != "" else "workstation")
		_session.user_stack.clear()
		_session.cwd = _session.home()
		_apply_setup(current.setup, _session)
		_snapshot = _session.machine.to_dict()
		_snapshot_cwd = _session.cwd
		_session.env["PWD"] = _session.cwd
		_events.append({"name": "challenge_reset", "data": {}})
		return true
	var restored := Machine.from_dict(_snapshot.duplicate(true))
	_session.machine = restored
	_session.cwd = _snapshot_cwd
	_session.env["PWD"] = _snapshot_cwd
	_session.user_stack.clear()
	_events.append({"name": "challenge_reset", "data": {}})
	return true


func shown_hint_texts() -> Array:
	if current == null:
		return []
	return current.hints.slice(0, _hints_shown)


func elapsed_seconds() -> float:
	return (Time.get_ticks_msec() - _started_msec) / 1000.0
