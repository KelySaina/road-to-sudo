class_name ShellSession
extends RefCounted
## Everything a login shell remembers: who, where, environment, history.

const MAX_LOG := 400

var machine: Machine
var user: String = "player"
## Set to the AdventureManager while in Adventure mode; null otherwise.
## Adventure verbs (go/look/talk...) read it. Kept untyped to avoid a
## dependency cycle between the terminal and adventure layers.
var adventure: RefCounted = null
var cwd: String = "/"
var previous_cwd: String = ""
var env: Dictionary = {}
var history: Array = []
var last_exit_code: int = 0
## Default-permission mask for new files/dirs (022 octal = 18). See `umask`.
var umask: int = 18
## Script positional parameters ($1..$9); empty for the interactive shell.
var positional: Array = []
## Shell functions defined this session: name -> body text (between { and }).
var functions: Dictionary = {}
## Every simple command that ran: {"name", "args", "exit_code", "stdout", "stderr", "depth", "user", "cwd"}
var command_log: Array = []
## Set by `exit N` inside a script; the interpreter stops at the next check.
var exit_requested: int = -1
## Set by `return N` inside a function; consumed at the function boundary so the
## unwind stops there instead of leaving the whole shell like `exit` does.
var return_requested: int = -1
## How many function bodies are currently on the call stack (so `return` outside a
## function can report the same error bash does).
var function_depth: int = 0
## Stack of {"user", "cwd"} pushed by su / sudo -i, popped by exit.
var user_stack: Array = []
## Stack of saved local contexts pushed by `ssh`, popped on remote `exit`.
## Each frame: {"machine", "user", "cwd", "env", "user_stack", "host"}.
var remote_stack: Array = []
## Remote machines built this session, keyed by host, so reconnecting sees the
## changes you made. Not serialized: a save/reload drops you back home.
var remote_cache: Dictionary = {}


func _init(p_machine: Machine, p_user: String) -> void:
	machine = p_machine
	user = p_user
	cwd = machine.home_of(user)
	_reset_env()


func _reset_env() -> void:
	env = {
		"USER": user,
		"LOGNAME": user,
		"HOME": home(),
		"SHELL": "/bin/bash",
		"PATH": "/usr/local/bin:/usr/bin:/bin",
		"PWD": cwd,
		"HOSTNAME": machine.hostname,
		"LANG": "en_US.UTF-8",
		"TERM": "xterm-256color",
	}


func home() -> String:
	return machine.home_of(user)


## Mode a newly created file/dir gets, after the umask removes bits.
func file_create_mode() -> int:
	return 438 & ~umask  # 0666 & ~umask


func dir_create_mode() -> int:
	return 511 & ~umask  # 0777 & ~umask


func access() -> AccessContext:
	return machine.access_for(user)


func resolve(path: String) -> String:
	return PathUtils.join(cwd, path)


func set_cwd(path: String) -> void:
	previous_cwd = cwd
	cwd = path
	env["OLDPWD"] = previous_cwd
	env["PWD"] = cwd


func get_variable(var_name: String) -> String:
	match var_name:
		"?":
			return str(last_exit_code)
		"$":
			return "4242"
		"#":
			return str(positional.size())
		"@":
			return " ".join(PackedStringArray(positional))
		"0":
			return "bash"
	if var_name.is_valid_int():
		var idx := int(var_name) - 1
		return str(positional[idx]) if idx >= 0 and idx < positional.size() else ""
	return str(env.get(var_name, ""))


func switch_user(new_user: String, login: bool) -> void:
	user_stack.append({"user": user, "cwd": cwd, "env": env.duplicate()})
	user = new_user
	if login:
		cwd = home()
		_reset_env()
	else:
		env["USER"] = user
		env["LOGNAME"] = user


## Returns false when there is nothing to pop (the top-level login shell).
func pop_user() -> bool:
	if user_stack.is_empty():
		return false
	var prev: Dictionary = user_stack.pop_back()
	user = prev.user
	cwd = prev.cwd
	env = prev.env
	return true


func prompt_symbol() -> String:
	return "#" if user == "root" else "$"


# --- ssh: switch the whole session to a remote machine, and back -------------

func is_remote() -> bool:
	return not remote_stack.is_empty()


## Opens a shell on `remote` as `target_user`, saving the current context.
func ssh_connect(remote: Machine, target_user: String) -> void:
	remote_stack.append({"machine": machine, "user": user, "cwd": cwd, "env": env.duplicate(), "user_stack": user_stack.duplicate(), "host": machine.hostname})
	machine = remote
	user = target_user
	user_stack = []
	cwd = machine.home_of(target_user)
	_reset_env()


## Closes the current remote shell, restoring the previous context. Returns the
## hostname just closed, or "" if there was no remote shell.
func ssh_disconnect() -> String:
	if remote_stack.is_empty():
		return ""
	var closed := machine.hostname
	var frame: Dictionary = remote_stack.pop_back()
	machine = frame.machine
	user = frame.user
	cwd = frame.cwd
	env = frame.env
	user_stack = frame.user_stack
	return closed


## The bottom-of-stack (login) machine and cwd — what a save should record even
## while the player is off on a remote host.
func base_machine() -> Machine:
	return remote_stack[0].machine if not remote_stack.is_empty() else machine


func base_cwd() -> String:
	return remote_stack[0].cwd if not remote_stack.is_empty() else cwd


func pretty_cwd() -> String:
	return PathUtils.prettify(cwd, home())


func log_command(record: Dictionary) -> void:
	command_log.append(record)
	if command_log.size() > MAX_LOG:
		command_log.pop_front()
