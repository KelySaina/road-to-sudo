class_name FindCommand
extends BaseCommand
## Supports: -name -iname -type -maxdepth -mindepth -user -group -perm -empty
## -not/! -print -delete -exec CMD {} ;


func get_command_name() -> String: return "find"
func get_category() -> String: return "files"
func get_summary() -> String: return "search for files in a directory hierarchy"
func get_usage() -> String: return "find [PATH...] [-name PATTERN] [-type f|d] [-maxdepth N] [-exec CMD {} \\;]"
func get_manual() -> String:
	return """Walks directories and prints every path matching the given tests.
  -name '*.log'   match the file name (quote the pattern!)
  -iname PAT      same, case-insensitive
  -type f|d       only files / only directories
  -maxdepth N     do not descend more than N levels
  -user NAME      owned by NAME
  -perm 644       exact permission bits
  -empty          empty files or directories
  ! EXPR / -not   negate a test
  EXPR -o EXPR    match either side (-a, the default, is AND)
  \\( EXPR \\)      group, so -o can bind before an -a
  -exec cmd {} \\; run cmd for each match ({} is replaced by the path)
Example:  find . \\( -name '*.log' -o -name '*.txt' \\) -type f"""


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	var starts: Array = []
	while not args.is_empty() and not (str(args[0]).begins_with("-") or args[0] == "!" or args[0] == "("):
		starts.append(args.pop_front())
	if starts.is_empty():
		starts = ["."]
	var parsed := _parse_expression(args)
	if parsed.has("error"):
		return ctx.fail("", parsed.error)

	var code := 0
	for start in starts:
		var start_abs := ctx.resolve(start)
		var res := ctx.vfs().lookup(start_abs, ctx.access())
		if not res.ok:
			code = ctx.fail("'%s'" % start, res.error)
			continue
		var walked := ctx.vfs().walk(start_abs, ctx.access())
		var start_depth := PathUtils.depth(start_abs)
		for path in walked.paths:
			var depth := PathUtils.depth(path) - start_depth
			if parsed.maxdepth >= 0 and depth > parsed.maxdepth:
				continue
			if depth < parsed.mindepth:
				continue
			var node := ctx.vfs().get_node_at(path)
			if node == null or not _eval(parsed.expr, node, ctx):
				continue
			var shown := _display_path(start, start_abs, path)
			if parsed.exec_argv.is_empty() and not parsed.delete:
				ctx.out(shown + "\n")
			if not parsed.exec_argv.is_empty():
				var argv: Array = []
				for a in parsed.exec_argv:
					argv.append(str(a).replace("{}", shown))
				var child := ctx.spawn(argv)
				child.stdin = ""
				child.has_stdin = false
				ctx.shell.invoke(child)
				ctx.absorb(child)
			if parsed.delete:
				var del := ctx.vfs().remove(path, ctx.access(), node.is_dir() and node.children.is_empty(), false)
				if not del.ok:
					code = ctx.fail("cannot delete '%s'" % shown, del.error)
				else:
					ctx.emit("file_deleted", {"path": path, "was_dir": node.is_dir()})
		for denied in walked.denied:
			code = ctx.fail("'%s'" % _display_path(start, start_abs, denied), VirtualFileSystem.EACCES)
	ctx.emit("find_used", {"exec": not parsed.exec_argv.is_empty()})
	return code


func _parse_expression(args: Array) -> Dictionary:
	var result := {"expr": null, "maxdepth": -1, "mindepth": 0, "exec_argv": [], "delete": false}
	# First pass: pull out global options and actions (which can sit anywhere), and
	# collect the remaining tokens — tests, operators, and \( \) grouping — as the
	# boolean expression to parse. Test tokens are folded into one {kind,value} each.
	var etoks: Array = []
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var needs_value := a in ["-name", "-iname", "-type", "-maxdepth", "-mindepth", "-user", "-group", "-perm"]
		if needs_value and i + 1 >= args.size():
			return {"error": "missing argument to `%s'" % a}
		match a:
			"-name", "-iname", "-type", "-user", "-group", "-perm":
				etoks.append({"kind": a, "value": args[i + 1]})
				i += 2
			"-empty":
				etoks.append({"kind": "-empty", "value": ""})
				i += 1
			"(", ")", "!", "-not", "-a", "-and", "-o", "-or":
				etoks.append(a)
				i += 1
			"-maxdepth":
				result.maxdepth = int(args[i + 1])
				i += 2
			"-mindepth":
				result.mindepth = int(args[i + 1])
				i += 2
			"-print":
				i += 1
			"-delete":
				result.delete = true
				i += 1
			"-exec":
				var cmd: Array = []
				i += 1
				while i < args.size() and args[i] != ";" and args[i] != "+":
					cmd.append(args[i])
					i += 1
				if i >= args.size():
					return {"error": "missing argument to `-exec' (end it with \\;)"}
				if cmd.is_empty():
					return {"error": "-exec needs a command"}
				result.exec_argv = cmd
				i += 1
			_:
				return {"error": "unknown predicate `%s'" % a}

	if etoks.is_empty():
		return result   # no tests: everything matches
	# Second pass: recursive descent over the tokens into an AST. Precedence from
	# loosest to tightest: -o, then -a (juxtaposition), then !/-not, then \( \).
	var c := {"toks": etoks, "i": 0, "error": ""}
	var tree = _parse_or(c)
	if c.error != "":
		return {"error": c.error}
	if c.i < etoks.size():
		return {"error": "unexpected `%s'" % str(etoks[c.i])}
	result.expr = tree
	return result


func _peek(c: Dictionary):
	return c.toks[c.i] if c.i < c.toks.size() else null


## Is the next token one of these operator strings? False for a test token (a
## Dictionary), which must never be compared to a String with `==` (GDScript errors).
func _is_op(c: Dictionary, ops: Array) -> bool:
	var t = _peek(c)
	return typeof(t) == TYPE_STRING and t in ops


func _parse_or(c: Dictionary):
	var node = _parse_and(c)
	while c.error == "" and _is_op(c, ["-o", "-or"]):
		c.i += 1
		var rhs = _parse_and(c)
		node = {"op": "or", "children": [node, rhs]}
	return node


func _parse_and(c: Dictionary):
	var children: Array = [_parse_unary(c)]
	# Implicit AND: any operand not separated by -o (or closing the group) binds here.
	while c.error == "" and _peek(c) != null and not _is_op(c, ["-o", "-or", ")"]):
		if _is_op(c, ["-a", "-and"]):
			c.i += 1
		children.append(_parse_unary(c))
	return children[0] if children.size() == 1 else {"op": "and", "children": children}


func _parse_unary(c: Dictionary):
	if _is_op(c, ["!", "-not"]):
		c.i += 1
		return {"op": "not", "child": _parse_unary(c)}
	return _parse_primary(c)


func _parse_primary(c: Dictionary):
	var t = _peek(c)
	if _is_op(c, ["("]):
		c.i += 1
		var node = _parse_or(c)
		if not _is_op(c, [")"]):
			c.error = "expected `)'"
			return null
		c.i += 1
		return node
	if typeof(t) == TYPE_DICTIONARY:
		c.i += 1
		return {"op": "test", "kind": t.kind, "value": t.value}
	c.error = "expected an expression%s" % (" but found `%s'" % str(t) if t != null else "")
	return null


## Evaluate the test AST against one node. A null tree matches everything.
func _eval(node, vfsnode: VFSNode, ctx: CommandContext) -> bool:
	if node == null:
		return true
	match node.op:
		"test":
			return _test_one(vfsnode, node, ctx)
		"not":
			return not _eval(node.child, vfsnode, ctx)
		"and":
			for child in node.children:
				if not _eval(child, vfsnode, ctx):
					return false
			return true
		"or":
			for child in node.children:
				if _eval(child, vfsnode, ctx):
					return true
			return false
	return true


func _test_one(node: VFSNode, t: Dictionary, _ctx: CommandContext) -> bool:
	match t.kind:
		"-name":
			return Expander.fnmatch(str(t.value), node.name)
		"-iname":
			return Expander.fnmatch(str(t.value).to_lower(), node.name.to_lower())
		"-type":
			return (t.value == "d" and node.is_dir()) or (t.value == "f" and not node.is_dir())
		"-user":
			return node.owner == t.value
		"-group":
			return node.group == t.value
		"-perm":
			return (node.mode & 4095) == Permissions.from_octal(str(t.value).trim_prefix("-").trim_prefix("/"))
		"-empty":
			return node.children.is_empty() if node.is_dir() else node.content == ""
	return false


func _display_path(start: String, start_abs: String, path: String) -> String:
	if path == start_abs:
		return start
	var rel := path.substr(start_abs.length()).trim_prefix("/")
	if start == "/":
		return "/" + rel
	return start.trim_suffix("/") + "/" + rel
