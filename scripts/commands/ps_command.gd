class_name PsCommand
extends BaseCommand


func get_command_name() -> String: return "ps"
func get_category() -> String: return "processes"
func get_summary() -> String: return "list running processes"
func get_usage() -> String: return "ps [aux | -e | -ef]"
func get_manual() -> String:
	return "Without options: processes in your terminal.\n  ps aux   every process, with owner, CPU and memory usage\nEach process has a PID (process id) — that is what kill needs."


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var full := false
	for a in args:
		if str(a).contains("a") or str(a).contains("e") or str(a).contains("x"):
			full = true
	var procs: Array = ctx.machine().processes
	if not full:
		ctx.out("    PID TTY          TIME CMD\n", "header")
		ctx.out("   %4d pts/0    00:00:00 bash\n" % 4242)
		for p in procs:
			if p.user == ctx.session.user and p.get("tty", "?") == "pts/0":
				ctx.out("   %4d pts/0    00:00:00 %s\n" % [int(p.pid), str(p.cmd).get_file()])
		ctx.out("   %4d pts/0    00:00:00 ps\n" % 4243)
		return 0
	ctx.out("USER         PID %CPU %MEM STAT COMMAND\n", "header")
	var rows: Array = procs.duplicate()
	rows.append({"pid": 4242, "user": ctx.session.user, "cpu": 0.0, "mem": 0.1, "stat": "Ss", "cmd": "-bash"})
	rows.append({"pid": 4243, "user": ctx.session.user, "cpu": 0.0, "mem": 0.1, "stat": "R+", "cmd": "ps aux"})
	for p in rows:
		var line := "%s %6d %4.1f %4.1f %-4s %s\n" % [str(p.user).rpad(8), int(p.pid), float(p.cpu), float(p.mem), p.get("stat", "S"), p.cmd]
		ctx.out(line, "warn" if float(p.cpu) > 50.0 else "")
	return 0
