class_name TrCommand
extends BaseCommand


func get_command_name() -> String: return "tr"
func get_category() -> String: return "text"
func get_summary() -> String: return "translate or delete characters"
func get_usage() -> String: return "tr [-d] SET1 [SET2]"
func get_manual() -> String:
	return "Reads stdin only.  tr a-z A-Z  uppercases,  tr -d '\\r'  deletes characters,\ntr ' ' '\\n'  puts every word on its own line."


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var ops: Array = opts.operands
	var delete: bool = opts.flags.has("d")
	if ops.is_empty() or (not delete and ops.size() < 2):
		return usage_error(ctx, "missing operand")
	var set1 := _expand(ops[0])
	var set2 := _expand(ops[1]) if ops.size() > 1 else ""
	var out := ""
	for i in ctx.stdin.length():
		var c := ctx.stdin[i]
		var idx := set1.find(c)
		if idx == -1:
			out += c
		elif not delete:
			out += set2[mini(idx, set2.length() - 1)] if set2 != "" else c
	ctx.out(out)
	return 0


static func _expand(set_text: String) -> String:
	var s := set_text.replace("\\n", "\n").replace("\\t", "\t").replace("\\r", "\r")
	s = s.replace("[:upper:]", "A-Z").replace("[:lower:]", "a-z").replace("[:digit:]", "0-9").replace("[:space:]", " \t\n")
	var out := ""
	var i := 0
	while i < s.length():
		if i + 2 < s.length() and s[i + 1] == "-":
			for code in range(s.unicode_at(i), s.unicode_at(i + 2) + 1):
				out += String.chr(code)
			i += 3
		else:
			out += s[i]
			i += 1
	return out
