class_name AdventureManager
extends RefCounted
## Adventure logic: collect skill orbs to learn commands, then pass each world's
## trial by solving a real problem with those skills. No health, no combat —
## just learn, apply, advance. Trials reuse ConditionEvaluator, so every valid
## solution wins, exactly like the campaign.

signal narrate(text: String, kind: String)
signal state_changed()
signal node_entered(world_id: String)          # a world was entered (kept name for wiring)
signal battle_won(world_id: String, reward: Dictionary)  # a trial was passed
signal skill_learned(skill: String, lesson: Dictionary)
signal adventure_won()

var world: AdventureWorld
var state: AdventureState
## func(machine_id) -> Machine (kept for parity with the campaign; unused here).
var machine_factory: Callable

var _session: ShellSession
var _log_start: int = 0
var _events: Array = []
var _hints_shown: int = 0
var _fired_reactions: Dictionary = {}
var _in_trial: bool = false
var _won: bool = false


## Set up refs without narrating; the 2D world drives everything.
func prepare(p_world: AdventureWorld, p_state: AdventureState, session: ShellSession) -> void:
	world = p_world
	state = p_state
	_session = session
	_session.adventure = self
	state.world_index = clampi(state.world_index, 0, maxi(0, world.count() - 1))


func is_active() -> bool:
	return not _won


func current_index() -> int:
	return state.world_index


func current_world() -> Dictionary:
	return world.world_at(state.world_index)


# --- worlds -----------------------------------------------------------------

## Move focus to a world (sets the index; the 2D scene builds the room).
func enter_world(index: int) -> void:
	state.world_index = clampi(index, 0, world.count() - 1)
	_in_trial = false
	node_entered.emit(str(current_world().get("id", "")))
	state_changed.emit()


func orbs_total(index: int) -> int:
	return world.orbs(index).size()


func orbs_collected_count(index: int) -> int:
	return state.collected_in(str(world.world_at(index).get("id", ""))).size()


func all_orbs_collected(index: int) -> bool:
	return orbs_collected_count(index) >= orbs_total(index)


## Reach an orb: learn its skill. Returns the lesson dict for the 2D card and
## or {} if it was already collected.
func collect_orb(index: int, orb_index: int) -> Dictionary:
	var orbs: Array = world.orbs(index)
	if orb_index < 0 or orb_index >= orbs.size():
		return {}
	var orb: Dictionary = orbs[orb_index]
	var world_id := str(world.world_at(index).get("id", ""))
	var skill := str(orb.get("skill", ""))
	if not state.learn_skill(world_id, skill):
		return {}
	# Some orbs grant a real capability, not just knowledge (the sudo orb makes
	# you a sudoer — the game's version of earning the right to become root).
	if orb.has("grant_group"):
		_grant_group(str(orb.grant_group))
	skill_learned.emit(skill, orb)
	state_changed.emit()
	return orb


func _grant_group(group: String) -> void:
	var users: Dictionary = _session.machine.users
	var me: String = _session.user_stack[0].user if not _session.user_stack.is_empty() else _session.user
	if users.has(me) and not users[me].get("groups", []).has(group):
		users[me]["groups"].append(group)


func can_engage_trial(index: int) -> bool:
	return all_orbs_collected(index) and not is_passed(index)


func is_passed(index: int) -> bool:
	return state.is_passed(str(world.world_at(index).get("id", "")))


# --- the trial --------------------------------------------------------------

## Open a world's trial: apply its setup fresh (a clean attempt every time),
## drop any leftover elevation, and put the shell in the world's directory.
func engage_trial(index: int) -> void:
	state.world_index = index
	while _session.pop_user():
		pass
	var wd: Dictionary = world.world_at(index)
	var trial: Dictionary = wd.get("trial", {})
	_apply_setup(trial.get("setup", {}))
	if wd.has("cwd"):
		_session.set_cwd(ConditionEvaluator._path(wd.cwd, _session))
	_events.clear()
	_fired_reactions.clear()
	_hints_shown = 0
	_log_start = _session.command_log.size()
	_in_trial = not is_passed(index)
	narrate.emit(I18n.t("── TRIAL — %s ──") % str(trial.get("name", wd.get("name", ""))).to_upper(), "rule")
	if is_passed(index):
		narrate.emit(I18n.t("You've already passed this trial. The console idles quietly."), "dim")
	else:
		narrate.emit(I18n.t("OBJECTIVE") + "  " + str(trial.get("objective", "")), "objective")
		narrate.emit(I18n.t("Skills in your kit:") + " " + "  ".join(PackedStringArray(state.skills)), "tip")
		narrate.emit(I18n.t("(type `hint` if you're stuck, or Esc to step back)"), "dim")
	state_changed.emit()


## Lay a world's files and processes out so an orb's example command actually
## has something to work on, WITHOUT opening the trial: no objective, no success
## check, nothing graded. Used by the prompt you get when you take an orb.
func prepare_practice(index: int) -> void:
	state.world_index = index
	var wd: Dictionary = world.world_at(index)
	_apply_setup(wd.get("trial", {}).get("setup", {}))
	if wd.has("cwd"):
		_session.set_cwd(ConditionEvaluator._path(wd.cwd, _session))
	_in_trial = false


func disengage() -> void:
	_in_trial = false
	while _session.pop_user():
		pass


func in_trial() -> bool:
	return _in_trial


func observe(outcome: ExecutionOutcome) -> void:
	if _won:
		return
	_events.append_array(outcome.events)
	for e in outcome.events:
		match e.name:
			"adv_hint": _handle_hint()
			"adv_look": _handle_look()
			"adv_move": narrate.emit(I18n.t("Just run and jump — A/D or the arrows, Space to jump. Consoles and portals take E."), "dim")
	if _won or not _in_trial:
		return
	var trial: Dictionary = current_world().get("trial", {})
	if ConditionEvaluator.evaluate(trial.get("success", {}), _state_dict()):
		_pass_trial()
	else:
		_check_reactions(trial)


func _state_dict() -> Dictionary:
	return {"session": _session, "log_start": _log_start, "events": _events, "last_records": []}


## Fire-once teaching nudges. A reaction carrying a `respawn` process repeats
## (it must re-fire every time the player kills the thing that respawns).
func _check_reactions(trial: Dictionary) -> void:
	var reactions: Array = trial.get("reactions", [])
	for i in reactions.size():
		var r: Dictionary = reactions[i]
		var repeatable: bool = r.has("respawn")
		if _fired_reactions.has(i) and not repeatable:
			continue
		if ConditionEvaluator.evaluate(r.get("when", {}), _state_dict()):
			_fired_reactions[i] = true
			narrate.emit("", "story")
			narrate.emit("» " + str(r.get("say", "")), r.get("kind", "tip"))
			if r.has("respawn"):
				var proc: Dictionary = (r.respawn as Dictionary).duplicate()
				if _session.machine.find_process(int(proc.get("pid", -1))).is_empty():
					_session.machine.next_pid = maxi(_session.machine.next_pid, int(proc.get("pid", 0)))
					_session.machine.processes.append(proc)


func _pass_trial() -> void:
	var index := state.world_index
	var wd: Dictionary = world.world_at(index)
	var world_id := str(wd.get("id", ""))
	state.mark_passed(world_id)
	_in_trial = false
	var trial: Dictionary = wd.get("trial", {})
	narrate.emit("", "story")
	narrate.emit(I18n.t("✔ TRIAL PASSED — %s") % wd.get("name", ""), "success")
	narrate.emit("", "story")
	narrate.emit(I18n.t("WHAT YOU LEARNED"), "header")
	for line in trial.get("learned", []):
		narrate.emit("  " + str(line), "story")
	var reward := {"xp": int(trial.get("xp", 80 + index * 25))}
	battle_won.emit(world_id, reward)
	state_changed.emit()
	if world.is_final(index):
		_win()
	else:
		narrate.emit("", "story")
		narrate.emit(I18n.t("The portal ahead hums awake. Step through it to the next world."), "tip")


func _win() -> void:
	_won = true
	adventure_won.emit()


## Walk through an opened portal to the next world.
func advance() -> bool:
	var index := state.world_index
	if not is_passed(index):
		return false
	if world.is_final(index):
		if not _won:
			_win()
		return true
	enter_world(index + 1)
	return true


# --- setup (same shape as challenge setup) ----------------------------------

func _apply_setup(setup: Dictionary) -> void:
	if setup.is_empty():
		return
	var m := _session.machine
	var files: Dictionary = {}
	for p in setup.get("files", {}):
		files[ConditionEvaluator._path(p, _session)] = setup.files[p]
	MachineBuilder.apply_files(m.vfs, files)
	for p in setup.get("remove", []):
		m.vfs.remove(ConditionEvaluator._path(p, _session), null, true)
	for proc in setup.get("processes", []):
		var pr: Dictionary = proc.duplicate()
		if not m.find_process(int(pr.get("pid", -1))).is_empty():
			continue
		pr["pid"] = int(pr.get("pid", m.next_pid + 1))
		m.next_pid = maxi(m.next_pid, pr.pid)
		m.processes.append(pr)
	# Later worlds need machine state beyond files and processes — a stalled
	# service, a package database, a network to probe or a host to ssh into.
	# The shapes match the campaign's challenge setup (and machine definitions).
	if setup.has("services"):
		MachineBuilder.apply_services(m, setup.services)
	if setup.has("packages"):
		MachineBuilder.apply_packages(m, setup.packages)
	if setup.has("net"):
		MachineBuilder._build_net(m, setup.net)


# --- hints & verbs ----------------------------------------------------------

func _handle_hint() -> void:
	if not _in_trial:
		narrate.emit(I18n.t("Nothing to solve at this prompt — try the command out. The trial waits at the console, once you have every orb."), "dim")
		return
	if reveal_hint() == "":
		narrate.emit(I18n.t("No more hints — trust what you've learned. `talk <command>` teaches any tool."), "dim")


func _handle_look() -> void:
	var wd := current_world()
	narrate.emit("── %s ──" % str(wd.get("name", "")).to_upper(), "rule")
	for line in wd.get("intro", []):
		narrate.emit(str(line), "story")


func reveal_hint() -> String:
	if not _in_trial:
		return ""
	var hints: Array = current_world().get("trial", {}).get("hints", [])
	if _hints_shown >= hints.size():
		return ""
	var text: String = hints[_hints_shown]
	_hints_shown += 1
	narrate.emit("", "story")
	narrate.emit(I18n.t("HINT %d/%d  %s") % [_hints_shown, hints.size(), text], "warn")
	return text


func hints_shown() -> int:
	return _hints_shown


# --- read-only text for the `status` / `map` verbs --------------------------

func status_text() -> String:
	var wd := current_world()
	var idx := state.world_index
	var out := "%s\n" % wd.get("name", "?")
	out += I18n.t("Skills learned: %s") % ("—" if state.skills.is_empty() else "  ".join(PackedStringArray(state.skills))) + "\n"
	out += I18n.t("This world: %d/%d orbs collected") % [orbs_collected_count(idx), orbs_total(idx)]
	if is_passed(idx):
		out += I18n.t("  ·  trial PASSED")
	elif all_orbs_collected(idx):
		out += I18n.t("  ·  trial ready (use the console)")
	out += "\n"
	return out


func map_text() -> String:
	var out := I18n.t("THE ASCENT — %d worlds") % world.count() + "\n\n"
	for i in world.count():
		var marker := "●" if i == state.world_index else ("✔" if is_passed(i) else ("·" if i < state.world_index else "○"))
		var name := world.world_name(i) if (i <= state.world_index or is_passed(i)) else "???"
		out += "  %s %s\n" % [marker, name]
	out += "\n  " + I18n.t("● here   ✔ passed   ○ ahead") + "\n"
	return out
