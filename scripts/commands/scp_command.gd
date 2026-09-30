class_name ScpCommand
extends BaseCommand
## Copies files between this machine and a remote one over ssh. A remote path is
## written host:path (e.g. web-01:/var/log/app.log).


func get_command_name() -> String: return "scp"
func get_category() -> String: return "network"
func get_summary() -> String: return "copy files to or from a remote machine (over ssh)"
func get_usage() -> String: return "scp [user@]host:remote local   |   scp local [user@]host:remote"
func get_manual() -> String:
	return """scp copies files across the network using ssh.
  scp web-01:/var/log/app.log .     download the remote file into the current dir
  scp report.txt admin@web-01:/tmp   upload a local file to the remote host
A remote location is written host:path; a plain path is local. It's the quick
way to pull a log off a server or push a config to it."""


func execute(ctx: CommandContext) -> int:
	var operands: Array = []
	for a in ctx.args():
		if not str(a).begins_with("-"):
			operands.append(str(a))
	if operands.size() < 2:
		return usage_error(ctx, "need a source and a destination")
	var src: String = operands[0]
	var dst: String = operands[operands.size() - 1]
	if _is_remote(src):
		return _copy(ctx, src, dst, true)
	if _is_remote(dst):
		return _copy(ctx, dst, src, false)
	ctx.err("scp: at least one path must be remote (host:path)\n")
	return 1


## `remote_spec` is the host:path side; `local` is the local path. download=true
## pulls remote->local, download=false pushes local->remote.
func _copy(ctx: CommandContext, remote_spec: String, local: String, download: bool) -> int:
	var colon := remote_spec.find(":")
	var hostspec := remote_spec.substr(0, colon)
	var rpath := remote_spec.substr(colon + 1)
	var r := RemoteHost.resolve(ctx, hostspec)
	if r.has("error"):
		ctx.err(str(r.error) + "\n")
		return 1
	var remote: Machine = r.machine
	var raccess := remote.access_for(r.user)
	if not rpath.begins_with("/"):
		rpath = PathUtils.normalize(remote.home_of(r.user) + "/" + rpath)

	if download:
		var res := remote.vfs.read_file(rpath, raccess)
		if not res.ok:
			ctx.err("scp: %s: %s\n" % [rpath, res.error])
			return 1
		var dest := ctx.resolve(local)
		if ctx.vfs().is_dir(dest):
			dest = PathUtils.normalize(dest + "/" + PathUtils.basename(rpath))
		ctx.vfs().write_file(dest, res.value, ctx.access(), false)
		ctx.out("%s  100%%  %d bytes\n" % [PathUtils.basename(rpath), res.value.length()], "dim")
		ctx.emit("scp_download", {"host": r.host, "remote": rpath, "local": dest})
		return 0
	# upload
	var lres := ctx.vfs().read_file(ctx.resolve(local), ctx.access())
	if not lres.ok:
		ctx.err("scp: %s: %s\n" % [local, lres.error])
		return 1
	var rdest := rpath
	if remote.vfs.is_dir(rdest):
		rdest = PathUtils.normalize(rdest + "/" + PathUtils.basename(ctx.resolve(local)))
	remote.vfs.write_file(rdest, lres.value, raccess, false)
	ctx.out("%s  100%%  %d bytes\n" % [PathUtils.basename(local), lres.value.length()], "dim")
	ctx.emit("scp_upload", {"host": r.host, "local": local, "remote": rdest})
	return 0


func _is_remote(spec: String) -> bool:
	var colon := spec.find(":")
	if colon <= 0:
		return false
	# Everything before the colon must be a hostname (no path separator).
	return not spec.substr(0, colon).contains("/")
