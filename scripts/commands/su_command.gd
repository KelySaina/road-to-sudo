class_name SuCommand
extends BaseCommand


func get_command_name() -> String: return "su"
func get_category() -> String: return "users"
func get_summary() -> String: return "switch user (needs that user's password)"
func get_usage() -> String: return "su [-] [USER]"
func get_manual() -> String:
	return "Becomes another user; with no USER, becomes root. Asks for the TARGET's password.\nModern systems usually lock the root password and use sudo instead:\nsudo checks YOUR password and a policy, which is easier to audit."


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var login := false
	if not args.is_empty() and args[0] in ["-", "-l", "--login"]:
		login = true
		args.pop_front()
	var target: String = "root" if args.is_empty() else args[0]
	if not ctx.machine().has_user(target):
		return ctx.fail("", "user %s does not exist or the user entry does not contain all the required fields" % target)
	if ctx.session.user != "root":
		ctx.err("Password: \n")
		ctx.err("su: Authentication failure\n")
		ctx.emit("su_failed", {"target": target})
		return 1
	ctx.session.switch_user(target, login)
	return 0
