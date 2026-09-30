class_name TopCommand
extends BaseCommand


func get_command_name() -> String: return "top"
func get_aliases() -> Array: return ["htop"]
func get_category() -> String: return "processes"
func get_summary() -> String: return "show processes by resource use"
func get_usage() -> String: return "top"
func get_manual() -> String:
	return "A snapshot of the busiest processes, sorted by CPU. On a real system top\nrefreshes live and you press q to quit; here it prints once. The greedy\nprocess floats to the top — that's usually the one you're hunting."


func execute(ctx: CommandContext) -> int:
	var procs: Array = ctx.machine().processes.duplicate()
	procs.sort_custom(func(a, b): return float(a.get("cpu", 0)) > float(b.get("cpu", 0)))
	var total_cpu := 0.0
	for p in procs:
		total_cpu += float(p.get("cpu", 0))
	ctx.out("top - 10:24:31 up 3 days,  2:14,  1 user,  load average: %.2f, 0.42, 0.31\n" % (total_cpu / 25.0), "dim")
	ctx.out("Tasks: %d total\n" % procs.size(), "dim")
	ctx.out("%%Cpu(s): %5.1f us   MiB Mem: 12000 total\n\n" % clampf(total_cpu, 0, 100), "dim")
	ctx.out("    PID USER      %CPU %MEM COMMAND\n", "header")
	for p in procs.slice(0, 12):
		var line := "%7d %-9s %4.1f %4.1f %s\n" % [int(p.pid), str(p.user).left(9), float(p.get("cpu", 0)), float(p.get("mem", 0)), str(p.cmd).split(" ")[0].get_file()]
		ctx.out(line, "warn" if float(p.get("cpu", 0)) > 50.0 else "")
	return 0
