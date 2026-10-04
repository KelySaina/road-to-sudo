class_name ReturnCommand
extends BaseCommand


func get_command_name() -> String: return "return"
func get_category() -> String: return "shell"
func get_summary() -> String: return "return from a shell function with a status"


func execute(ctx: CommandContext) -> int:
	# `return` only makes sense inside a function body; bash errors otherwise.
	if ctx.session.function_depth <= 0:
		ctx.err("return: can only `return' from a function or sourced script\n")
		return 1
	var code := ctx.session.last_exit_code
	if not ctx.args().is_empty():
		var arg := str(ctx.args()[0])
		if not arg.is_valid_int():
			ctx.err("return: %s: numeric argument required\n" % arg)
			return 2
		code = int(arg)
	# Request the unwind; the interpreter stops the body at the next checkpoint and
	# _run_function consumes this, so the status becomes the function's exit code.
	ctx.session.return_requested = code
	return code
