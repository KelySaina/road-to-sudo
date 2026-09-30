class_name SshCommand
extends BaseCommand
## Opens a shell on a remote machine. `ssh host` logs you in and keeps you there
## (the prompt changes; `exit` comes back). `ssh host command` runs one command
## remotely and returns. Reachability and login come from the networking model.


func get_command_name() -> String: return "ssh"
func get_category() -> String: return "network"
func get_summary() -> String: return "log in to and run commands on a remote machine"
func get_usage() -> String: return "ssh [user@]host [command...]"
func get_manual() -> String:
	return """ssh (secure shell) gives you a shell on another machine over the network.
  ssh admin@web-01        log in; your prompt becomes admin@web-01. `exit` returns.
  ssh web-01 uptime       run one command remotely and come straight back
Once logged in, every command runs on the remote host — the same tools you know
(ls, systemctl, ps...). It's how servers are administered. Keys live in ~/.ssh;
`ssh-keygen` makes them."""


func execute(ctx: CommandContext) -> int:
	var operands: Array = []
	var i := 0
	var args := ctx.args()
	while i < args.size():
		var a := str(args[i])
		if a in ["-i", "-p", "-l", "-o", "-F"]:
			i += 2 # option with a value; accepted and ignored
			continue
		if a.begins_with("-"):
			i += 1
			continue
		operands.append(a)
		i += 1
	if operands.is_empty():
		return usage_error(ctx, "usage: ssh [user@]host [command]")

	var hostspec: String = operands[0]
	var remote_cmd: Array = operands.slice(1)
	var r := RemoteHost.resolve(ctx, hostspec)
	if r.has("error"):
		ctx.err(str(r.error) + "\n")
		return 255

	var remote: Machine = r.machine
	ctx.session.ssh_connect(remote, r.user)
	ctx.emit("ssh_connected", {"host": r.host, "user": r.user})

	if remote_cmd.is_empty():
		# Interactive: stay logged in. Show the remote's message of the day.
		var motd: VFSNode = remote.vfs.get_node_at("/etc/motd")
		if motd != null and ctx.to_screen:
			ctx.out(str(motd.content).strip_edges(false, true) + "\n", "dim")
		ctx.out("Welcome to %s. You are %s. Type 'exit' to disconnect.\n" % [remote.hostname, r.user], "dim")
		return 0

	# One-shot: run the command remotely, then disconnect (like real ssh).
	var child := ctx.spawn(remote_cmd)
	child.depth = ctx.depth
	var code: int = ctx.shell.invoke(child)
	ctx.absorb(child)
	ctx.session.ssh_disconnect()
	ctx.emit("ssh_closed", {"host": r.host})
	return code
