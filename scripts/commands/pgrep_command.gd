class_name PgrepCommand
extends BaseCommand


func get_command_name() -> String: return "pgrep"
func get_category() -> String: return "processes"
func get_summary() -> String: return "find process IDs by name"
func get_usage() -> String: return "pgrep [-l] PATTERN"
func get_manual() -> String:
	return "Prints the PIDs of processes whose command matches PATTERN.\n`pgrep -l nginx` also prints the name. Pair with kill:  kill $(pgrep miner)"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.operands.is_empty():
		return usage_error(ctx, "no matching criteria specified")
	var pat: String = opts.operands[0]
	var long: bool = opts.flags.has("l")
	var found := false
	for p in ctx.machine().processes:
		if str(p.cmd).contains(pat) or PathUtils.basename(str(p.cmd).split(" ")[0]).contains(pat):
			found = true
			ctx.out(("%d %s\n" % [int(p.pid), str(p.cmd).split(" ")[0].get_file()]) if long else "%d\n" % int(p.pid))
	return 0 if found else 1
