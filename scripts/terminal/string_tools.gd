class_name StringTools
extends RefCounted
## Text helpers shared by commands, the parser and the UI.


## Optimal-string-alignment distance: Levenshtein plus adjacent transpositions,
## so "sl" is one edit away from "ls".
static func edit_distance(a: String, b: String) -> int:
	if a == b:
		return 0
	if a.is_empty():
		return b.length()
	if b.is_empty():
		return a.length()
	var d: Array = []
	for i in a.length() + 1:
		var row: Array = []
		row.resize(b.length() + 1)
		row[0] = i
		d.append(row)
	for j in b.length() + 1:
		d[0][j] = j
	for i in range(1, a.length() + 1):
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			var best: int = mini(mini(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				best = mini(best, d[i - 2][j - 2] + 1)
			d[i][j] = best
	return d[a.length()][b.length()]


static func shared_prefix_length(a: String, b: String) -> int:
	var n := mini(a.length(), b.length())
	for i in n:
		if a[i] != b[i]:
			return i
	return n


## Splits text into lines, dropping the empty string after a trailing newline.
static func lines(text: String) -> Array:
	if text == "":
		return []
	var parts := Array(text.split("\n"))
	if text.ends_with("\n"):
		parts.pop_back()
	return parts


static func join_lines(items: Array) -> String:
	if items.is_empty():
		return ""
	return "\n".join(PackedStringArray(items)) + "\n"


static func human_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes)
	var units := ["K", "M", "G", "T"]
	var value := float(bytes)
	var idx := -1
	while value >= 1024.0 and idx < units.size() - 1:
		value /= 1024.0
		idx += 1
	return ("%.1f%s" % [value, units[idx]]) if value < 10.0 else ("%d%s" % [int(ceil(value)), units[idx]])


## Escapes BBCode for RichTextLabel.
static func bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func common_prefix(items: Array) -> String:
	if items.is_empty():
		return ""
	var prefix: String = items[0]
	for item in items:
		var s: String = item
		while not s.begins_with(prefix):
			prefix = prefix.substr(0, prefix.length() - 1)
	return prefix
