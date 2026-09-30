class_name JournalctlCommand
extends BaseCommand
## Reads the systemd journal: per-unit logs kept on each service. A teaching
## subset — enough to diagnose why a service won't start.


func get_command_name() -> String: return "journalctl"
func get_category() -> String: return "system"
func get_summary() -> String: return "read the system journal (service logs)"
func get_usage() -> String: return "journalctl [-u UNIT] [-n LINES] [-p err] [-f]"
func get_manual() -> String:
	return """The journal is where systemd services record what they do — and why they
crashed. When `systemctl status` says a service failed, the journal says why.
  journalctl -u nginx        everything nginx has logged
  journalctl -u nginx -n 20  just the last 20 lines
  journalctl -u nginx -p err only the error-level lines
  journalctl                 the whole journal, all units
-x adds hints, -e jumps to the end, -b limits to this boot: all accepted."""


func execute(ctx: CommandContext) -> int:
	var parsed := parse_options(ctx.args(), "unp", ["unit", "lines", "priority"])
	if parsed.error != "":
		return usage_error(ctx, parsed.error)
	var flags: Dictionary = parsed.flags
	var values: Dictionary = parsed.values
	var m := ctx.machine()

	var unit_name: String = str(values.get("u", values.get("unit", "")))
	var only_errors := str(values.get("p", values.get("priority", ""))) in ["err", "error", "3", "warning", "4"]

	var lines: Array = []
	if unit_name != "":
		var key := _resolve(m, unit_name)
		if key == "":
			ctx.err("Failed to look up unit %s: no such unit.\n" % unit_name)
			return 1
		lines = (m.services[key].get("journal", []) as Array).duplicate()
	else:
		var keys: Array = m.services.keys()
		keys.sort()
		for key in keys:
			lines.append_array(m.services[key].get("journal", []))

	if only_errors:
		var re := RegEx.create_from_string("(?i)(error|fail|fatal|denied|refused|cannot|unable)")
		var kept: Array = []
		for line in lines:
			if re.search(str(line)) != null:
				kept.append(line)
		lines = kept

	if values.has("n") or values.has("lines"):
		var n := int(str(values.get("n", values.get("lines", "10"))))
		if n > 0 and lines.size() > n:
			lines = lines.slice(lines.size() - n)

	if lines.is_empty():
		ctx.out("-- No entries --\n", "dim")
		return 0
	ctx.out("-- Journal begins. --\n", "dim")
	var err_re := RegEx.create_from_string("(?i)(error|fail|fatal|denied|refused)")
	for line in lines:
		ctx.out(str(line) + "\n", "err" if err_re.search(str(line)) != null else "")
	return 0


func _resolve(m: Machine, name: String) -> String:
	if m.has_service(name):
		return name
	for suffix in [".service", ".socket", ".timer", ".target"]:
		if name.ends_with(suffix):
			var bare := name.substr(0, name.length() - suffix.length())
			if m.has_service(bare):
				return bare
	return ""
