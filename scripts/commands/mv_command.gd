class_name MvCommand
extends BaseCommand


func get_command_name() -> String: return "mv"
func get_category() -> String: return "files"
func get_summary() -> String: return "move or rename files"
func get_usage() -> String: return "mv [-v] SOURCE... DEST"
func get_manual() -> String:
	return "Renames SOURCE to DEST, or moves sources into DEST if it is a directory.\nThere is no 'rename' command: renaming is just moving within a directory."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var ops: Array = opts.operands
	if ops.size() < 2:
		return usage_error(ctx, "missing destination file operand")
	var dest: String = ops.pop_back()
	var dest_abs := ctx.resolve(dest)
	if ops.size() > 1 and not ctx.vfs().is_dir(dest_abs):
		return ctx.fail("target '%s'" % dest, VirtualFileSystem.ENOTDIR)
	var code := 0
	for src in ops:
		var res := ctx.vfs().move(ctx.resolve(src), dest_abs, ctx.access())
		if not res.ok:
			code = ctx.fail("cannot move '%s'" % src, res.error)
			continue
		if opts.flags.has("v"):
			ctx.out("renamed '%s' -> '%s'\n" % [src, dest])
		ctx.emit("file_moved", {"from": ctx.resolve(src), "to": dest_abs})
	return code
