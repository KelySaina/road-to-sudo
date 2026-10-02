class_name Completer
extends RefCounted
## Tab completion for the prompt: command names in command position,
## VFS paths everywhere else, :meta commands after a colon.
## Returns {"line": String, "candidates": Array} — candidates are shown
## when the completion is ambiguous (bash's double-Tab list).

const META_WORDS := [":hint", ":solution", ":objective", ":reset", ":skip", ":next", ":stats", ":save", ":menu"]
const SEPARATORS := ["|", ";", "&", ">", "<", " "]


static func complete(line: String, session: ShellSession, registry: CommandRegistry) -> Dictionary:
	var start := 0
	for sep in SEPARATORS:
		start = maxi(start, line.rfind(sep) + 1)
	var prefix := line.substr(0, start)
	var word := line.substr(start)
	var before := prefix.strip_edges()
	var command_position := before == "" or before.ends_with("|") or before.ends_with(";") or before.ends_with("&") or before == "sudo" or before.ends_with(" sudo") or before == "man" or before == "which"

	var candidates: Array = []
	if word.begins_with(":") and before == "":
		for m in META_WORDS:
			if m.begins_with(word):
				candidates.append(m)
	elif command_position and not word.contains("/") and not word.begins_with(".") and not word.begins_with("~"):
		for n in registry.all_names():
			if n.begins_with(word):
				candidates.append(n)
	else:
		candidates = _paths(word, session)

	if candidates.is_empty():
		return {"line": line, "candidates": []}
	if candidates.size() == 1:
		var only: String = candidates[0]
		return {"line": prefix + only + ("" if only.ends_with("/") else " "), "candidates": []}
	var common := StringTools.common_prefix(candidates)
	if common.length() > word.length():
		return {"line": prefix + common, "candidates": []}
	var shown: Array = []
	for c in candidates:
		var s: String = c
		shown.append(s.trim_suffix("/").get_file() + ("/" if s.ends_with("/") else "") if s.contains("/") else s)
	return {"line": line, "candidates": shown}


static func _paths(word: String, session: ShellSession) -> Array:
	var slash := word.rfind("/")
	var dir_part := word.substr(0, slash + 1)
	var base := word.substr(slash + 1)
	var dir_expanded := Expander.expand_tilde(dir_part, session) if dir_part != "" else "."
	var dir_abs := session.resolve(dir_expanded)
	var node := session.machine.vfs.get_node_at(dir_abs)
	var out: Array = []
	if node == null or not node.is_dir() or not Permissions.can(node, session.access(), Permissions.READ):
		return out
	for child_name in node.sorted_child_names():
		var n: String = child_name
		if not n.begins_with(base):
			continue
		if n.begins_with(".") and not base.begins_with("."):
			continue
		var child: VFSNode = node.children[n]
		out.append(dir_part + n + ("/" if child.is_dir() else ""))
	return out


## One-line inline help for Beginner mode: what the first word would run.
static func describe(line: String, registry: CommandRegistry) -> String:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty() or line.begins_with(":"):
		return ""
	var first: String = words[0]
	if registry.has(first):
		var cmd := registry.get_command(first)
		return "%s — %s" % [I18n.t(cmd.get_usage()), I18n.t(cmd.get_summary())]
	if words.size() == 1 and first.length() >= 1:
		var matches: Array = []
		for n in registry.primary_names():
			if n.begins_with(first):
				matches.append(n)
		if matches.size() > 0 and matches.size() <= 6:
			return "Tab ⇥  " + "  ".join(PackedStringArray(matches))
	return ""
