class_name Shell
extends RefCounted
## Executes parsed command lines against a ShellSession.
## Pipes pass stdout text along; redirections talk to the VFS; scripts are
## interpreted line by line after a real permission check.

const MAX_DEPTH := 8
const EXIT_NOT_EXECUTABLE := 126
const EXIT_NOT_FOUND := 127

var session: ShellSession
var registry: CommandRegistry
var _fn_regex: RegEx


func _init(p_session: ShellSession, p_registry: CommandRegistry) -> void:
	session = p_session
	registry = p_registry


## Entry point for the interactive prompt.
func run_line(line: String) -> ExecutionOutcome:
	var outcome := ExecutionOutcome.new()
	outcome.line = line
	session.exit_requested = -1
	var trimmed := line.strip_edges()
	if trimmed != "":
		session.history.append(trimmed)
	run_into(trimmed, outcome, 0)
	outcome.exit_code = session.last_exit_code
	return outcome


## `parent` is set when running inside a script: nested output then follows
## the parent's streams (so `./x.sh > out.txt` captures everything).
func run_into(line: String, outcome: ExecutionOutcome, depth: int, parent: CommandContext = null) -> void:
	if line.strip_edges() == "":
		return
	# A line is a sequence of top-level statements (split on ; and newline, but
	# not inside a for/while/if block). Each is either a compound command or an
	# ordinary pipeline. This is also what makes compounds work after a ; and
	# multi-line blocks work (their embedded newlines separate statements).
	for stmt in ShellControl.split_statements(line):
		_run_statement(stmt, outcome, depth, parent)
		if (session.exit_requested >= 0 or session.return_requested >= 0) and depth > 0:
			return


func _run_statement(stmt: String, outcome: ExecutionOutcome, depth: int, parent: CommandContext) -> void:
	if stmt == "" or stmt.begins_with("#"):
		return
	# Control flow (for / while / until / if) is detected on the raw statement —
	# the scanner treats $(...) and quotes as opaque — and runs its conditions
	# and bodies back through run_into.
	if ShellControl.is_compound_start(ShellControl.first_word(stmt)):
		ShellControl.run(self, stmt, outcome, depth, parent)
		return
	# A function definition — name() { ... } or function name { ... } — is stored,
	# not run. Detected before command substitution so its body stays literal.
	if stmt.contains("{") and stmt.contains("}"):
		var fn := _parse_function_def(stmt)
		if not fn.is_empty():
			session.functions[fn.name] = fn.body
			session.last_exit_code = 0
			return
	var line := stmt
	# Arithmetic $(( )) first, so its parens aren't mistaken for $( ) command subst.
	if line.contains("$(("):
		line = Arith.expand(line, session)
	if line.contains("$(") or line.contains("`"):
		line = _expand_command_subst(line, outcome, depth, parent)
	var parsed := CommandParser.parse(line)
	if parsed.error != "":
		outcome.write("err", "bash: %s\n" % parsed.error)
		session.last_exit_code = 2
		return
	for segment in parsed.segments:
		match segment.join:
			"&&":
				if session.last_exit_code != 0:
					continue
			"||":
				if session.last_exit_code == 0:
					continue
		_run_pipeline(segment.pipeline, outcome, depth, parent)
		if (session.exit_requested >= 0 or session.return_requested >= 0) and depth > 0:
			return
		if segment.pipeline.size() > 1:
			outcome.emit("pipe_used", {"length": segment.pipeline.size()})
		if segment.join in ["&&", "||"]:
			outcome.emit("chain_used", {"op": segment.join})


func _run_pipeline(pipeline: Array, outcome: ExecutionOutcome, depth: int, parent: CommandContext) -> void:
	var stdin_data := ""
	var piped := false
	for i in pipeline.size():
		var pc: ParsedCommand = pipeline[i]
		var ctx := CommandContext.new()
		ctx.session = session
		ctx.shell = self
		ctx.outcome = outcome
		ctx.depth = depth
		ctx.stdin = stdin_data
		ctx.has_stdin = piped
		var is_last := i == pipeline.size() - 1
		ctx.to_screen = is_last and (parent == null or parent.to_screen)
		ctx.stderr_to_screen = parent == null or parent.stderr_to_screen
		ctx.argv = Expander.expand_words(pc.words, session)

		var out_redirect := {}
		var err_redirect := {}
		var redirect_failed := false
		for r in pc.redirects:
			if r.op == "2>&1":
				ctx.stderr_to_stdout = true
				continue
			if r.op == ">&2":
				ctx.stdout_to_stderr = true
				continue
			var target_words := Expander.expand_word(r.target, session)
			if target_words.size() != 1:
				outcome.write("err", "bash: %s: ambiguous redirect\n" % ShellLexer.word_text(r.target))
				redirect_failed = true
				break
			var target_path := session.resolve(target_words[0])
			match r.op:
				"<":
					var res := session.machine.vfs.read_file(target_path, session.access())
					if not res.ok:
						outcome.write("err", "bash: %s: %s\n" % [target_words[0], res.error])
						if res.error == VirtualFileSystem.EACCES:
							outcome.emit("permission_denied", {"command": "<", "path": target_words[0]})
						redirect_failed = true
						break
					ctx.stdin = res.value
					ctx.has_stdin = true
				">", ">>":
					out_redirect = {"path": target_path, "shown": target_words[0], "append": r.op == ">>"}
					ctx.to_screen = false
				"2>", "2>>":
					err_redirect = {"path": target_path, "shown": target_words[0], "append": r.op == "2>>"}
					ctx.stderr_to_screen = false

		if redirect_failed:
			session.last_exit_code = 1
			stdin_data = ""
			piped = true
			continue

		# Like bash, the output file is created/truncated before the command runs.
		if not out_redirect.is_empty():
			if not _open_redirect(out_redirect, outcome):
				session.last_exit_code = 1
				stdin_data = ""
				piped = true
				continue

		var code := 0
		if not ctx.argv.is_empty():
			code = invoke(ctx)
		session.last_exit_code = code

		if not out_redirect.is_empty():
			if out_redirect.path != "/dev/null":
				session.machine.vfs.write_file(out_redirect.path, ctx.stdout_buffer, session.access(), true)
			outcome.emit("redirect_used", {"append": out_redirect.append, "path": out_redirect.path})
		if not err_redirect.is_empty() and err_redirect.path != "/dev/null":
			session.machine.vfs.write_file(err_redirect.path, ctx.stderr_buffer, session.access(), err_redirect.append)
		if parent != null:
			if err_redirect.is_empty():
				parent.stderr_buffer += ctx.stderr_buffer
			if is_last and out_redirect.is_empty():
				parent.stdout_buffer += ctx.stdout_buffer

		stdin_data = ctx.stdout_buffer
		piped = true


## Replaces every $(...) and `...` with the stdout of running it. Single-quoted
## spans are left literal. Trailing newlines are trimmed and inner newlines
## become spaces (the common unquoted use, e.g. `for f in $(ls)`).
func _expand_command_subst(line: String, outcome: ExecutionOutcome, depth: int, parent: CommandContext) -> String:
	var out := ""
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "'":
			var e := line.find("'", i + 1)
			if e == -1:
				out += line.substr(i)
				break
			out += line.substr(i, e - i + 1)
			i = e + 1
			continue
		if c == "\\" and i + 1 < n:
			out += line.substr(i, 2)
			i += 2
			continue
		if c == "$" and i + 1 < n and line[i + 1] == "(":
			var close := _find_subst_close(line, i + 2)
			out += _run_capture(line.substr(i + 2, close - i - 2), outcome, depth, parent)
			i = close + 1
			continue
		if c == "`":
			var b := line.find("`", i + 1)
			if b == -1:
				out += line.substr(i)
				break
			out += _run_capture(line.substr(i + 1, b - i - 1), outcome, depth, parent)
			i = b + 1
			continue
		out += c
		i += 1
	return out


func _find_subst_close(line: String, i: int) -> int:
	var depth := 1
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "'":
			var e := line.find("'", i + 1)
			i = (e + 1) if e != -1 else n
			continue
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return n


func _run_capture(inner: String, outcome: ExecutionOutcome, depth: int, parent: CommandContext) -> String:
	var cap := CommandContext.new()
	cap.session = session
	cap.shell = self
	cap.outcome = outcome
	cap.to_screen = false
	cap.stderr_to_screen = parent == null or parent.stderr_to_screen
	var saved_code := session.last_exit_code
	run_into(inner, outcome, depth + 1, cap)
	session.last_exit_code = saved_code
	var text := cap.stdout_buffer
	while text.ends_with("\n"):
		text = text.substr(0, text.length() - 1)
	return text.replace("\n", " ")


func _open_redirect(redirect: Dictionary, outcome: ExecutionOutcome) -> bool:
	if redirect.path == "/dev/null":
		return true
	var vfs := session.machine.vfs
	var res: VfsResult
	if redirect.append:
		res = vfs.write_file(redirect.path, "", session.access(), true)
	else:
		res = vfs.write_file(redirect.path, "", session.access(), false)
	if not res.ok:
		outcome.write("err", "bash: %s: %s\n" % [redirect.shown, res.error])
		if res.error == VirtualFileSystem.EACCES:
			outcome.emit("permission_denied", {"command": ">", "path": redirect.shown})
		return false
	return true


## Runs one already-expanded command. Public so commands like sudo and
## find -exec can run nested commands through the same path.
func invoke(ctx: CommandContext) -> int:
	var cmd_name: String = ctx.argv[0]
	var code := 0
	if ctx.depth > MAX_DEPTH:
		ctx.err("bash: maximum nesting depth exceeded\n")
		code = 1
	elif _is_assignment(cmd_name):
		var eq := cmd_name.find("=")
		session.env[cmd_name.substr(0, eq)] = cmd_name.substr(eq + 1)
		ctx.emit("variable_set", {"name": cmd_name.substr(0, eq)})
	elif cmd_name.contains("/"):
		code = _run_program_file(cmd_name, ctx)
	elif session.functions.has(cmd_name):
		code = _run_function(cmd_name, ctx)
	elif registry.has(cmd_name):
		code = registry.get_command(cmd_name).execute(ctx)
	else:
		code = _command_not_found(cmd_name, ctx)
	var record := {
		"name": cmd_name,
		"args": ctx.args(),
		"exit_code": code,
		"stdout": ctx.stdout_buffer,
		"stderr": ctx.stderr_buffer,
		"depth": ctx.depth,
		"user": session.user,
		"cwd": session.cwd,
	}
	session.log_command(record)
	ctx.outcome.records.append(record)
	return code


## Parse `name() { body }` or `function name { body }` into {name, body}, or {}.
## The body is everything between the first { and the final } (DOTALL, so it can
## span lines); inner } (as in ${VAR}) are kept, since the function's } is last.
func _parse_function_def(stmt: String) -> Dictionary:
	if _fn_regex == null:
		_fn_regex = RegEx.new()
		_fn_regex.compile("(?s)^\\s*(?:function\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?:\\(\\s*\\))?|([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\s*\\))\\s*\\{(.*)\\}\\s*;?\\s*$")
	var m := _fn_regex.search(stmt)
	if m == null:
		return {}
	var name := m.get_string(1)
	if name == "":
		name = m.get_string(2)
	return {"name": name, "body": m.get_string(3).strip_edges()}


## Run a defined function: its args become $1.., and its body runs like a script.
func _run_function(name: String, ctx: CommandContext) -> int:
	var body: String = session.functions[name]
	var saved_positional: Array = session.positional
	session.positional = ctx.args().duplicate()
	var saved_code := session.last_exit_code
	session.last_exit_code = 0
	session.function_depth += 1
	run_into(body, ctx.outcome, ctx.depth + 1, ctx)
	session.function_depth -= 1
	# `return N` unwinds the body up to here; consume it so it stops at the
	# function boundary instead of leaking out like `exit`.
	if session.return_requested >= 0:
		session.last_exit_code = session.return_requested
		session.return_requested = -1
	var code := session.last_exit_code
	session.positional = saved_positional
	return code


func _is_assignment(word: String) -> bool:
	var eq := word.find("=")
	return eq > 0 and word.substr(0, eq).is_valid_identifier()


func _command_not_found(cmd_name: String, ctx: CommandContext) -> int:
	ctx.err("Command '%s' not found.\n" % cmd_name)
	var suggestions := registry.suggest(cmd_name)
	if not suggestions.is_empty():
		ctx.err("\nDid you mean:\n")
		for s in suggestions:
			ctx.err("    %s\n" % s)
	# A file with that name in the cwd is a classic beginner trap.
	if session.machine.vfs.exists(session.resolve(cmd_name)):
		ctx.err("\n(There is a file called '%s' here. To run a program from the current directory, prefix it: ./%s)\n" % [cmd_name, cmd_name])
	ctx.emit("command_not_found", {"name": cmd_name})
	return EXIT_NOT_FOUND


## ./script.sh, /opt/tool/run, ../bin/x ...
func _run_program_file(path_text: String, ctx: CommandContext) -> int:
	var vfs := session.machine.vfs
	var abs_path := session.resolve(path_text)
	var res := vfs.lookup(abs_path, session.access())
	if not res.ok:
		ctx.err("bash: %s: %s\n" % [path_text, res.error])
		if res.error == VirtualFileSystem.EACCES:
			ctx.emit("permission_denied", {"command": path_text, "path": path_text})
			return EXIT_NOT_EXECUTABLE
		return EXIT_NOT_FOUND
	if res.node.is_dir():
		ctx.err("bash: %s: Is a directory\n" % path_text)
		return EXIT_NOT_EXECUTABLE
	if not Permissions.can(res.node, session.access(), Permissions.EXEC):
		ctx.err("bash: %s: Permission denied\n" % path_text)
		ctx.emit("permission_denied", {"command": path_text, "path": path_text, "reason": "not_executable"})
		return EXIT_NOT_EXECUTABLE
	# The kernel can exec a binary without read permission; an interpreter
	# needs to read the script.
	if res.node.content.begins_with("\u007fELF"):
		var bin_name := PathUtils.basename(abs_path)
		if registry.has(bin_name):
			var child := ctx.spawn([bin_name] + ctx.args())
			child.depth = ctx.depth
			var code := registry.get_command(bin_name).execute(child)
			ctx.absorb(child)
			return code
		return 0
	if not Permissions.can(res.node, session.access(), Permissions.READ):
		ctx.err("bash: %s: Permission denied\n" % path_text)
		ctx.emit("permission_denied", {"command": path_text, "path": path_text, "reason": "not_readable"})
		return EXIT_NOT_EXECUTABLE
	return run_script(res.node.content, ctx.args(), ctx)


## Interprets a script. Statements are read one at a time; a for/while/if block
## is accumulated across lines until it closes (done/fi) and run as a unit.
func run_script(source: String, script_args: Array, ctx: CommandContext) -> int:
	var saved_positional := session.positional
	session.positional = script_args
	var saved_code := session.last_exit_code
	session.last_exit_code = 0
	var lines := source.split("\n")
	var i := 0
	while i < lines.size():
		var line := str(lines[i]).strip_edges()
		i += 1
		if line == "" or line.begins_with("#"):
			continue
		# A compound command (for/while/if) may span several lines: keep reading
		# until its block is balanced (done/fi), then run the whole thing.
		while ShellControl.block_depth(line) > 0 and i < lines.size():
			line += "\n" + str(lines[i])
			i += 1
		run_into(line, ctx.outcome, ctx.depth + 1, ctx)
		if session.exit_requested >= 0:
			session.last_exit_code = session.exit_requested
			session.exit_requested = -1
			break
	var code := session.last_exit_code
	session.positional = saved_positional
	if code == 0:
		ctx.emit("script_succeeded", {"path": ctx.command_name()})
	session.last_exit_code = saved_code
	return code
