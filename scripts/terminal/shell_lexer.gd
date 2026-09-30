class_name ShellLexer
extends RefCounted
## Turns a command line into tokens. Words keep their quoting as segments so
## the expander knows what may be expanded:
##   {"type": "word", "segments": [{"t": "text", "q": QUOTE_NONE}]}
##   {"type": "op", "value": "|"}

const QUOTE_NONE := 0
const QUOTE_DOUBLE := 1
const QUOTE_SINGLE := 2

const OPERATORS := ["2>&1", ">&2", "2>>", "2>", ">>", "||", "&&", "|", "&", ";", ">", "<"]


static func tokenize(line: String) -> Dictionary:
	var tokens: Array = []
	var segments: Array = []
	var current := ""
	var i := 0
	var n := line.length()

	while i < n:
		var c := line[i]

		if c == "'":
			var end := line.find("'", i + 1)
			if end == -1:
				return {"tokens": [], "error": "unexpected end of line while looking for matching `''"}
			_flush_plain(segments, current)
			current = ""
			segments.append({"t": line.substr(i + 1, end - i - 1), "q": QUOTE_SINGLE})
			i = end + 1
			continue

		if c == "\"":
			_flush_plain(segments, current)
			current = ""
			var buf := ""
			i += 1
			var closed := false
			while i < n:
				var d := line[i]
				if d == "\\" and i + 1 < n and "\"\\$`".contains(line[i + 1]):
					buf += line[i + 1] if line[i + 1] != "$" else "\\$"
					i += 2
					continue
				if d == "\"":
					closed = true
					i += 1
					break
				buf += d
				i += 1
			if not closed:
				return {"tokens": [], "error": "unexpected end of line while looking for matching `\"'"}
			segments.append({"t": buf, "q": QUOTE_DOUBLE})
			continue

		if c == "\\":
			if i + 1 < n:
				_flush_plain(segments, current)
				current = ""
				segments.append({"t": line[i + 1], "q": QUOTE_SINGLE})
				i += 2
			else:
				i += 1
			continue

		if c == " " or c == "\t":
			_flush_plain(segments, current)
			current = ""
			_flush_word(tokens, segments)
			segments = []
			i += 1
			continue

		# A comment starts only at the beginning of a word.
		if c == "#" and current == "" and segments.is_empty():
			break

		var op := _match_operator(line, i, current == "" and segments.is_empty())
		if op != "":
			_flush_plain(segments, current)
			current = ""
			_flush_word(tokens, segments)
			segments = []
			tokens.append({"type": "op", "value": op})
			i += op.length()
			continue

		current += c
		i += 1

	_flush_plain(segments, current)
	_flush_word(tokens, segments)
	return {"tokens": tokens, "error": ""}


static func _match_operator(line: String, i: int, at_word_start: bool) -> String:
	for op in OPERATORS:
		# "2>" only counts as an fd redirect when "2" starts a word.
		if op.begins_with("2") and not at_word_start:
			continue
		if line.substr(i, op.length()) == op:
			return op
	return ""


static func _flush_plain(segments: Array, text: String) -> void:
	if text != "":
		segments.append({"t": text, "q": QUOTE_NONE})


static func _flush_word(tokens: Array, segments: Array) -> void:
	if not segments.is_empty():
		tokens.append({"type": "word", "segments": segments.duplicate()})


static func word_text(word: Dictionary) -> String:
	var out := ""
	for s in word.segments:
		out += s.t
	return out
