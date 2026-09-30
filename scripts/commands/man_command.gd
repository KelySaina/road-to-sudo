class_name ManCommand
extends BaseCommand


func get_command_name() -> String: return "man"
func get_category() -> String: return "basics"
func get_summary() -> String: return "read a command's manual page"
func get_usage() -> String: return "man COMMAND"
func get_manual() -> String:
	return "Every serious Linux user reads man pages. Try `man ls` or `man chmod`.\nOn a real system, press q to leave the pager; here the page just prints."


func execute(ctx: CommandContext) -> int:
	if ctx.args().is_empty():
		ctx.err("What manual page do you want?\nFor example, try 'man man'.\n")
		return 1
	var topic: String = ctx.args()[0]
	var registry: CommandRegistry = ctx.shell.registry
	var cmd := registry.get_command(topic)
	if cmd == null:
		ctx.err("No manual entry for %s\n" % topic)
		return 16
	var name := cmd.get_command_name()
	ctx.out("%s(1)%s%s(1)\n\n" % [name.to_upper(), "User Commands".lpad(30), name.to_upper().lpad(20)], "dim")
	ctx.out("NAME\n", "header")
	ctx.out("       %s - %s\n\n" % [name, cmd.get_summary()])
	ctx.out("SYNOPSIS\n", "header")
	ctx.out("       %s\n\n" % cmd.get_usage())
	ctx.out("DESCRIPTION\n", "header")
	for line in cmd.get_manual().split("\n"):
		ctx.out("       %s\n" % line)
	if not cmd.get_aliases().is_empty():
		ctx.out("\nALIASES\n", "header")
		ctx.out("       %s\n" % ", ".join(PackedStringArray(cmd.get_aliases())))
	ctx.emit("manual_read", {"topic": name})
	return 0
