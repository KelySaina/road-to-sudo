class_name TailCommand
extends BaseCommand


func get_command_name() -> String: return "tail"
func get_category() -> String: return "text"
func get_summary() -> String: return "print the last lines of files"
func get_usage() -> String: return "tail [-n N | -n +N] [FILE...]"
func get_manual() -> String:
	return "Prints the last 10 lines (or N). `-n +N` starts at line N instead.\nLogs grow at the bottom, so tail is usually the first look at a log file.\n(-f, follow, is not simulated yet.)"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(HeadCommand.normalize_count_args(ctx.args()), "n", ["lines"])
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var count_text: String = opts.values.get("n", opts.values.get("lines", "10"))
	var from_start := count_text.begins_with("+")
	var num := count_text.trim_prefix("+")
	if not num.is_valid_int():
		return ctx.fail("", "invalid number of lines: '%s'" % count_text)
	var count := int(num)
	var read := ctx.read_sources(opts.operands)
	var multi: bool = read.sources.size() > 1
	for i in read.sources.size():
		var src: Dictionary = read.sources[i]
		if multi:
			ctx.out("%s==> %s <==\n" % ["\n" if i > 0 else "", src.name], "dim")
		var lines := StringTools.lines(src.content)
		var selected: Array = lines.slice(maxi(0, count - 1)) if from_start else lines.slice(maxi(0, lines.size() - count))
		ctx.out(StringTools.join_lines(selected))
	return 1 if read.failed else 0
