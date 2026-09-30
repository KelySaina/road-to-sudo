class_name PwdCommand
extends BaseCommand


func get_command_name() -> String: return "pwd"
func get_category() -> String: return "basics"
func get_summary() -> String: return "print the current working directory"
func get_manual() -> String:
	return "Prints the absolute path of the directory you are in.\nEvery relative path you type is resolved from here."


func execute(ctx: CommandContext) -> int:
	ctx.out(ctx.session.cwd + "\n")
	return 0
