class_name CatCommand
extends BaseCommand


func get_command_name() -> String: return "cat"
func get_category() -> String: return "files"
func get_summary() -> String: return "print file contents"
func get_usage() -> String: return "cat [-n] [FILE...]"
func get_manual() -> String:
	return "Concatenates files to standard output. With no FILE, reads standard input,\nso it works at the end of a pipe too.  -n numbers the lines."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var read := ctx.read_sources(opts.operands)
	var number: bool = opts.flags.has("n")
	var line_no := 1
	for src in read.sources:
		var text: String = src.content
		if number:
			for line in StringTools.lines(text):
				ctx.out("%6d\t%s\n" % [line_no, line])
				line_no += 1
		else:
			ctx.out(text)
		if src.name != "-":
			ctx.emit("file_read", {"path": ctx.resolve(src.name)})
	return 1 if read.failed else 0
