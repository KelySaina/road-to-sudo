class_name RmCommand
extends BaseCommand


func get_command_name() -> String: return "rm"
func get_category() -> String: return "files"
func get_summary() -> String: return "remove files or directories (there is no trash can)"
func get_usage() -> String: return "rm [-r] [-f] [-v] FILE..."
func get_manual() -> String:
	return "Deletes files. There is no undo and no recycle bin.\n  -r  remove directories and their contents\n  -f  never prompt, ignore missing files\n  -v  explain what is being done\nRead the command twice before pressing Enter."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var f: Dictionary = opts.flags
	var recursive := f.has("r") or f.has("R") or f.has("recursive")
	var force := f.has("f") or f.has("force")
	if opts.operands.is_empty():
		if force:
			return 0
		return usage_error(ctx, "missing operand")
	var code := 0
	for target in opts.operands:
		var abs_path := ctx.resolve(target)
		if recursive and (abs_path == "/" or target == "/*"):
			ctx.err("rm: it is dangerous to operate recursively on '/'\nrm: use --no-preserve-root to override this failsafe\n")
			ctx.emit("rm_root_attempt")
			code = 1
			continue
		if target == "." or target == ".." or target.ends_with("/.") or target.ends_with("/.."):
			code = ctx.fail("", "refusing to remove '.' or '..' directory: skipping '%s'" % target)
			continue
		var node := ctx.vfs().get_node_at(abs_path)
		if node == null and force:
			continue
		var res := ctx.vfs().remove(abs_path, ctx.access(), recursive)
		if not res.ok:
			code = ctx.fail("cannot remove '%s'" % target, res.error)
			continue
		if f.has("v"):
			ctx.out("removed %s'%s'\n" % ["directory " if res.node.is_dir() else "", target])
		ctx.emit("file_deleted", {"path": abs_path, "was_dir": res.node.is_dir()})
	return code
