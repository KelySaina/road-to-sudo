class_name CpCommand
extends BaseCommand


func get_command_name() -> String: return "cp"
func get_category() -> String: return "files"
func get_summary() -> String: return "copy files and directories"
func get_usage() -> String: return "cp [-r] [-v] SOURCE... DEST"
func get_manual() -> String:
	return "Copies SOURCE to DEST. If DEST is an existing directory, copies go inside it.\n  -r  copy directories recursively\n  -v  explain what is being done"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var ops: Array = opts.operands
	if ops.size() < 2:
		return usage_error(ctx, "missing destination file operand after '%s'" % (ops[0] if ops.size() == 1 else ""))
	var dest: String = ops.pop_back()
	var dest_abs := ctx.resolve(dest)
	if ops.size() > 1 and not ctx.vfs().is_dir(dest_abs):
		return ctx.fail("target '%s'" % dest, VirtualFileSystem.ENOTDIR)
	var recursive: bool = opts.flags.has("r") or opts.flags.has("R") or opts.flags.has("recursive")
	var code := 0
	for src in ops:
		var res := ctx.vfs().copy(ctx.resolve(src), dest_abs, ctx.access(), recursive)
		if not res.ok:
			code = ctx.fail("cannot copy '%s'" % src, res.error)
			continue
		if opts.flags.has("v"):
			ctx.out("'%s' -> '%s'\n" % [src, dest])
		ctx.emit("file_created", {"path": dest_abs})
	return code
