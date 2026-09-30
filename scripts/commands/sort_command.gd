class_name SortCommand
extends BaseCommand


func get_command_name() -> String: return "sort"
func get_category() -> String: return "text"
func get_summary() -> String: return "sort lines of text"
func get_usage() -> String: return "sort [-r] [-n] [-u] [-f] [-k N] [-t SEP] [FILE...]"
func get_manual() -> String:
	return "Sorts lines alphabetically.  -n numeric, -r reverse, -u unique, -f ignore case,\n-k N sort by the Nth field (-t sets the separator).\nClassic combo:  sort | uniq -c | sort -rn"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args(), "kt")
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var f: Dictionary = opts.flags
	var read := ctx.read_sources(opts.operands)
	var lines: Array = []
	for src in read.sources:
		lines.append_array(StringTools.lines(src.content))
	var key_field := int(str(opts.values.get("k", "0")).split(",")[0])
	var sep: String = opts.values.get("t", "")
	var numeric: bool = f.has("n")
	var fold: bool = f.has("f")
	var keyed: Array = []
	for l in lines:
		keyed.append([_key(l, key_field, sep, numeric, fold), l])
	keyed.sort_custom(func(a, b):
		if a[0] == b[0]:
			return a[1] < b[1]
		return a[0] < b[0])
	var out: Array = []
	for k in keyed:
		out.append(k[1])
	if f.has("r"):
		out.reverse()
	if f.has("u"):
		var seen := {}
		var uniq: Array = []
		for l in out:
			if not seen.has(l):
				seen[l] = true
				uniq.append(l)
		out = uniq
	ctx.out(StringTools.join_lines(out))
	return 1 if read.failed else 0


func _key(line: String, field: int, sep: String, numeric: bool, fold: bool) -> Variant:
	var text := line
	if field > 0:
		var parts := line.split(sep, false) if sep != "" else line.strip_edges().split(" ", false)
		text = parts[field - 1] if field - 1 < parts.size() else ""
	if numeric:
		var t := text.strip_edges()
		return t.to_float() if t.is_valid_float() else 0.0
	return text.to_lower() if fold else text
