class_name SuCommand
extends BaseCommand
## Switch user — and, unlike before, it actually asks for the TARGET's password.
## At the terminal it opens a masked password prompt (the overlay); in a pipe it
## reads the password from stdin (`echo pw | su bob`). A user with no password is
## locked (su fails), which is the modern default for root — so the lesson lands:
## root is locked, use sudo. Verification is su's own (the target's password),
## separate from sudo's policy check, exactly like real Linux.


func get_command_name() -> String: return "su"
func get_category() -> String: return "users"
func get_summary() -> String: return "switch user (asks for that user's password)"
func get_usage() -> String: return "su [-] [USER]"
func get_manual() -> String:
	return """Becomes another user (root with no USER), after asking for the TARGET's password.
At the terminal a masked prompt appears; in a pipe the password is read from stdin.
Modern systems lock the root password and use sudo instead: sudo checks YOUR
password and a policy, which is easier to audit. `su -` also loads the login env."""


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var login := false
	if not args.is_empty() and args[0] in ["-", "-l", "--login"]:
		login = true
		args.pop_front()
	var target: String = "root" if args.is_empty() else args[0]
	var m := ctx.machine()
	if not m.has_user(target):
		return ctx.fail("", "user %s does not exist or the user entry does not contain all the required fields" % target)

	# root may become anyone without a password, like real su.
	if ctx.session.user == "root":
		ctx.session.switch_user(target, login)
		ctx.emit("user_switched", {"user": target})
		return 0

	var stored := str(m.users[target].get("password", ""))
	if ctx.has_stdin:
		return _finish(ctx, target, login, stored, ctx.stdin.split("\n")[0])
	if ctx.to_screen:
		# Hand off to the interactive password prompt; Game resolves it.
		ctx.emit("open_prompt", {"kind": "su", "target": target, "login": login, "label": "Password: "})
		return 0
	# No terminal and no piped password: nothing to authenticate with.
	ctx.err("su: Authentication failure\n")
	ctx.emit("su_failed", {"target": target})
	return 1


func _finish(ctx: CommandContext, target: String, login: bool, stored: String, given: String) -> int:
	if stored != "" and given == stored:
		ctx.session.switch_user(target, login)
		ctx.emit("user_switched", {"user": target})
		return 0
	ctx.err("su: Authentication failure\n")
	ctx.emit("su_failed", {"target": target})
	if stored == "":
		ctx.out("(%s has no password set — the account is locked. Use sudo instead: sudo -i)\n" % target, "dim")
	return 1
