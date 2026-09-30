class_name MkdirCommand
extends BaseCommand


func get_command_name() -> String: return "mkdir"
func get_category() -> String: return "files"
func get_summary() -> String: return "create directories"
func get_usage() -> String: return "mkdir [-p] [-v] DIR..."
func get_manual() -> String:
	return "Creates directories.  -p creates missing parents and does not complain\nif the directory already exists (mkdir -p a/b/c).  -v says what it did."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.operands.is_empty():
		return usage_error(ctx, "missing operand")
	var parents: bool = opts.flags.has("p") or opts.flags.has("parents")
	var code := 0
	for d in opts.operands:
		var res := ctx.vfs().make_dir(ctx.resolve(d), ctx.access(), parents, ctx.session.dir_create_mode())
		if not res.ok:
			code = ctx.fail("cannot create directory '%s'" % d, res.error)
		elif opts.flags.has("v"):
			ctx.out("mkdir: created directory '%s'\n" % d)
	return code
