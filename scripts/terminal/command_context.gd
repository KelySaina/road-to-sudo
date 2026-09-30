class_name CommandContext
extends RefCounted
## The world as one command sees it: arguments, streams, session.
## Commands write through out()/err() and never touch the UI directly.

var argv: Array = []
var session: ShellSession
## The Shell running us (typed loosely to avoid a class dependency cycle).
var shell: RefCounted
var outcome: ExecutionOutcome
var stdin: String = ""
var has_stdin: bool = false
## False when stdout goes to a pipe or a file (the "isatty" of this world).
var to_screen: bool = true
var stdout_buffer: String = ""
var stderr_to_screen: bool = true
var stderr_buffer: String = ""
## 2>&1 sends errors wherever stdout goes; >&2 sends output to stderr.
var stderr_to_stdout: bool = false
var stdout_to_stderr: bool = false
var depth: int = 0


func command_name() -> String:
	return str(argv[0]) if argv.size() > 0 else ""


func args() -> Array:
	return argv.slice(1)


func out(text: String, style: String = "") -> void:
	if stdout_to_stderr:
		_write_err(text)
		return
	stdout_buffer += text
	if to_screen:
		outcome.write("out", text, style)


func err(text: String) -> void:
	if stderr_to_stdout:
		stdout_buffer += text
		if to_screen:
			outcome.write("err", text)
		return
	_write_err(text)


func _write_err(text: String) -> void:
	stderr_buffer += text
	if stderr_to_screen:
		outcome.write("err", text)


func emit(event_name: String, data: Dictionary = {}) -> void:
	outcome.emit(event_name, data)


# --- convenience -------------------------------------------------------------

func machine() -> Machine:
	return session.machine


func vfs() -> VirtualFileSystem:
	return session.machine.vfs


func access() -> AccessContext:
	return session.access()


func resolve(path: String) -> String:
	return session.resolve(path)


## Standard "cmd: subject: reason" error. Returns 1 so callers can `return ctx.fail(...)`.
func fail(subject: String, reason: String, code: int = 1) -> int:
	if subject == "":
		err("%s: %s\n" % [command_name(), reason])
	else:
		err("%s: %s: %s\n" % [command_name(), subject, reason])
	if reason == VirtualFileSystem.EACCES or reason == "Operation not permitted":
		emit("permission_denied", {"command": command_name(), "path": subject})
	return code


## Reads each operand (or stdin when there are none / "-").
## Returns [{"name": String, "content": String}], reporting errors itself.
func read_sources(operands: Array) -> Dictionary:
	var sources: Array = []
	var failed := false
	if operands.is_empty():
		sources.append({"name": "-", "content": stdin})
		return {"sources": sources, "failed": false}
	for op in operands:
		if op == "-":
			sources.append({"name": "-", "content": stdin})
			continue
		var res := vfs().read_file(resolve(op), access())
		if not res.ok:
			fail(op, res.error)
			failed = true
			continue
		sources.append({"name": op, "content": res.value})
	return {"sources": sources, "failed": failed}


## A context for running another command inside this one (sudo, find -exec).
func spawn(new_argv: Array) -> CommandContext:
	var c := CommandContext.new()
	c.argv = new_argv
	c.session = session
	c.shell = shell
	c.outcome = outcome
	c.stdin = stdin
	c.has_stdin = has_stdin
	c.to_screen = to_screen
	c.stderr_to_screen = stderr_to_screen
	c.stderr_to_stdout = stderr_to_stdout
	c.stdout_to_stderr = stdout_to_stderr
	c.depth = depth + 1
	return c


func absorb(child: CommandContext) -> void:
	stdout_buffer += child.stdout_buffer
	stderr_buffer += child.stderr_buffer
