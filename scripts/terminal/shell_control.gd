class_name ShellControl
extends RefCounted
## Bash control flow: for / while / until / if. Parses a compound command by
## scanning its top-level words (quotes and $(...) are opaque), then runs the
## inner command lists through the shell's normal path — so pipes, redirects and
## nesting all work, and every body is just ordinary commands.

const OPENERS := ["for", "while", "until", "if", "case"]
const CLOSERS := ["done", "fi", "esac"]
const MAX_ITERATIONS := 100000  # a guard so a runaway loop can't hang the game


static func is_compound_start(word: String) -> bool:
	return word in OPENERS


## Net open-block depth of a chunk: openers (for/while/until/if) raise it,
## done/fi lower it. >0 means a block was opened but not yet closed (so a script
## should keep reading lines). Used to accumulate multi-line blocks.
static func block_depth(text: String) -> int:
	var depth := 0
	for w in scan(text):
		if w.sep:
			continue
		if w.text in OPENERS or w.text == "{":
			depth += 1
		elif w.text in CLOSERS or w.text == "}":
			depth -= 1
	return depth


## Splits a line into top-level statements on ';' and newline, but never inside
## a for/while/if block or inside quotes / $(...). Each returned statement is
## trimmed and non-empty, and may still contain pipes and && / ||.
static func split_statements(line: String) -> Array:
	var out: Array = []
	var depth := 0
	var seg_start := 0
	for w in scan(line):
		if w.sep:
			if depth <= 0:
				var stmt := line.substr(seg_start, w.start - seg_start).strip_edges()
				if stmt != "":
					out.append(stmt)
				seg_start = w.end
				depth = 0
			continue
		if w.text in OPENERS or w.text == "{":
			depth += 1
		elif w.text in CLOSERS or w.text == "}":
			depth -= 1
	var last := line.substr(seg_start).strip_edges()
	if last != "":
		out.append(last)
	return out


## The first bare word of a line (for compound detection), or "".
static func first_word(line: String) -> String:
	var words := scan(line)
	for w in words:
		if not w.sep:
			return w.text
	return ""


## Top-level word scan. Returns [{text, start, end, sep}]. Whitespace splits
## words; ';' and newline are separators; single/double quotes, $(...) and
## backticks are consumed whole (so keywords inside them don't count).
static func scan(line: String) -> Array:
	var out: Array = []
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == " " or c == "\t":
			i += 1
			continue
		if c == ";" or c == "\n":
			out.append({"text": ";", "start": i, "end": i + 1, "sep": true})
			i += 1
			continue
		var start := i
		while i < n:
			var d := line[i]
			if d == " " or d == "\t" or d == ";" or d == "\n":
				break
			if d == "'":
				var e := line.find("'", i + 1)
				i = (e + 1) if e != -1 else n
				continue
			if d == "\"":
				i = _skip_double(line, i + 1, n)
				continue
			if d == "`":
				var b := line.find("`", i + 1)
				i = (b + 1) if b != -1 else n
				continue
			if d == "$" and i + 1 < n and line[i + 1] == "(":
				i = _skip_parens(line, i + 2, n)
				continue
			if d == "\\" and i + 1 < n:
				i += 2
				continue
			i += 1
		out.append({"text": line.substr(start, i - start), "start": start, "end": i, "sep": false})
	return out


static func _skip_double(line: String, i: int, n: int) -> int:
	while i < n:
		if line[i] == "\\" and i + 1 < n:
			i += 2
			continue
		if line[i] == "\"":
			return i + 1
		i += 1
	return n


static func _skip_parens(line: String, i: int, n: int) -> int:
	var depth := 1
	while i < n and depth > 0:
		var c := line[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
		elif c == "'":
			var e := line.find("'", i + 1)
			i = (e) if e != -1 else n - 1
		i += 1
	return i


## Runs a compound command. Bodies and conditions go back through
## shell.run_into, so they can be pipelines, chains, or further compounds.
static func run(shell, line: String, outcome, depth: int, parent) -> void:
	var words := _non_sep(scan(line))
	if words.is_empty():
		return
	match words[0].text:
		"for": _run_for(shell, line, words, outcome, depth, parent)
		"while", "until": _run_while(shell, line, words, words[0].text == "until", outcome, depth, parent)
		"if": _run_if(shell, line, words, outcome, depth, parent)
		"case": _run_case(shell, line, words, outcome, depth, parent)
		_: shell.run_into(line, outcome, depth, parent)


static func _non_sep(words: Array) -> Array:
	var out: Array = []
	for w in words:
		if not w.sep:
			out.append(w)
	return out


# --- for NAME in ITEMS; do BODY; done ---------------------------------------

static func _run_for(shell, line: String, words: Array, outcome, depth: int, parent) -> void:
	if words.size() < 4 or not str(words[1].text).is_valid_identifier() or words[2].text != "in":
		return _syntax(shell, outcome, "for")
	var name: String = words[1].text
	var do_idx := _find_keyword(words, 3, "do")
	if do_idx == -1:
		return _syntax(shell, outcome, "do")
	var done_idx := _match(words, do_idx, "do", "done")
	if done_idx == -1:
		return _syntax(shell, outcome, "done")
	var items_str := line.substr(words[2].end, words[do_idx].start - words[2].end)
	var body := line.substr(words[do_idx].end, words[done_idx].start - words[do_idx].end)
	if items_str.contains("$(") or items_str.contains("`"):
		items_str = shell._expand_command_subst(items_str, outcome, depth, parent)
	var items := _expand_items(items_str, shell.session)
	var count := 0
	for value in items:
		shell.session.env[name] = value
		shell.run_into(body, outcome, depth, parent)
		if shell.session.exit_requested >= 0:
			return
		count += 1
		if count > MAX_ITERATIONS:
			break


# --- while/until COND; do BODY; done ----------------------------------------

static func _run_while(shell, line: String, words: Array, is_until: bool, outcome, depth: int, parent) -> void:
	var do_idx := _find_keyword(words, 1, "do")
	if do_idx == -1:
		return _syntax(shell, outcome, "do")
	var done_idx := _match(words, do_idx, "do", "done")
	if done_idx == -1:
		return _syntax(shell, outcome, "done")
	var cond := line.substr(words[0].end, words[do_idx].start - words[0].end)
	var body := line.substr(words[do_idx].end, words[done_idx].start - words[do_idx].end)
	var count := 0
	while true:
		shell.run_into(cond, outcome, depth, parent)
		var ok: bool = shell.session.last_exit_code == 0
		if is_until:
			ok = not ok
		if not ok:
			break
		shell.run_into(body, outcome, depth, parent)
		if shell.session.exit_requested >= 0:
			return
		count += 1
		if count > MAX_ITERATIONS:
			shell.session.last_exit_code = 1
			break


# --- if COND; then BODY; [elif ...; then ...;] [else ...;] fi ----------------

static func _run_if(shell, line: String, words: Array, outcome, depth: int, parent) -> void:
	var fi_idx := _match(words, 0, "if", "fi")
	if fi_idx == -1:
		return _syntax(shell, outcome, "fi")
	var clause := 0            # index of the current 'if' or 'elif'
	var handled := false
	while clause < fi_idx:
		var then_idx := _next_at_level(words, clause + 1, fi_idx, ["then"])
		if then_idx >= fi_idx:
			return _syntax(shell, outcome, "then")
		var boundary := _next_at_level(words, then_idx + 1, fi_idx, ["elif", "else"])
		if not handled:
			var cond := line.substr(words[clause].end, words[then_idx].start - words[clause].end)
			shell.run_into(cond, outcome, depth, parent)
			if shell.session.last_exit_code == 0:
				handled = true
				var body_end: int = words[boundary].start if boundary < fi_idx else words[fi_idx].start
				var body := line.substr(words[then_idx].end, body_end - words[then_idx].end)
				shell.run_into(body, outcome, depth, parent)
		if boundary >= fi_idx:
			break
		if words[boundary].text == "elif":
			clause = boundary
			continue
		# else
		if not handled:
			handled = true
			var ebody := line.substr(words[boundary].end, words[fi_idx].start - words[boundary].end)
			shell.run_into(ebody, outcome, depth, parent)
		break
	if not handled:
		shell.session.last_exit_code = 0


# --- case WORD in PAT) BODY ;; PAT2|PAT3) BODY2 ;; *) BODY ;; esac -----------

static func _run_case(shell, line: String, words: Array, outcome, depth: int, parent) -> void:
	var in_idx := -1
	for i in range(1, words.size()):
		if words[i].text == "in":
			in_idx = i
			break
	if in_idx == -1:
		return _syntax(shell, outcome, "in")
	var esac_idx := _match(words, 0, "case", "esac")
	if esac_idx == -1:
		return _syntax(shell, outcome, "esac")

	var subj_raw := line.substr(words[0].end, words[in_idx].start - words[0].end)
	var subject := _expand_scalar(shell, subj_raw, outcome, depth, parent)
	var clauses_raw := line.substr(words[in_idx].end, words[esac_idx].start - words[in_idx].end)

	shell.session.last_exit_code = 0
	for clause in clauses_raw.split(";;", false):
		var text: String = clause.strip_edges()
		if text == "":
			continue
		var close := text.find(")")
		if close == -1:
			continue
		var pat_part := text.substr(0, close).strip_edges().lstrip("(").strip_edges()
		var body := text.substr(close + 1)
		var matched := false
		for pat in pat_part.split("|", false):
			if Expander.fnmatch(pat.strip_edges(), subject):
				matched = true
				break
		if matched:
			shell.run_into(body, outcome, depth, parent)
			return


## Expand a single value (subject of a case): arithmetic, command subst and
## variables, then strip one layer of surrounding quotes. No globbing.
static func _expand_scalar(shell, text: String, outcome, depth: int, parent) -> String:
	var s := text
	if s.contains("$(("):
		s = Arith.expand(s, shell.session)
	if s.contains("$(") or s.contains("`"):
		s = shell._expand_command_subst(s, outcome, depth, parent)
	s = Expander.expand_variables(s, shell.session).strip_edges()
	if s.length() >= 2 and ((s[0] == "\"" and s[-1] == "\"") or (s[0] == "'" and s[-1] == "'")):
		s = s.substr(1, s.length() - 2)
	return s


# --- helpers ----------------------------------------------------------------

## Index of the first top-level keyword `kw` at or after `from`.
static func _find_keyword(words: Array, from: int, kw: String) -> int:
	var block_depth := 0
	for i in range(from, words.size()):
		var t: String = words[i].text
		if block_depth == 0 and t == kw:
			return i
		if t in OPENERS:
			block_depth += 1
		elif t in CLOSERS:
			block_depth -= 1
	return -1


## Given the index of an opener keyword (do/if), the index of its matching
## closer, honoring nesting.
static func _match(words: Array, open_idx: int, open_kw: String, close_kw: String) -> int:
	var depth := 1
	for i in range(open_idx + 1, words.size()):
		var t: String = words[i].text
		if t == open_kw:
			depth += 1
		elif t == close_kw:
			depth -= 1
			if depth == 0:
				return i
	return -1


## The first of `kws` at this block's top level between `from` and `limit`.
static func _next_at_level(words: Array, from: int, limit: int, kws: Array) -> int:
	var block_depth := 0
	for i in range(from, limit):
		var t: String = words[i].text
		if t in OPENERS:
			block_depth += 1
		elif t in CLOSERS:
			block_depth -= 1
		elif block_depth == 0 and t in kws:
			return i
	return limit


static func _expand_items(items_str: String, session) -> Array:
	var lexed := ShellLexer.tokenize(items_str.strip_edges())
	if lexed.error != "" or lexed.tokens.is_empty():
		return []
	var word_tokens: Array = []
	for tok in lexed.tokens:
		if tok.type == "word":
			word_tokens.append(tok)
	return Expander.expand_words(word_tokens, session)


static func _syntax(shell, outcome, near: String) -> void:
	outcome.write("err", "bash: syntax error near `%s'\n" % near)
	shell.session.last_exit_code = 2
