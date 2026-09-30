class_name KillCommand
extends BaseCommand


func get_command_name() -> String: return "kill"
func get_category() -> String: return "processes"
func get_summary() -> String: return "send a signal to a process"
func get_usage() -> String: return "kill [-9 | -TERM | -KILL] PID..."
func get_manual() -> String:
	return "Asks a process to stop (SIGTERM, the polite default).  kill -9 PID sends\nSIGKILL, which cannot be ignored — use it when asking nicely failed.\nYou may only signal your own processes, unless you are root."


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var sig := "TERM"
	if not args.is_empty() and str(args[0]).begins_with("-"):
		var s: String = str(args.pop_front()).trim_prefix("-").trim_prefix("SIG")
		if s == "l":
			ctx.out(" 1) SIGHUP   2) SIGINT   9) SIGKILL  15) SIGTERM  18) SIGCONT  19) SIGSTOP\n")
			return 0
		sig = {"9": "KILL", "15": "TERM", "1": "HUP", "2": "INT"}.get(s, s)
	if args.is_empty():
		return usage_error(ctx)
	var code := 0
	for a in args:
		if not str(a).is_valid_int():
			code = ctx.fail("", "failed to parse argument: '%s'" % a)
			continue
		var pid := int(a)
		var p := ctx.machine().find_process(pid)
		if p.is_empty():
			ctx.err("kill: (%d) - No such process\n" % pid)
			code = 1
			continue
		if p.user != ctx.session.user and not ctx.access().is_root():
			ctx.err("kill: (%d) - Operation not permitted\n" % pid)
			ctx.emit("permission_denied", {"command": "kill", "path": str(pid)})
			code = 1
			continue
		if p.get("ignores_term", false) and sig == "TERM":
			continue # stubborn process: survives the polite signal
		ctx.machine().kill(pid)
		ctx.emit("process_killed", {"pid": pid, "cmd": p.cmd, "signal": sig})
	return code
