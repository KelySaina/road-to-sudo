class_name AdventureManager
extends RefCounted
## Runs the RPG layer: exploration, dialogue and combat, all driven from the
## terminal. Enemies and bosses are Linux problems; you defeat them by
## solving them. Wrong or reckless actions cost HP. It reuses
## ConditionEvaluator so every valid solution wins, exactly like the campaign.

signal narrate(text: String, kind: String)
signal state_changed()
signal node_entered(node_id: String)
signal battle_won(node_id: String, reward: Dictionary)
signal player_damaged(amount: int, hp: int)
signal player_rebooted()
signal adventure_won()

var world: AdventureWorld
var state: AdventureState
## func(machine_id) -> Machine, so a reboot can rebuild a pristine server.
var machine_factory: Callable

var _session: ShellSession
var _log_start: int = 0
var _events: Array = []
var _fired_traps: Dictionary = {}
var _snapshot: Dictionary = {}
var _snapshot_cwd: String = ""
var _in_battle: bool = false
var _hints_shown: int = 0
var _setup_done: Dictionary = {}
var _fired_reactions: Dictionary = {}
var _won: bool = false


func begin(p_world: AdventureWorld, p_state: AdventureState, session: ShellSession) -> void:
	world = p_world
	state = p_state
	_session = session
	_session.adventure = self
	if state.current == "" or not world.has_node(state.current):
		state.current = world.start
	_enter(state.current, not state.visited.has(state.current), true)


func is_active() -> bool:
	return not _won


# --- 2D world API (physical map; walking replaces the `go` verb) -------------

## Prepare state without entering/narrating; the 2D world drives engagement.
func prepare(p_world: AdventureWorld, p_state: AdventureState, session: ShellSession) -> void:
	world = p_world
	state = p_state
	_session = session
	_session.adventure = self
	if state.current == "" or not world.has_node(state.current):
		state.current = world.start


## Walk up to a console and start (or resume) its fight. Setup is applied once
## per node so leaving and returning never wipes partial progress.
func engage(node_id: String) -> void:
	while _session.pop_user():
		pass
	state.current = node_id
	state.visited[node_id] = true
	var node := world.node(node_id)
	if not _setup_done.has(node_id):
		_setup_done[node_id] = true
		_apply_setup(node.get("battle", {}).get("setup", {}))
		if node.has("cwd"):
			_session.set_cwd(ConditionEvaluator._path(node.cwd, _session))
	_fired_traps.clear()
	_fired_reactions.clear()
	_events.clear()
	_hints_shown = 0
	_log_start = _session.command_log.size()
	_snapshot = _session.machine.to_dict()
	_snapshot_cwd = _session.cwd
	_in_battle = world.is_battle(node_id) and not state.is_cleared(node_id)
	_narrate_battle_intro(node)
	node_entered.emit(node_id)
	state_changed.emit()


func disengage() -> void:
	_in_battle = false
	# Stepping away from a console must not leave you elevated: unwind any
	# `su` / `sudo -i` back to the base account so walking is always as player.
	while _session.pop_user():
		pass


func _narrate_battle_intro(node: Dictionary) -> void:
	narrate.emit("── %s ──" % str(node.get("name", "?")).to_upper(), "rule")
	if not _in_battle:
		narrate.emit("You have already dealt with this. The console idles quietly.", "dim")
		return
	var enemy: Dictionary = node.get("enemy", {})
	if not enemy.is_empty():
		narrate.emit("» %s stirs." % enemy.get("name", "An enemy"), "warning")
		for t in enemy.get("taunt", []):
			narrate.emit("  \"%s\"" % t, "reaction")
	narrate.emit("", "story")
	narrate.emit("OBJECTIVE  " + str(node.get("battle", {}).get("objective", "")), "objective")
	narrate.emit("(type `hint` for help, `status` for your health, or Esc to step back)", "dim")


## Talk to the character at a node: applies its story gate (grants), returns
## the dialogue lines for the 2D dialogue box.
func visit_npc(node_id: String) -> Dictionary:
	state.visited[node_id] = true
	state.current = node_id
	var node := world.node(node_id)
	var lines: Array = []
	var grant: Dictionary = node.get("on_enter_grant", {})
	var granted := false
	if not grant.is_empty():
		granted = true
		for needed in grant.get("needs", []):
			if not state.has_flag(needed):
				granted = false
		if granted:
			var newly := false
			for flag in grant.get("flags", []):
				if not state.has_flag(flag):
					state.add_flag(flag); newly = true
			if grant.has("grant_group"):
				_grant_group(str(grant.grant_group))
			if newly or grant.has("grant_group"):
				lines.append_array(grant.get("say", []))
	var npc: Dictionary = node.get("npc", {})
	if lines.is_empty():
		lines.append_array(npc.get("lines", []))
	state_changed.emit()
	return {"name": npc.get("name", "?"), "lines": lines, "granted": granted}



# --- entering a node --------------------------------------------------------

func _enter(node_id: String, first_visit: bool, silent_intro: bool = false) -> void:
	state.current = node_id
	state.visited[node_id] = true
	var node := world.node(node_id)
	_fired_traps.clear()
	_events.clear()
	_apply_setup(node.get("battle", {}).get("setup", {}))
	if node.has("cwd"):
		_session.set_cwd(ConditionEvaluator._path(node.cwd, _session))
	_log_start = _session.command_log.size()
	_snapshot = _session.machine.to_dict()
	_snapshot_cwd = _session.cwd
	_in_battle = world.is_battle(node_id) and not state.is_cleared(node_id)
	_hints_shown = 0
	_apply_grant(node.get("on_enter_grant", {}), silent_intro)

	if not silent_intro:
		_narrate_node(node, first_visit)
	node_entered.emit(node_id)
	state_changed.emit()


## Story gate: hands out a flag / group the first time the player arrives with
## the required keys (e.g. the Gatekeeper who grants sudo).
func _apply_grant(grant: Dictionary, silent: bool) -> void:
	if grant.is_empty():
		return
	for needed in grant.get("needs", []):
		if not state.has_flag(needed):
			return
	var newly: Array = []
	for flag in grant.get("flags", []):
		if not state.has_flag(flag):
			state.add_flag(flag)
			newly.append(flag)
	if grant.has("grant_group"):
		_grant_group(str(grant.grant_group))
	if silent or newly.is_empty() and not grant.has("grant_group"):
		return
	for line in grant.get("say", []):
		narrate.emit(str(line), "success")
	if grant.has("grant_group"):
		narrate.emit("You now wield %s. The prompt will answer to you." % grant.grant_group, "reaction")


func _narrate_node(node: Dictionary, first_visit: bool) -> void:
	narrate.emit("", "story")
	narrate.emit("── %s ──" % str(node.get("name", "?")).to_upper(), "rule")
	for line in node.get("art", []):
		narrate.emit(str(line), "dim")
	var lines: Array = node.get("on_enter", []) if first_visit else node.get("on_return", node.get("on_enter", []))
	for line in lines:
		narrate.emit(str(line), "story")
	if world.is_battle(node.get("id", "")) and not state.is_cleared(node.get("id", "")):
		var battle: Dictionary = node.get("battle", {})
		var enemy: Dictionary = node.get("enemy", {})
		if not enemy.is_empty():
			narrate.emit("", "story")
			narrate.emit("» %s blocks your path." % enemy.get("name", "An enemy"), "warning")
			for t in enemy.get("taunt", []):
				narrate.emit("  \"%s\"" % t, "reaction")
		narrate.emit("", "story")
		narrate.emit("OBJECTIVE  " + str(battle.get("objective", "Deal with it.")), "objective")
		narrate.emit("(type `hint` for help, `look` to survey, `status` for your health)", "dim")
	else:
		_narrate_exits(node)


func _narrate_exits(node: Dictionary) -> void:
	var ex: Dictionary = node.get("exits", {})
	if ex.is_empty():
		return
	var parts: Array = []
	for dir in ex:
		parts.append("%s → %s" % [dir, world.node_name(ex[dir])])
	narrate.emit("Paths from here:  " + "   ".join(PackedStringArray(parts)), "tip")
	narrate.emit("Travel with:  go <direction>", "dim")


func _apply_setup(setup: Dictionary) -> void:
	if setup.is_empty():
		return
	var m := _session.machine
	if setup.has("restore"):
		_restore_pristine(setup.restore)
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


func _restore_pristine(paths: Array) -> void:
	if not machine_factory.is_valid():
		return
	var pristine: Machine = machine_factory.call(world.machine)
	for p in paths:
		var abs_path := ConditionEvaluator._path(p, _session)
		var src := pristine.vfs.get_node_at(abs_path)
		if src == null:
			continue
		_session.machine.vfs.ensure_dir(PathUtils.dirname(abs_path)).children[src.name] = src.deep_copy()


# --- observing commands -----------------------------------------------------

func observe(outcome: ExecutionOutcome) -> void:
	if _won:
		return
	_events.append_array(outcome.events)
	# Adventure verbs are handled here so their narration types out after the
	# command's own output has been printed.
	for e in outcome.events:
		match e.name:
			"adv_move": _handle_move(e.data.get("exit", ""))
			"adv_look": _handle_look()
			"adv_talk": _handle_talk(e.data.get("who", ""))
			"adv_hint": _handle_hint()
	if _won:
		return
	if _in_battle:
		_check_traps()
		if state.hp <= 0:
			return
		var node := world.node(state.current)
		if ConditionEvaluator.evaluate(node.get("battle", {}).get("success", {}), _state_dict()):
			_win_battle(node)
		else:
			_check_reactions(node)


func _state_dict() -> Dictionary:
	return {"session": _session, "log_start": _log_start, "events": _events, "last_records": []}


## Fire-once nudges that teach when the player is clearly stuck (looking around
## with the wrong tool). Defined per battle in world.json as `reactions`.
func _check_reactions(node: Dictionary) -> void:
	var reactions: Array = node.get("battle", {}).get("reactions", [])
	for i in reactions.size():
		if _fired_reactions.has(i):
			continue
		var r: Dictionary = reactions[i]
		if ConditionEvaluator.evaluate(r.get("when", {}), _state_dict()):
			_fired_reactions[i] = true
			narrate.emit("", "story")
			narrate.emit("» " + str(r.get("say", "")), r.get("kind", "tip"))


func _check_traps() -> void:
	var node := world.node(state.current)
	var traps: Array = node.get("battle", {}).get("traps", [])
	for i in traps.size():
		var trap: Dictionary = traps[i]
		if _fired_traps.has(i) and trap.get("once", true):
			continue
		if ConditionEvaluator.evaluate(trap.get("when", {}), _state_dict()):
			_fired_traps[i] = true
			var dmg := int(trap.get("damage", 5))
			state.damage(dmg)
			narrate.emit("", "story")
			narrate.emit("✗ %s  (−%d HP)" % [trap.get("say", "You take a hit."), dmg], "warning")
			if trap.has("respawn"):
				var proc: Dictionary = trap.respawn.duplicate()
				if _session.machine.find_process(int(proc.get("pid", -1))).is_empty():
					_session.machine.next_pid = maxi(_session.machine.next_pid, int(proc.get("pid", 0)))
					_session.machine.processes.append(proc)
			player_damaged.emit(dmg, state.hp)
			state_changed.emit()
			if state.hp <= 0:
				_reboot()
				return


func _reboot() -> void:
	state.deaths += 1
	narrate.emit("", "story")
	narrate.emit("*** KERNEL PANIC — not syncing ***", "err")
	narrate.emit("The machine reboots. You come to at the last checkpoint, shaken but whole.", "story")
	var base_user: String = _session.user_stack[0].user if not _session.user_stack.is_empty() else _session.user
	if not _snapshot.is_empty():
		_session.machine = Machine.from_dict(_snapshot.duplicate(true))
		_session.cwd = _snapshot_cwd
		_session.env["PWD"] = _snapshot_cwd
	_session.user_stack.clear()
	_session.user = base_user
	_session.env["HOME"] = _session.home()
	state.heal_full()
	_fired_traps.clear()
	_events.clear()
	_log_start = _session.command_log.size()
	player_rebooted.emit()
	state_changed.emit()


func _win_battle(node: Dictionary) -> void:
	var node_id: String = node.get("id", state.current)
	state.cleared[node_id] = true
	_in_battle = false
	var battle: Dictionary = node.get("battle", {})
	var enemy: Dictionary = node.get("enemy", {})
	narrate.emit("", "story")
	if not enemy.is_empty():
		narrate.emit("✔ %s is defeated." % enemy.get("name", "The enemy"), "success")
	for line in battle.get("victory", []):
		narrate.emit(str(line), "success")
	var reward := {"flags": [], "xp": 0}
	for flag in battle.get("reward_flags", []):
		state.add_flag(flag)
		reward.flags.append(flag)
	if battle.has("grant_group"):
		_grant_group(str(battle.grant_group))
		narrate.emit("You now wield %s." % battle.grant_group, "reaction")
	if not reward.flags.is_empty():
		narrate.emit("Gained: " + "  ".join(PackedStringArray(reward.flags)), "reaction")
	reward["xp"] = int(battle.get("reward_xp", 0))
	if battle.has("learned"):
		narrate.emit("", "story")
		narrate.emit("WHAT YOU LEARNED", "header")
		for line in battle.learned:
			narrate.emit("  " + str(line), "story")
	battle_won.emit(node_id, reward)
	state_changed.emit()
	if node.get("win", false):
		_win_adventure()


func _grant_group(group: String) -> void:
	var users: Dictionary = _session.machine.users
	var me: String = _session.user_stack[0].user if not _session.user_stack.is_empty() else _session.user
	if users.has(me) and not users[me].get("groups", []).has(group):
		users[me]["groups"].append(group)


func _win_adventure() -> void:
	_won = true
	adventure_won.emit()


# --- verbs (called from AdventureManager.observe via events) -----------------

func _handle_move(exit_arg: String) -> void:
	var node := world.node(state.current)
	if _in_battle and not node.get("open_exits_in_battle", false):
		var enemy_name: String = node.get("enemy", {}).get("name", "this")
		narrate.emit("You can't leave — %s stands in your way. Deal with it first." % enemy_name, "warning")
		return
	var ex: Dictionary = node.get("exits", {})
	var dest := _resolve_exit(exit_arg, ex)
	if dest == "":
		if exit_arg == "":
			_narrate_exits(node)
		else:
			narrate.emit("There is no way '%s' from here." % exit_arg, "warning")
			_narrate_exits(node)
		return
	var lock: Dictionary = node.get("locks", {}).get(_dir_of(dest, ex), {})
	for needed in lock.get("needs", []):
		if not state.has_flag(needed):
			for line in lock.get("blocked", ["The way is barred. You're not ready yet."]):
				narrate.emit(str(line), "warning")
			return
	_enter(dest, not state.visited.has(dest))


func _resolve_exit(arg: String, ex: Dictionary) -> String:
	if arg == "":
		return ""
	var low := arg.to_lower()
	if ex.has(low):
		return ex[low]
	for dir in ex:
		var dest: String = ex[dir]
		if dest.to_lower() == low or world.node_name(dest).to_lower() == low or world.node_name(dest).to_lower().contains(low):
			return dest
	return ""


func _dir_of(dest: String, ex: Dictionary) -> String:
	for dir in ex:
		if ex[dir] == dest:
			return dir
	return ""


func _handle_hint() -> void:
	if not _in_battle:
		narrate.emit("Nothing to puzzle out here. Try `look`, `talk`, or `map`.", "dim")
		return
	if reveal_hint() == "":
		narrate.emit("No more hints — trust what you've learned. `talk` to the locals, or `look` again.", "dim")


func _handle_look() -> void:
	_narrate_node(world.node(state.current), false)


func _handle_talk(who: String) -> void:
	var node := world.node(state.current)
	var npc: Dictionary = node.get("npc", {})
	if npc.is_empty():
		narrate.emit("There is no one here to talk to.", "dim")
		return
	narrate.emit("", "story")
	narrate.emit("%s:" % npc.get("name", "A stranger"), "header")
	var lines: Array = npc.get("lines", [])
	if who != "" and npc.has("hint") and (who == "hint" or who.contains("help")):
		lines = [npc.hint]
	for line in lines:
		narrate.emit("  \"%s\"" % str(line), "reaction")


# --- battle hints -----------------------------------------------------------

func battle_hints() -> Array:
	return world.node(state.current).get("battle", {}).get("hints", [])


func reveal_hint() -> String:
	if not _in_battle:
		return ""
	var hints := battle_hints()
	if _hints_shown >= hints.size():
		return ""
	var text: String = hints[_hints_shown]
	_hints_shown += 1
	narrate.emit("", "story")
	narrate.emit("HINT %d/%d  %s" % [_hints_shown, hints.size(), text], "warn")
	return text


func hints_shown() -> int:
	return _hints_shown


func in_battle() -> bool:
	return _in_battle


# --- text builders for instant read-only verbs ------------------------------

func status_text() -> String:
	var hearts := _hp_bar()
	var out := "HP  %s  %d/%d\n" % [hearts, state.hp, state.max_hp]
	out += "Location: %s\n" % world.node_name(state.current)
	out += "Keys: %s\n" % ("—" if state.flags.is_empty() else "  ".join(PackedStringArray(state.flags)))
	if state.deaths > 0:
		out += "Reboots survived: %d\n" % state.deaths
	return out


func map_text() -> String:
	var out := "MAP — %s\n\n" % world.title
	for nid in world.nodes:
		if not state.visited.has(nid):
			continue
		var marker := "●" if nid == state.current else ("✔" if state.is_cleared(nid) else "○")
		out += "  %s %s\n" % [marker, world.node_name(nid)]
		var ex: Dictionary = world.exits(nid)
		for dir in ex:
			var dest: String = ex[dir]
			var known := "%s" % world.node_name(dest) if state.visited.has(dest) else "???"
			out += "        %s → %s\n" % [dir, known]
	out += "\n  ● here   ✔ cleared   ○ visited\n"
	return out


func _hp_bar() -> String:
	var filled := int(round(10.0 * state.hp / maxi(1, state.max_hp)))
	return "[" + "#".repeat(filled) + "-".repeat(10 - filled) + "]"


func current_node() -> Dictionary:
	return world.node(state.current)


func exits_text() -> String:
	var ex: Dictionary = world.exits(state.current)
	if ex.is_empty():
		return "No exits from here."
	var parts: Array = []
	for dir in ex:
		parts.append("%s → %s" % [dir, world.node_name(ex[dir])])
	return "Exits:  " + "   ".join(PackedStringArray(parts))
