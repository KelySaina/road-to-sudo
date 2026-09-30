class_name PkillCommand
extends BaseCommand


func get_command_name() -> String: return "pkill"
func get_category() -> String: return "processes"
func get_summary() -> String: return "kill processes by name"
func get_usage() -> String: return "pkill PATTERN"
func get_manual() -> String:
	return "Signals every process whose command matches PATTERN — like pgrep, but it\nkills. Handy when you don't know the PID:  pkill xmrig\nYou may only kill your own processes unless you are root."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.operands.is_empty():
		return usage_error(ctx, "no matching criteria specified")
	var pat: String = opts.operands[0]
	var killed := 0
	var denied := false
	for p in ctx.machine().processes.duplicate():
		if not (str(p.cmd).contains(pat)):
			continue
		if p.user != ctx.session.user and not ctx.access().is_root():
			denied = true
			continue
		if p.get("ignores_term", false):
			continue
		ctx.machine().kill(int(p.pid))
		ctx.emit("process_killed", {"pid": int(p.pid), "cmd": p.cmd, "signal": "TERM"})
		killed += 1
	if denied and killed == 0:
		ctx.emit("permission_denied", {"command": "pkill", "path": pat})
	return 0 if killed > 0 else 1
