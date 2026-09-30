class_name HeadCommand
extends BaseCommand


func get_command_name() -> String: return "head"
func get_category() -> String: return "text"
func get_summary() -> String: return "print the first lines of files"
func get_usage() -> String: return "head [-n N] [FILE...]"
func get_manual() -> String:
	return "Prints the first 10 lines (or N with -n N, or -N). Reads stdin when no file is given:\n  sort names.txt | head -n 3"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(normalize_count_args(ctx.args()), "nc", ["lines"])
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var count_text: String = opts.values.get("n", opts.values.get("lines", "10"))
	if not count_text.is_valid_int():
		return ctx.fail("", "invalid number of lines: '%s'" % count_text)
	var count := int(count_text)
	var read := ctx.read_sources(opts.operands)
	var multi: bool = read.sources.size() > 1
	for i in read.sources.size():
		var src: Dictionary = read.sources[i]
		if multi:
			ctx.out("%s==> %s <==\n" % ["\n" if i > 0 else "", src.name], "dim")
		ctx.out(StringTools.join_lines(select(StringTools.lines(src.content), count)))
	return 1 if read.failed else 0


func select(lines: Array, count: int) -> Array:
	return lines.slice(0, count) if count >= 0 else lines.slice(0, maxi(0, lines.size() + count))


## Turns the old-style "-5" into "-n 5".
static func normalize_count_args(args: Array) -> Array:
	var out: Array = []
	for a in args:
		var s: String = a
		if s.length() > 1 and s.begins_with("-") and s.substr(1).is_valid_int():
			out.append("-n")
			out.append(s.substr(1))
		else:
			out.append(s)
	return out
