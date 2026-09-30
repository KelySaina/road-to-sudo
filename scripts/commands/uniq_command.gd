class_name UniqCommand
extends BaseCommand


func get_command_name() -> String: return "uniq"
func get_category() -> String: return "text"
func get_summary() -> String: return "collapse adjacent duplicate lines"
func get_usage() -> String: return "uniq [-c] [-d] [-u] [-i] [FILE]"
func get_manual() -> String:
	return "Removes ADJACENT duplicate lines — so you usually sort first.\n  -c  prefix each line with how many times it occurred\n  -d  only print duplicated lines\n  -u  only print unique lines"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var f: Dictionary = opts.flags
	var read := ctx.read_sources(opts.operands.slice(0, 1))
	var lines := StringTools.lines(read.sources[0].content) if not read.sources.is_empty() else []
	var groups: Array = []
	for l in lines:
		var key: String = l.to_lower() if f.has("i") else l
		if not groups.is_empty() and groups[-1].key == key:
			groups[-1].count += 1
		else:
			groups.append({"key": key, "line": l, "count": 1})
	for g in groups:
		if f.has("d") and g.count < 2:
			continue
		if f.has("u") and g.count > 1:
			continue
		ctx.out(("%7d %s\n" % [g.count, g.line]) if f.has("c") else (g.line + "\n"))
	return 1 if read.failed else 0
