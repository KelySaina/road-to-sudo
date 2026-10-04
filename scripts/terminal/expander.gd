class_name Expander
extends RefCounted
## Word expansion, in shell order: tilde -> variables -> globbing.
## Single-quoted text is literal; double-quoted text expands variables only.

static var _var_regex: RegEx


static func expand_words(words: Array, session: ShellSession) -> Array:
	var out: Array = []
	for w in words:
		out.append_array(expand_word(w, session))
	return out


static func expand_word(word: Dictionary, session: ShellSession) -> Array:
	var text := ""
	var globbable := false
	var segs: Array = word.segments
	for idx in segs.size():
		var s: Dictionary = segs[idx]
		var piece: String = s.t
		if s.q == ShellLexer.QUOTE_SINGLE:
			text += piece
			continue
		if s.q == ShellLexer.QUOTE_NONE and idx == 0:
			piece = expand_tilde(piece, session)
		piece = expand_variables(piece, session)
		if s.q == ShellLexer.QUOTE_DOUBLE:
			piece = piece.replace("\\$", "$")
		if s.q == ShellLexer.QUOTE_NONE and (piece.contains("*") or piece.contains("?") or (piece.contains("[") and piece.contains("]"))):
			globbable = true
		text += piece

	# An unquoted word that expands to nothing disappears ($EMPTY).
	if text == "" and segs.size() == 1 and segs[0].q == ShellLexer.QUOTE_NONE:
		return []
	if globbable:
		var matches := glob(text, session)
		if not matches.is_empty():
			return matches
	return [text]


static func expand_tilde(text: String, session: ShellSession) -> String:
	if not text.begins_with("~"):
		return text
	var slash := text.find("/")
	var who := text.substr(1, slash - 1) if slash != -1 else text.substr(1)
	var rest := text.substr(slash) if slash != -1 else ""
	if who == "":
		return session.home() + rest
	if session.machine.has_user(who):
		return session.machine.home_of(who) + rest
	return text


static func expand_variables(text: String, session: ShellSession) -> String:
	if not text.contains("$"):
		return text
	if _var_regex == null:
		_var_regex = RegEx.new()
		_var_regex.compile("(?<!\\\\)\\$(\\{([A-Za-z_][A-Za-z0-9_]*)\\}|([A-Za-z_][A-Za-z0-9_]*)|([?$#@0-9]))")
	var out := ""
	var last := 0
	for m in _var_regex.search_all(text):
		out += text.substr(last, m.get_start() - last)
		var var_name := m.get_string(2)
		if var_name == "":
			var_name = m.get_string(3)
		if var_name == "":
			var_name = m.get_string(4)
		out += session.get_variable(var_name)
		last = m.get_end()
	out += text.substr(last)
	return out


## Expands a glob pattern against the VFS, component by component.
## Shell glob match for a single path component: * ? and [abc] / [a-z] classes
## (and [!abc] negation). Shared by filename globbing and case patterns.
static func fnmatch(pattern: String, name: String) -> bool:
	var rx := "^"
	var i := 0
	var n := pattern.length()
	while i < n:
		var c := pattern[i]
		match c:
			"*": rx += ".*"
			"?": rx += "."
			"[":
				var close := pattern.find("]", i + 1)
				if close == -1:
					rx += "\\["
				else:
					var cls := pattern.substr(i + 1, close - (i + 1))
					if cls.begins_with("!"):
						cls = "^" + cls.substr(1)
					rx += "[" + cls + "]"
					i = close
			_:
				if c in [".", "+", "(", ")", "{", "}", "^", "$", "\\", "|"]:
					rx += "\\" + c
				else:
					rx += c
		i += 1
	rx += "$"
	var re := RegEx.create_from_string(rx)
	return re != null and re.search(name) != null


static func glob(pattern: String, session: ShellSession) -> Array:
	var absolute := pattern.begins_with("/")
	var parts := pattern.split("/", false)
	var bases: Array = ["/" if absolute else ""]
	for p in parts:
		var next_bases: Array = []
		var has_wild := p.contains("*") or p.contains("?") or (p.contains("[") and p.contains("]"))
		for base in bases:
			if not has_wild:
				next_bases.append(_join_rel(base, p))
				continue
			var dir_abs := session.resolve(base if base != "" else ".")
			var node := session.machine.vfs.get_node_at(dir_abs)
			if node == null or not node.is_dir():
				continue
			if not Permissions.can(node, session.access(), Permissions.READ):
				continue
			for child_name in node.sorted_child_names():
				if child_name.begins_with(".") and not p.begins_with("."):
					continue
				if fnmatch(p, child_name):
					next_bases.append(_join_rel(base, child_name))
		bases = next_bases
		if bases.is_empty():
			return []
	var existing: Array = []
	for b in bases:
		if session.machine.vfs.exists(session.resolve(b)):
			existing.append(b)
	existing.sort()
	return existing


static func _join_rel(base: String, name: String) -> String:
	if base == "":
		return name
	if base == "/":
		return "/" + name
	return base + "/" + name
