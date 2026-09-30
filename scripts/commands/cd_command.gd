class_name CdCommand
extends BaseCommand


func get_command_name() -> String: return "cd"
func get_category() -> String: return "basics"
func get_summary() -> String: return "change the current directory"
func get_usage() -> String: return "cd [DIR | - | ~]"
func get_manual() -> String:
	return "With no argument, go home. `cd -` returns to the previous directory.\n`cd ..` goes up one level. Paths may be absolute (/var/log) or relative (projects/)."


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	if args.size() > 1:
		return ctx.fail("", "too many arguments")
	var target: String = ctx.session.home() if args.is_empty() else args[0]
	if target == "-":
		if ctx.session.previous_cwd == "":
			return ctx.fail("", "OLDPWD not set")
		target = ctx.session.previous_cwd
		ctx.out(target + "\n")
	var abs_path := ctx.resolve(target)
	var res := ctx.vfs().lookup(abs_path, ctx.access())
	if not res.ok:
		return ctx.fail(target, res.error)
	if not res.node.is_dir():
		return ctx.fail(target, VirtualFileSystem.ENOTDIR)
	if not Permissions.can(res.node, ctx.access(), Permissions.EXEC):
		return ctx.fail(target, VirtualFileSystem.EACCES)
	ctx.session.set_cwd(abs_path)
	ctx.emit("cwd_changed", {"path": abs_path})
	return 0
