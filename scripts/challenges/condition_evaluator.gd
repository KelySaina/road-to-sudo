class_name ConditionEvaluator
extends RefCounted
## Evaluates challenge conditions against the *state* of the simulation
## rather than the literal command typed, so every valid solution passes.
##
## Composite:  {"all": [...]}  {"any": [...]}  {"not": {...}}
## Leaf:       {"type": "<name>", ...}  — see docs/ADDING_CHALLENGES.md
##
## `state` is a Dictionary:
##   session: ShellSession, log_start: int (command_log index when the
##   challenge began), events: Array of outcome events since then.


static func evaluate(cond: Dictionary, state: Dictionary) -> bool:
	if cond.is_empty():
		return false
	if cond.has("all"):
		for c in cond.all:
			if not evaluate(c, state):
				return false
		return true
	if cond.has("any"):
		for c in cond.any:
			if evaluate(c, state):
				return true
		return false
	if cond.has("not"):
		return not evaluate(cond["not"], state)

	var session: ShellSession = state.session
	var vfs := session.machine.vfs
	match str(cond.get("type", "")):
		"command_ran":
			return not _matching_records(cond, state).is_empty()
		"output_contains":
			return _output_contains(cond, state)
		"output_matches":
			var re := RegEx.create_from_string(cond.regex)
			for r in _records(state, cond.get("scope", "any")):
				if re.search(r.stdout) != null:
					return true
			return false
		"file_exists":
			var n := vfs.get_node_at(_path(cond.path, session))
			return n != null and not n.is_dir()
		"dir_exists":
			return vfs.is_dir(_path(cond.path, session))
		"path_missing":
			return not vfs.exists(_path(cond.path, session))
		"file_contains":
			var n := vfs.get_node_at(_path(cond.path, session))
			if n == null or n.is_dir():
				return false
			if cond.get("ignore_case", false):
				return n.content.to_lower().contains(str(cond.text).to_lower())
			return n.content.contains(cond.text)
		"file_matches":
			var n := vfs.get_node_at(_path(cond.path, session))
			return n != null and not n.is_dir() and RegEx.create_from_string(cond.regex).search(n.content) != null
		"mode_is":
			var n := vfs.get_node_at(_path(cond.path, session))
			return n != null and (n.mode & 4095) == Permissions.from_octal(str(cond.mode))
		"mode_has":
			var n := vfs.get_node_at(_path(cond.path, session))
			if n == null:
				return false
			var wanted := Permissions.apply_spec(0, str(cond.bits).replace("-", "+"))
			return (n.mode & wanted) == wanted
		"mode_lacks":
			var n := vfs.get_node_at(_path(cond.path, session))
			if n == null:
				return false
			var unwanted := Permissions.apply_spec(0, str(cond.bits).replace("-", "+"))
			return (n.mode & unwanted) == 0
		"owner_is":
			var n := vfs.get_node_at(_path(cond.path, session))
			if n == null:
				return false
			return (not cond.has("owner") or n.owner == cond.owner) and (not cond.has("group") or n.group == cond.group)
		"cwd_is":
			return session.cwd == _path(cond.path, session)
		"user_is":
			return session.user == cond.user
		"env_is":
			return str(session.env.get(cond.name, "")) == str(cond.get("value", ""))
		"event":
			return _event_seen(cond, state)
		"process_running":
			return _process_exists(session.machine, cond)
		"process_absent":
			return not _process_exists(session.machine, cond)
		"service_active":
			return session.machine.service_active(cond.service) == bool(cond.get("expect", true))
		"service_enabled":
			return session.machine.service_enabled(cond.service) == bool(cond.get("expect", true))
		"has_flag":
			return session.adventure != null and session.adventure.state.has_flag(cond.flag)
	push_warning("Unknown condition type: %s" % cond.get("type", "?"))
	return false


static func _records(state: Dictionary, scope: String) -> Array:
	var session: ShellSession = state.session
	var start := clampi(int(state.get("log_start", 0)), 0, session.command_log.size())
	var recs: Array = session.command_log.slice(start)
	if scope == "last":
		return state.get("last_records", [])
	return recs


static func _matching_records(cond: Dictionary, state: Dictionary) -> Array:
	var out: Array = []
	var names: Array = cond.name if cond.get("name") is Array else [cond.get("name", "")]
	for r in _records(state, cond.get("scope", "any")):
		if not (r.name in names or PathUtils.basename(r.name) in names):
			continue
		if cond.has("exit_code") and int(r.exit_code) != int(cond.exit_code):
			continue
		if cond.has("user") and r.user != cond.user:
			continue
		if cond.has("cwd") and r.cwd != _path(cond.cwd, state.session):
			continue
		if cond.has("args_contain"):
			var joined := " ".join(PackedStringArray(r.args))
			if not joined.contains(cond.args_contain):
				continue
		out.append(r)
	return out


static func _output_contains(cond: Dictionary, state: Dictionary) -> bool:
	var needle: String = cond.text
	var ignore_case: bool = cond.get("ignore_case", false)
	for r in _records(state, cond.get("scope", "any")):
		var hay: String = r.stdout
		if ignore_case:
			if hay.to_lower().contains(needle.to_lower()):
				return true
		elif hay.contains(needle):
			return true
	return false


static func _event_seen(cond: Dictionary, state: Dictionary) -> bool:
	var want: Dictionary = cond.get("data", {})
	for e in state.get("events", []):
		if e.name != cond.name:
			continue
		var ok := true
		for k in want:
			var expected: Variant = want[k]
			if expected is String and str(expected).begins_with("~"):
				expected = _path(expected, state.session)
			if str(e.data.get(k, "")) != str(expected):
				ok = false
				break
		var contains: Dictionary = cond.get("data_contains", {})
		for k in contains:
			if not str(e.data.get(k, "")).contains(str(contains[k])):
				ok = false
				break
		if ok:
			return true
	return false


static func _process_exists(m: Machine, cond: Dictionary) -> bool:
	for p in m.processes:
		if cond.has("pid") and int(p.pid) == int(cond.pid):
			return true
		if cond.has("cmd_contains") and str(p.cmd).contains(cond.cmd_contains):
			return true
	return false


## Condition paths may use ~ for the player's home.
static func _path(path: String, session: ShellSession) -> String:
	if path.begins_with("~"):
		var home := session.machine.home_of(_player_user(session))
		return PathUtils.normalize(home + path.substr(1))
	return PathUtils.normalize(path)


## The login user at the bottom of the su/sudo stack.
static func _player_user(session: ShellSession) -> String:
	if not session.user_stack.is_empty():
		return session.user_stack[0].user
	return session.user
