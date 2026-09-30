class_name ExitCommand
extends BaseCommand


func get_command_name() -> String: return "exit"
func get_aliases() -> Array: return ["logout"]
func get_category() -> String: return "shell"
func get_summary() -> String: return "leave the current shell"


func execute(ctx: CommandContext) -> int:
	var code := ctx.session.last_exit_code
	if not ctx.args().is_empty() and str(ctx.args()[0]).is_valid_int():
		code = int(ctx.args()[0])
	if ctx.depth > 0:
		# Inside a script: stop the script, not the terminal.
		ctx.session.exit_requested = code
		return code
	ctx.out("logout\n")
	if ctx.session.pop_user():
		ctx.emit("shell_exited", {"user": ctx.session.user})
		return 0
	ctx.out("(This is your login shell. Type :menu to return to the main menu.)\n", "dim")
	return 0
