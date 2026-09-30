class_name SystemctlCommand
extends BaseCommand
## A teaching subset of systemd's service manager. Reads and mutates the
## machine's `services` table; state-changing verbs require root (use sudo).


func get_command_name() -> String: return "systemctl"
func get_category() -> String: return "system"
func get_summary() -> String: return "control system services (status, start, stop, enable...)"
func get_usage() -> String:
	return "systemctl [status|start|stop|restart|enable|disable|is-active|is-enabled|list-units] [UNIT...]"
func get_manual() -> String:
	return """systemctl controls the init system that runs background services (daemons).
  systemctl status nginx      is it running? why did it stop?
  systemctl start  nginx      start it now            (needs root)
  systemctl stop   nginx      stop it now             (needs root)
  systemctl restart nginx     stop, then start again  (needs root)
  systemctl enable  nginx     start it on every boot  (needs root)
  systemctl disable nginx     don't start it on boot  (needs root)
  systemctl is-active nginx   prints active / inactive / failed
  systemctl list-units        every known service and its state
'active' means running now. 'enabled' means it starts at boot. They are
independent: a service can be enabled but stopped, or running but not enabled.
Changing state needs privilege — prefix with sudo."""


func execute(ctx: CommandContext) -> int:
	var operands: Array = []
	var failed_only := false
	var now := false
	for a in ctx.args():
		var s := str(a)
		if s == "--failed" or s == "--state=failed":
			failed_only = true
		elif s == "--now":
			now = true
		elif s.begins_with("-"):
			pass # --no-pager, -l, --all, --type=..., -q: accepted and ignored
		else:
			operands.append(s)

	var sub: String = operands[0] if operands.size() > 0 else "list-units"
	var units: Array = operands.slice(1)

	match sub:
		"list-units", "list-unit-files", "list-sockets":
			return _list(ctx, failed_only, sub == "list-unit-files")
		"status":
			return _status(ctx, units)
		"is-active":
			return _is(ctx, units, "active")
		"is-enabled":
			return _is(ctx, units, "enabled")
		"is-failed":
			return _is(ctx, units, "failed")
		"start", "stop", "restart", "reload", "reload-or-restart", "try-restart", "enable", "disable":
			return _change(ctx, sub, units, now)
		_:
			# Bare `systemctl UNIT` isn't a thing; a lone verb means list-units.
			if operands.size() == 1 and not ctx.machine().has_service(_bare(sub)):
				return _list(ctx, failed_only, false)
			ctx.err("systemctl: unknown command or unit '%s'.\n" % sub)
			return 1


# --- readers -----------------------------------------------------------------

func _status(ctx: CommandContext, units: Array) -> int:
	var m := ctx.machine()
	if units.is_empty():
		return _list(ctx, false, false)
	var worst := 0
	for u in units:
		var key := _resolve(m, str(u))
		if key == "":
			ctx.err("Unit %s could not be found.\n" % _dotted(str(u)))
			worst = maxi(worst, 4)
			continue
		var s: Dictionary = m.services[key]
		var active: bool = bool(s.active)
		var is_failed: bool = str(s.sub) == "failed"
		ctx.out(_glyph(s) + " ", _state_style(s))
		ctx.out("%s - %s\n" % [s.unit, s.description])
		var boot := "enabled" if bool(s.enabled) else "disabled"
		ctx.out("     Loaded: loaded (/lib/systemd/system/%s; %s; preset: enabled)\n" % [s.unit, boot], "dim")
		if active:
			ctx.out("     Active: active (running) since %s\n" % s.since, "success")
		elif is_failed:
			ctx.out("     Active: failed (Result: exit-code) since %s\n" % s.since, "err")
		else:
			ctx.out("     Active: inactive (dead)\n", "dim")
		if active and int(s.main_pid) > 0:
			ctx.out("   Main PID: %d (%s)\n" % [int(s.main_pid), key])
		_print_journal_tail(ctx, s.get("journal", []), 6)
		if units.size() > 1:
			ctx.out("\n")
		if not active:
			worst = maxi(worst, 3)
	return worst


func _is(ctx: CommandContext, units: Array, kind: String) -> int:
	var m := ctx.machine()
	if units.is_empty():
		return usage_error(ctx, "expected a unit name")
	var code := 0
	for u in units:
		var key := _resolve(m, str(u))
		if key == "":
			ctx.out("inactive\n" if kind != "enabled" else "not-found\n")
			code = maxi(code, 4 if kind == "enabled" else 3)
			continue
		var s: Dictionary = m.services[key]
		if kind == "enabled":
			ctx.out(("enabled" if bool(s.enabled) else "disabled") + "\n")
			if not bool(s.enabled):
				code = maxi(code, 1)
		elif kind == "failed":
			var f := str(s.sub) == "failed"
			ctx.out(("failed" if f else "active" if bool(s.active) else "inactive") + "\n")
			if not f:
				code = maxi(code, 1)
		else: # active
			var word := "active" if bool(s.active) else ("failed" if str(s.sub) == "failed" else "inactive")
			ctx.out(word + "\n", "success" if bool(s.active) else "dim")
			if not bool(s.active):
				code = maxi(code, 3)
	return code


func _list(ctx: CommandContext, failed_only: bool, unit_files: bool) -> int:
	var m := ctx.machine()
	var keys: Array = m.services.keys()
	keys.sort()
	if unit_files:
		ctx.out("UNIT FILE                     STATE     PRESET\n", "header")
		for key in keys:
			var s: Dictionary = m.services[key]
			var state := "enabled" if bool(s.enabled) else "disabled"
			ctx.out("%s %s enabled\n" % [str(s.unit).rpad(29), state.rpad(9)])
		ctx.out("\n%d unit files listed.\n" % keys.size(), "dim")
		return 0
	ctx.out("  UNIT                     LOAD   ACTIVE   SUB     DESCRIPTION\n", "header")
	var shown := 0
	for key in keys:
		var s: Dictionary = m.services[key]
		if failed_only and str(s.sub) != "failed":
			continue
		var active := "active" if bool(s.active) else ("failed" if str(s.sub) == "failed" else "inactive")
		ctx.out(_glyph(s) + " ", _state_style(s))
		ctx.out("%s loaded %s %s %s\n" % [str(s.unit).rpad(24), active.rpad(8), str(s.sub).rpad(7), s.description])
		shown += 1
	if failed_only and shown == 0:
		ctx.out("0 loaded units listed. No failed units.\n", "dim")
	return 0


# --- mutators ----------------------------------------------------------------

func _change(ctx: CommandContext, verb: String, units: Array, now: bool) -> int:
	if units.is_empty():
		return usage_error(ctx, "expected a unit name")
	if ctx.session.user != "root":
		ctx.err("Failed to %s unit: Interactive authentication required.\n" % verb)
		ctx.out("This action needs privileges. Try: sudo systemctl %s %s\n" % [verb, " ".join(PackedStringArray(units))], "dim")
		ctx.emit("service_denied", {"verb": verb})
		return 1
	var m := ctx.machine()
	var code := 0
	for u in units:
		var key := _resolve(m, str(u))
		if key == "":
			ctx.err("Failed to %s %s: Unit %s not found.\n" % [verb, _dotted(str(u)), _dotted(str(u))])
			code = maxi(code, 5)
			continue
		var s: Dictionary = m.services[key]
		match verb:
			"start":
				code = maxi(code, _do_start(ctx, key, s))
			"stop":
				_do_stop(ctx, key, s)
			"restart", "try-restart", "reload-or-restart":
				if verb == "try-restart" and not bool(s.active):
					continue
				_do_stop(ctx, key, s)
				code = maxi(code, _do_start(ctx, key, s))
			"reload":
				if not bool(s.active):
					ctx.err("Failed to reload %s: unit is not active.\n" % s.unit)
					code = maxi(code, 1)
				else:
					m.journal(key, "Reloaded %s." % s.description)
			"enable":
				s.enabled = true
				ctx.out("Created symlink /etc/systemd/system/multi-user.target.wants/%s → /lib/systemd/system/%s.\n" % [s.unit, s.unit])
				ctx.emit("service_changed", {"unit": key, "verb": "enable", "enabled": true})
				if now:
					code = maxi(code, _do_start(ctx, key, s))
			"disable":
				s.enabled = false
				ctx.out("Removed /etc/systemd/system/multi-user.target.wants/%s.\n" % s.unit)
				ctx.emit("service_changed", {"unit": key, "verb": "disable", "enabled": false})
				if now:
					_do_stop(ctx, key, s)
	return code


func _do_start(ctx: CommandContext, key: String, s: Dictionary) -> int:
	var m := ctx.machine()
	if bool(s.active):
		return 0
	var needs: Dictionary = s.get("needs", {})
	if not needs.is_empty() and not ConditionEvaluator.evaluate(needs, {"session": ctx.session, "events": []}):
		s.active = false
		s.sub = "failed"
		s.since = Machine._stamp()
		m.journal(key, "Failed to start %s — check the configuration." % s.description)
		ctx.err("Job for %s failed because the control process exited with error code.\n" % s.unit)
		ctx.err("See \"systemctl status %s\" and \"journalctl -xeu %s\" for details.\n" % [key, key])
		ctx.emit("service_changed", {"unit": key, "verb": "start", "active": false})
		return 1
	s.active = true
	s.sub = "running"
	s.since = Machine._stamp()
	if int(s.main_pid) <= 0:
		s.main_pid = m.spawn("root", str(s.exec), 0.4, 0.6).pid
	m.journal(key, "Started %s." % s.description)
	ctx.emit("service_changed", {"unit": key, "verb": "start", "active": true})
	return 0


func _do_stop(ctx: CommandContext, key: String, s: Dictionary) -> void:
	var m := ctx.machine()
	if int(s.main_pid) > 0:
		m.kill(int(s.main_pid))
	s.active = false
	s.sub = "dead"
	s.main_pid = 0
	m.journal(key, "Stopped %s." % s.description)
	ctx.emit("service_changed", {"unit": key, "verb": "stop", "active": false})


# --- helpers -----------------------------------------------------------------

func _print_journal_tail(ctx: CommandContext, journal: Array, n: int) -> void:
	if journal.is_empty():
		return
	var start := maxi(0, journal.size() - n)
	for i in range(start, journal.size()):
		ctx.out("       " + str(journal[i]) + "\n", "dim")


func _glyph(s: Dictionary) -> String:
	if bool(s.active):
		return "●" # ●
	if str(s.sub) == "failed":
		return "×" # ×
	return "○"     # ○


func _state_style(s: Dictionary) -> String:
	if bool(s.active):
		return "success"
	if str(s.sub) == "failed":
		return "err"
	return "dim"


## Accepts "nginx", "nginx.service", "sshd.socket"; returns the stored key or "".
func _resolve(m: Machine, name: String) -> String:
	if m.has_service(name):
		return name
	var bare := _bare(name)
	if m.has_service(bare):
		return bare
	return ""


func _bare(name: String) -> String:
	for suffix in [".service", ".socket", ".timer", ".target"]:
		if name.ends_with(suffix):
			return name.substr(0, name.length() - suffix.length())
	return name


func _dotted(name: String) -> String:
	return name if name.contains(".") else name + ".service"
