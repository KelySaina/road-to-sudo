class_name StatCommand
extends BaseCommand


func get_command_name() -> String: return "stat"
func get_category() -> String: return "files"
func get_summary() -> String: return "show detailed file status"
func get_usage() -> String: return "stat FILE..."


func execute(ctx: CommandContext) -> int:
	if ctx.args().is_empty():
		return usage_error(ctx, "missing operand")
	var code := 0
	var m := ctx.machine()
	for f in ctx.args():
		var res := ctx.vfs().lookup(ctx.resolve(f), ctx.access())
		if not res.ok:
			code = ctx.fail("cannot statx '%s'" % f, res.error)
			continue
		var n := res.node
		var kind := "directory" if n.is_dir() else ("regular empty file" if n.content == "" else "regular file")
		ctx.out("  File: %s\n" % f)
		ctx.out("  Size: %-10d Blocks: %-10d IO Block: 4096   %s\n" % [n.size(), int(ceil(n.size() / 512.0)), kind])
		ctx.out("Access: (%s/%s)  Uid: (%5d/%8s)   Gid: (%5d/%8s)\n" % [
			Permissions.to_octal(n.mode).lpad(4, "0"), Permissions.to_symbolic(n.mode, n.kind_char()),
			m.uid_of(n.owner), n.owner, m.gid_of_group(n.group), n.group])
		ctx.out("Modify: %s\n" % n.mtime)
	return code
