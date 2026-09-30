class_name FindCommand
extends BaseCommand
## Supports: -name -iname -type -maxdepth -mindepth -user -group -perm -empty
## -not/! -print -delete -exec CMD {} ;


func get_command_name() -> String: return "find"
func get_category() -> String: return "files"
func get_summary() -> String: return "search for files in a directory hierarchy"
func get_usage() -> String: return "find [PATH...] [-name PATTERN] [-type f|d] [-maxdepth N] [-exec CMD {} \\;]"
func get_manual() -> String:
	return """Walks directories and prints every path matching ALL the given tests.
  -name '*.log'   match the file name (quote the pattern!)
  -iname PAT      same, case-insensitive
  -type f|d       only files / only directories
  -maxdepth N     do not descend more than N levels
  -user NAME      owned by NAME
  -perm 644       exact permission bits
  -empty          empty files or directories
  -exec cmd {} \\; run cmd for each match ({} is replaced by the path)
Example:  find /var/log -name '*.log' -exec grep ERROR {} \\;"""


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
			if node == null or not _matches(node, parsed.tests, ctx):
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
	var tests: Array = []
	var result := {"tests": tests, "maxdepth": -1, "mindepth": 0, "exec_argv": [], "delete": false}
	var negate := false
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var needs_value := a in ["-name", "-iname", "-type", "-maxdepth", "-mindepth", "-user", "-group", "-perm"]
		if needs_value and i + 1 >= args.size():
			return {"error": "missing argument to `%s'" % a}
		match a:
			"!", "-not":
				negate = true
				i += 1
				continue
			"-name", "-iname", "-type", "-user", "-group", "-perm":
				tests.append({"kind": a, "value": args[i + 1], "negate": negate})
				i += 2
			"-empty":
				tests.append({"kind": a, "value": "", "negate": negate})
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
			"-o", "-or":
				return {"error": "-o (OR) is not supported in this simulator yet; run find twice"}
			_:
				return {"error": "unknown predicate `%s'" % a}
		negate = false
	return result


func _matches(node: VFSNode, tests: Array, ctx: CommandContext) -> bool:
	for t in tests:
		var ok := true
		match t.kind:
			"-name":
				ok = node.name.match(t.value)
			"-iname":
				ok = node.name.to_lower().match(str(t.value).to_lower())
			"-type":
				ok = (t.value == "d" and node.is_dir()) or (t.value == "f" and not node.is_dir())
			"-user":
				ok = node.owner == t.value
			"-group":
				ok = node.group == t.value
			"-perm":
				ok = (node.mode & 4095) == Permissions.from_octal(str(t.value).trim_prefix("-").trim_prefix("/"))
			"-empty":
				ok = node.children.is_empty() if node.is_dir() else node.content == ""
		if t.negate:
			ok = not ok
		if not ok:
			return false
	return true


func _display_path(start: String, start_abs: String, path: String) -> String:
	if path == start_abs:
		return start
	var rel := path.substr(start_abs.length()).trim_prefix("/")
	if start == "/":
		return "/" + rel
	return start.trim_suffix("/") + "/" + rel
