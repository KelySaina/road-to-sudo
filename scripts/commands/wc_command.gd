class_name WcCommand
extends BaseCommand


func get_command_name() -> String: return "wc"
func get_category() -> String: return "text"
func get_summary() -> String: return "count lines, words and bytes"
func get_usage() -> String: return "wc [-l] [-w] [-c] [FILE...]"
func get_manual() -> String:
	return "Counts newlines (-l), words (-w) and bytes (-c). The classic question\n'how many X?' is almost always answered by  ... | wc -l"


func execute(ctx: CommandContext) -> int:
	var opts := parse_options(ctx.args())
	var f: Dictionary = opts.flags
	var want := {"l": f.has("l") or f.has("lines"), "w": f.has("w") or f.has("words"), "c": f.has("c") or f.has("bytes") or f.has("m")}
	if not (want.l or want.w or want.c):
		want = {"l": true, "w": true, "c": true}
	var read := ctx.read_sources(opts.operands)
	var rows: Array = []
	var total := {"l": 0, "w": 0, "c": 0}
	for src in read.sources:
		var text: String = src.content
		var counts := {"l": text.count("\n"), "w": _word_count(text), "c": text.to_utf8_buffer().size()}
		for k in total:
			total[k] += counts[k]
		rows.append({"counts": counts, "name": "" if src.name == "-" else src.name})
	if rows.size() > 1:
		rows.append({"counts": total, "name": "total"})
	var single_col: bool = [want.l, want.w, want.c].count(true) == 1 and rows.size() == 1
	for r in rows:
		var parts: Array = []
		for k in ["l", "w", "c"]:
			if want[k]:
				parts.append(str(r.counts[k]) if single_col else str(r.counts[k]).lpad(7))
		var line := " ".join(PackedStringArray(parts))
		if r.name != "":
			line += " " + r.name
		ctx.out(line + "\n")
	return 1 if read.failed else 0


func _word_count(text: String) -> int:
	var n := 0
	for w in text.replace("\t", " ").replace("\n", " ").split(" ", false):
		n += 1
	return n
