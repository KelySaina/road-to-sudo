class_name CutCommand
extends BaseCommand


func get_command_name() -> String: return "cut"
func get_category() -> String: return "text"
func get_summary() -> String: return "extract columns from each line"
func get_usage() -> String: return "cut -d DELIM -f LIST [FILE...]  |  cut -c LIST [FILE...]"
func get_manual() -> String:
	return "Keeps only some fields of each line.\n  -d ':' -f 1      first field, fields separated by ':'  (cut -d: -f1 /etc/passwd)\n  -f 2,4 / -f 2-4 / -f 3-   several fields or ranges\n  -c 1-8           characters instead of fields"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args(), "dfc")
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var delim: String = opts.values.get("d", "\t")
	if delim.length() != 1:
		return ctx.fail("", "the delimiter must be a single character")
	var by_chars: bool = opts.values.has("c")
	var list_text: String = opts.values.get("c", opts.values.get("f", ""))
	if list_text == "":
		return usage_error(ctx, "you must specify a list of bytes, characters, or fields")
	var read := ctx.read_sources(opts.operands)
	for src in read.sources:
		for line in StringTools.lines(src.content):
			if by_chars:
				var picked := ""
				for idx in _indices(list_text, line.length()):
					picked += line[idx]
				ctx.out(picked + "\n")
			else:
				if not line.contains(delim):
					ctx.out(line + "\n")
					continue
				var parts: PackedStringArray = str(line).split(delim)
				var picked: Array = []
				for idx in _indices(list_text, parts.size()):
					picked.append(parts[idx])
				ctx.out(delim.join(PackedStringArray(picked)) + "\n")
	return 1 if read.failed else 0


## "1,3-4,6-" -> zero-based indices below `size`.
func _indices(list_text: String, size: int) -> Array:
	var out: Array = []
	for part in list_text.split(","):
		var a := 1
		var b := size
		if part.contains("-"):
			var ab := part.split("-")
			a = int(ab[0]) if ab[0] != "" else 1
			b = int(ab[1]) if ab.size() > 1 and ab[1] != "" else size
		else:
			a = int(part)
			b = a
		for i in range(maxi(a, 1), mini(b, size) + 1):
			if not out.has(i - 1):
				out.append(i - 1)
	out.sort()
	return out
