class_name TouchCommand
extends BaseCommand


func get_command_name() -> String: return "touch"
func get_category() -> String: return "files"
func get_summary() -> String: return "create an empty file or update its timestamp"
func get_usage() -> String: return "touch FILE..."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.operands.is_empty():
		return usage_error(ctx, "missing file operand")
	var code := 0
	for f in opts.operands:
		var res := ctx.vfs().touch(ctx.resolve(f), ctx.access(), ctx.session.file_create_mode())
		if not res.ok:
			code = ctx.fail("cannot touch '%s'" % f, res.error)
		else:
			ctx.emit("file_created", {"path": ctx.resolve(f)})
	return code
