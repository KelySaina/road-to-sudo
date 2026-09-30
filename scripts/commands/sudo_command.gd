class_name SudoCommand
extends BaseCommand


func get_command_name() -> String: return "sudo"
func get_category() -> String: return "users"
func get_summary() -> String: return "run a command as another user (root by default)"
func get_usage() -> String: return "sudo [-u USER] COMMAND  |  sudo -i  |  sudo -l"
func get_manual() -> String:
	return """"superuser do". Runs one command with root's privileges — if /etc/sudoers
(or membership in the 'sudo' group) says you may.
  sudo COMMAND     run COMMAND as root
  sudo -u bob CMD  run as bob
  sudo -l          list what you are allowed to do
  sudo -i          open a root login shell (exit to come back)
With great power comes an audit log: every sudo is recorded."""


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var target := "root"
	var login := false
	var list := false
	while not args.is_empty() and str(args[0]).begins_with("-"):
		var a: String = args.pop_front()
		match a:
			"-i", "--login", "-s":
				login = true
			"-l", "--list":
				list = true
			"-u":
				if args.is_empty():
					return usage_error(ctx, "option requires an argument -- 'u'")
				target = args.pop_front()
			"--":
				break
			_:
				return usage_error(ctx, "invalid option -- '%s'" % a.trim_prefix("-"))
	var user := ctx.session.user
	var m := ctx.machine()
	ctx.emit("sudo_attempt", {"user": user, "allowed": m.is_sudoer(user), "args": args})
	if not m.is_sudoer(user):
		ctx.err("[sudo] password for %s: \n" % user)
		ctx.err("%s is not in the sudoers file.\n" % user)
		ctx.err("This incident will be reported.\n")
		ctx.emit("sudo_denied", {"user": user})
		return 1
	if user != "root" and ctx.to_screen:
		ctx.out("[sudo] password for %s: ********\n" % user, "dim")
	if not m.has_user(target):
		return ctx.fail("", "unknown user %s" % target)
	if list:
		ctx.out("User %s may run the following commands on %s:\n    (ALL : ALL) ALL\n" % [user, m.hostname])
		return 0
	if login:
		ctx.session.switch_user(target, true)
		ctx.emit("root_shell", {"user": target})
		return 0
	if args.is_empty():
		return usage_error(ctx)
	ctx.session.switch_user(target, false)
	var child := ctx.spawn(args)
	child.depth = ctx.depth
	var code: int = ctx.shell.invoke(child)
	ctx.absorb(child)
	ctx.session.pop_user()
	ctx.emit("sudo_ran", {"command": args[0], "exit_code": code})
	return code
