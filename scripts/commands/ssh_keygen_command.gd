class_name SshKeygenCommand
extends BaseCommand
## Generates an ssh key pair in ~/.ssh, so you can log in without a password.


func get_command_name() -> String: return "ssh-keygen"
func get_category() -> String: return "network"
func get_summary() -> String: return "create an SSH key pair for passwordless login"
func get_usage() -> String: return "ssh-keygen [-t ed25519] [-f FILE] [-C COMMENT]"
func get_manual() -> String:
	return """ssh-keygen makes a key pair: a private key (kept secret, mode 600) and a
public key (.pub, shareable). You put the public key on a server's authorized
list, keep the private key safe, and then `ssh` logs you in with no password.
  ssh-keygen -t ed25519            make a modern key at ~/.ssh/id_ed25519
  ssh-keygen -t ed25519 -C \"me@host\"   add a comment/label
The private key must stay private — its permissions are set to 600 for a reason."""


func execute(ctx: CommandContext) -> int:
	var parsed := parse_options(ctx.args(), "tfCN", [])
	var key_type := str(parsed.values.get("t", "ed25519"))
	var comment := str(parsed.values.get("C", "%s@%s" % [ctx.session.user, ctx.machine().hostname]))
	var home := ctx.machine().home_of(ctx.session.user)
	var default_name := "id_ed25519" if key_type == "ed25519" else "id_rsa"
	var path := str(parsed.values.get("f", home + "/.ssh/" + default_name))
	path = ctx.resolve(path)

	var vfs := ctx.vfs()
	var ssh_dir := PathUtils.dirname(path)
	vfs.ensure_dir(ssh_dir)
	var dir_node := vfs.get_node_at(ssh_dir)
	if dir_node != null:
		dir_node.owner = ctx.session.user
		dir_node.group = ctx.session.user
		dir_node.mode = Permissions.from_octal("700")

	ctx.out("Generating public/private %s key pair.\n" % key_type)
	# A believable-looking (fake) key body — nothing real, just for the sim.
	var fingerprint := "SHA256:%s" % _rand_b64(43)
	var priv := "-----BEGIN OPENSSH PRIVATE KEY-----\n%s\n-----END OPENSSH PRIVATE KEY-----\n" % _rand_b64(64)
	var pub := "ssh-%s %s %s\n" % [key_type, _rand_b64(68), comment]
	vfs.put_file(path, priv, ctx.session.user, ctx.session.user, Permissions.from_octal("600"))
	vfs.put_file(path + ".pub", pub, ctx.session.user, ctx.session.user, Permissions.from_octal("644"))

	ctx.out("Your identification has been saved in %s\n" % path)
	ctx.out("Your public key has been saved in %s.pub\n" % path)
	ctx.out("The key fingerprint is:\n")
	ctx.out("%s %s\n" % [fingerprint, comment])
	ctx.emit("ssh_keygen", {"path": path})
	return 0


func _rand_b64(n: int) -> String:
	const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var s := ""
	for i in n:
		s += CHARS[randi() % CHARS.length()]
	return s
