class_name RemoteHost
extends RefCounted
## Resolves an [user@]host into a remote Machine for ssh / scp, using the local
## machine's networking model. Remote machines are cached on the session so
## reconnecting sees earlier changes.


## Returns {"machine", "user", "host", "ip"} or {"error": "..."} on failure.
static func resolve(ctx: CommandContext, hostspec: String) -> Dictionary:
	var user := ctx.session.user
	var host := hostspec
	if hostspec.contains("@"):
		var parts := hostspec.split("@", false, 1)
		user = parts[0]
		host = parts[1] if parts.size() > 1 else ""
	if host == "":
		return {"error": "ssh: could not parse host from '%s'" % hostspec}

	var m := ctx.machine()
	var ip := m.resolve_host(host)
	if ip == "":
		return {"error": "ssh: Could not resolve hostname %s: Name or service not known" % host}
	var peer := m.host_at(ip)
	if peer.is_empty():
		return {"error": "ssh: connect to host %s port 22: No route to host" % host}
	var ports: Dictionary = peer.get("ports", {})
	if not ports.has("22"):
		return {"error": "ssh: connect to host %s port 22: Connection refused" % host}
	var machine_id := str(peer.get("machine", ""))
	if machine_id == "":
		return {"error": "ssh: connect to host %s: no login shell configured" % host}

	var remote: Machine = ctx.session.remote_cache.get(host, null)
	if remote == null:
		var names: Array = ctx.shell.registry.primary_names() if ctx.shell != null else []
		remote = MachineBuilder.load_machine(machine_id, names)
		ctx.session.remote_cache[host] = remote
	if not remote.has_user(user):
		return {"error": "%s@%s: Permission denied (publickey,password)." % [user, host]}
	return {"machine": remote, "user": user, "host": host, "ip": ip}
