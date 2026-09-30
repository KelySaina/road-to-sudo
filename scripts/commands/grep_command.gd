class_name GrepCommand
extends BaseCommand


func get_command_name() -> String: return "grep"
func get_aliases() -> Array: return ["egrep"]
func get_category() -> String: return "text"
func get_summary() -> String: return "print lines matching a pattern"
func get_usage() -> String: return "grep [-i] [-v] [-n] [-c] [-l] [-r] [-w] [-o] [-F] PATTERN [FILE...]"
func get_manual() -> String:
	return """Searches text for PATTERN (a regular expression) and prints matching lines.
  -i  ignore case            -v  invert: print lines that do NOT match
  -n  show line numbers      -c  count matching lines
  -l  list matching files    -r  search directories recursively
  -w  whole words only       -o  print only the matching part
  -F  fixed string, not a regex
With no FILE, grep reads stdin:   cat auth.log | grep Failed"""


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args(), "eA", ["regexp"])
	if opts.error != "":
		return usage_error(ctx, opts.error)
	var f: Dictionary = opts.flags
	var operands: Array = opts.operands
	var pattern: String
	if opts.values.has("e") or opts.values.has("regexp"):
		pattern = opts.values.get("e", opts.values.get("regexp", ""))
	elif operands.is_empty():
		return usage_error(ctx)
	else:
		pattern = operands.pop_front()

	var ignore_case := f.has("i") or f.has("ignore-case")
	var regex := RegEx.new()
	var source := escape_regex(pattern) if f.has("F") else _bre_to_pcre(pattern)
	if f.has("w"):
		source = "\\b(?:" + source + ")\\b"
	if ignore_case:
		source = "(?i)" + source
	if regex.compile(source) != OK:
		return ctx.fail("", "Invalid regular expression", 2)

	var recursive := f.has("r") or f.has("R") or f.has("recursive")
	if recursive and operands.is_empty():
		operands = ["."]
	var sources: Array = []
	var failed := false
	if recursive:
		for op in operands:
			var start := ctx.resolve(op)
			if not ctx.vfs().exists(start):
				failed = true
				ctx.fail(op, VirtualFileSystem.ENOENT)
				continue
			var walked := ctx.vfs().walk(start, ctx.access())
			for path in walked.paths:
				var node := ctx.vfs().get_node_at(path)
				if node.is_dir() or node.content.begins_with("\u007fELF"):
					continue
				var shown := FindCommand.new()._display_path(op, start, path)
				var res := ctx.vfs().read_file(path, ctx.access())
				if res.ok:
					sources.append({"name": shown, "content": res.value})
				else:
					failed = true
					ctx.fail(shown, res.error)
			for d in walked.denied:
				failed = true
				ctx.fail(d, VirtualFileSystem.EACCES)
	else:
		var read := ctx.read_sources(operands)
		sources = read.sources
		failed = read.failed

	var show_names: bool = (sources.size() > 1 or recursive) and not f.has("h")
	var any_match := false
	for src in sources:
		var count := 0
		var lines := StringTools.lines(src.content)
		for idx in lines.size():
			var line: String = lines[idx]
			var matches := regex.search_all(line)
			var hit := not matches.is_empty()
			if f.has("v") or f.has("invert-match"):
				hit = not hit
			if not hit:
				continue
			count += 1
			any_match = true
			if f.has("q") or f.has("c") or f.has("l"):
				continue
			var prefix := ""
			if show_names:
				prefix += src.name + ":"
			if f.has("n"):
				prefix += str(idx + 1) + ":"
			if f.has("o") and not f.has("v"):
				for m in matches:
					ctx.out(prefix, "path")
					ctx.out(m.get_string() + "\n", "match")
				continue
			ctx.out(prefix, "path")
			_print_highlighted(ctx, line, matches if not f.has("v") else [])
		if f.has("c"):
			ctx.out(("%s:%d\n" % [src.name, count]) if show_names else ("%d\n" % count))
		elif f.has("l") and count > 0:
			ctx.out(src.name + "\n", "path")
	ctx.emit("grep_used", {"pattern": pattern, "matched": any_match})
	if failed and not any_match:
		return 2
	return 0 if any_match else 1


func _print_highlighted(ctx: CommandContext, line: String, matches: Array) -> void:
	var last := 0
	for m in matches:
		if m.get_end() == m.get_start():
			continue
		ctx.out(line.substr(last, m.get_start() - last))
		ctx.out(m.get_string(), "match")
		last = m.get_end()
	ctx.out(line.substr(last) + "\n")


## Basic regular expressions use \| \( \) \+ where PCRE uses | ( ) +.
static func _bre_to_pcre(pattern: String) -> String:
	return pattern.replace("\\|", "|")


static func escape_regex(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		if "\\.^$|?*+()[]{}".contains(c):
			out += "\\"
		out += c
	return out
