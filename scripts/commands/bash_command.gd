class_name BashCommand
extends BaseCommand


func get_command_name() -> String: return "bash"
func get_aliases() -> Array: return ["sh"]
func get_category() -> String: return "shell"
func get_summary() -> String: return "run a shell script or a command string"
func get_usage() -> String: return "bash SCRIPT [ARGS...]  |  bash -c 'COMMANDS'"
func get_manual() -> String:
	return "Runs a script with the shell interpreter. Note: `bash script.sh` only needs\nREAD permission, while `./script.sh` needs EXECUTE permission too."


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	if args.is_empty():
		ctx.err("bash: nested interactive shells are not simulated yet — you are already in one.\n")
		return 1
	if args[0] == "-c":
		if args.size() < 2:
			return usage_error(ctx, "-c: option requires an argument")
		ctx.shell.run_into(args[1], ctx.outcome, ctx.depth + 1, ctx)
		if ctx.session.exit_requested >= 0:
			ctx.session.last_exit_code = ctx.session.exit_requested
			ctx.session.exit_requested = -1
		return ctx.session.last_exit_code
	var path: String = args[0]
	var res := ctx.vfs().read_file(ctx.resolve(path), ctx.access())
	if not res.ok:
		return ctx.fail(path, res.error, 127 if res.error == VirtualFileSystem.ENOENT else 126)
	return ctx.shell.run_script(res.value, args.slice(1), ctx)
