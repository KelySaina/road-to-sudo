class_name RmdirCommand
extends BaseCommand


func get_command_name() -> String: return "rmdir"
func get_category() -> String: return "files"
func get_summary() -> String: return "remove empty directories"
func get_usage() -> String: return "rmdir DIR..."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.operands.is_empty():
		return usage_error(ctx, "missing operand")
	var code := 0
	for d in opts.operands:
		var abs_path := ctx.resolve(d)
		if ctx.vfs().exists(abs_path) and not ctx.vfs().is_dir(abs_path):
			code = ctx.fail("failed to remove '%s'" % d, VirtualFileSystem.ENOTDIR)
			continue
		var res := ctx.vfs().remove(abs_path, ctx.access(), false, true)
		if not res.ok:
			code = ctx.fail("failed to remove '%s'" % d, res.error)
	return code
