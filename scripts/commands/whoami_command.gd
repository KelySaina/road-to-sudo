class_name WhoamiCommand
extends BaseCommand


func get_command_name() -> String: return "whoami"
func get_category() -> String: return "users"
func get_summary() -> String: return "print the current user name"
func get_manual() -> String:
	return "Prints the name of the user you are acting as.\nEvery permission check on the system is made against this identity."


func execute(ctx: CommandContext) -> int:
	ctx.out(ctx.session.user + "\n")
	ctx.emit("identity_checked", {"user": ctx.session.user})
	return 0
