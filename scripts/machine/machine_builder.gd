class_name MachineBuilder
extends RefCounted
## Builds a Machine from a data/machines/*.json definition.
##
## "files" maps absolute paths to specs:
##   {"dir": true, "owner": "player", "group": "player", "mode": "750"}
##   {"content": "hello\n", "mode": "644"}
##   {"lines": ["line 1", "line 2"]}            -> joined with \n
##   {"generator": "auth_log", "params": {...}} -> ContentGenerators

const MACHINES_DIR := "res://data/machines/"


static func load_machine(machine_id: String, command_names: Array = []) -> Machine:
	var path := MACHINES_DIR + machine_id + ".json"
	var data := JsonLoader.load_dict(path)
	if data.is_empty():
		push_error("Machine definition missing or invalid: %s" % path)
	return build(data, command_names)


static func build(data: Dictionary, command_names: Array = []) -> Machine:
	var m := Machine.new()
	m.hostname = data.get("hostname", "localhost")
	m.users = data.get("users", {"root": {"uid": 0, "gid": 0, "groups": ["root"], "home": "/root", "shell": "/bin/bash"}})
	m.sudoers = data.get("sudoers", [])
	m.processes = []
	for p in data.get("processes", []):
		var proc: Dictionary = p.duplicate()
		proc["pid"] = int(proc.get("pid", 1))
		m.processes.append(proc)
		m.next_pid = maxi(m.next_pid, int(proc.pid))

	for d in ["/bin", "/etc", "/home", "/root", "/tmp", "/usr/bin", "/usr/share", "/var/log", "/opt", "/dev", "/proc"]:
		m.vfs.ensure_dir(d)
	m.vfs.get_node_at("/root").mode = Permissions.from_octal("700")
	m.vfs.get_node_at("/tmp").mode = Permissions.from_octal("777")
	m.vfs.put_file("/dev/null", "", "root", "root", Permissions.from_octal("666"))

	# Every simulated command appears as a binary so `ls /bin` and `which` feel real.
	for cmd_name in command_names:
		m.vfs.put_file("/usr/bin/" + str(cmd_name), "\u007fELF (simulated binary)\n", "root", "root", Permissions.from_octal("755"))

	for user_name in m.users:
		var u: Dictionary = m.users[user_name]
		var home: String = u.get("home", "/home/" + user_name)
		var groups: Array = u.get("groups", [user_name])
		var primary: String = groups[0] if groups.size() > 0 else user_name
		m.vfs.ensure_dir(home).owner = user_name
		m.vfs.get_node_at(home).group = primary

	apply_services(m, data.get("services", {}))
	_build_net(m, data.get("net", {}))
	_write_system_files(m)
	apply_files(m.vfs, data.get("files", {}))
	return m


## Fills in the networking model, always guaranteeing a loopback interface.
static func _build_net(m: Machine, spec: Dictionary) -> void:
	var net: Dictionary = spec.duplicate(true)
	var interfaces: Array = net.get("interfaces", [])
	var has_lo := false
	for iface in interfaces:
		if str(iface.get("name", "")) == "lo":
			has_lo = true
	if not has_lo:
		interfaces.push_front({"name": "lo", "ip": "127.0.0.1", "cidr": 8, "mac": "00:00:00:00:00:00", "state": "UNKNOWN"})
	net["interfaces"] = interfaces
	net["routes"] = net.get("routes", [])
	net["dns"] = net.get("dns", {})
	net["listen"] = net.get("listen", [])
	net["hosts"] = net.get("hosts", {})
	m.net = net


## Normalizes a name->spec map of systemd units onto the machine. Also used by
## challenge setup so a challenge can declare (or override) its own services.
static func apply_services(m: Machine, specs: Dictionary) -> void:
	for unit in specs:
		var s: Dictionary = (specs[unit] as Dictionary).duplicate(true)
		var active: bool = bool(s.get("active", false))
		var base: Dictionary = m.services.get(unit, {})
		var unit_full: String = unit if unit.contains(".") else unit + ".service"
		m.services[unit] = {
			"unit": unit_full,
			"description": s.get("description", base.get("description", unit + " service")),
			"active": active,
			"enabled": bool(s.get("enabled", base.get("enabled", false))),
			"sub": s.get("sub", ("running" if active else "dead")),
			"exec": s.get("exec", base.get("exec", "/usr/sbin/" + unit)),
			"main_pid": int(s.get("main_pid", base.get("main_pid", 0))),
			"since": s.get("since", base.get("since", "Mon 2026-09-30 09:12:04 UTC")),
			"journal": s.get("journal", base.get("journal", [])),
			"needs": s.get("needs", base.get("needs", {})),
		}


## Applies a path->spec map. Used by machine definitions and challenge setup.
static func apply_files(vfs: VirtualFileSystem, files: Dictionary) -> void:
	var paths := files.keys()
	paths.sort_custom(func(a, b): return PathUtils.depth(a) < PathUtils.depth(b))
	for path in paths:
		var spec: Dictionary = files[path]
		var node: VFSNode
		if spec.get("dir", false):
			node = vfs.ensure_dir(path)
		else:
			node = vfs.get_node_at(path)
			if node == null or node.is_dir():
				node = vfs.put_file(path, "")
			node.content = _content_of(spec)
		node.owner = spec.get("owner", node.owner)
		node.group = spec.get("group", spec.get("owner", node.group))
		if spec.has("mode"):
			node.mode = Permissions.from_octal(str(spec.mode))
		if spec.has("mtime"):
			node.mtime = spec.mtime


static func _content_of(spec: Dictionary) -> String:
	if spec.has("generator"):
		return ContentGenerators.generate(spec.generator, spec.get("params", {}))
	if spec.has("lines"):
		return "\n".join(PackedStringArray(spec.lines)) + "\n"
	return spec.get("content", "")


static func _write_system_files(m: Machine) -> void:
	m.vfs.put_file("/etc/hostname", m.hostname + "\n")
	if m.vfs.get_node_at("/etc/hosts") == null:
		m.vfs.put_file("/etc/hosts", "127.0.0.1\tlocalhost\n127.0.1.1\t%s\n" % m.hostname)
	m.vfs.put_file("/etc/os-release", "PRETTY_NAME=\"SudoOS 1.0 (Bootstrap)\"\nNAME=\"SudoOS\"\nID=sudoos\nID_LIKE=debian\nHOME_URL=\"https://example.invalid/road-to-sudo\"\n")
	var passwd := PackedStringArray()
	var group_members := {}
	for user_name in m.users:
		var u: Dictionary = m.users[user_name]
		passwd.append("%s:x:%d:%d:%s:%s:%s" % [user_name, int(u.get("uid", 1000)), int(u.get("gid", 1000)), u.get("gecos", user_name), u.get("home", "/home/" + user_name), u.get("shell", "/bin/bash")])
		for g in u.get("groups", []):
			if not group_members.has(g):
				group_members[g] = []
			group_members[g].append(user_name)
	m.vfs.put_file("/etc/passwd", "\n".join(passwd) + "\n")
	var group_lines := PackedStringArray()
	for g in group_members:
		group_lines.append("%s:x:%d:%s" % [g, m.gid_of_group(g), ",".join(PackedStringArray(group_members[g]))])
	m.vfs.put_file("/etc/group", "\n".join(group_lines) + "\n")
	m.vfs.put_file("/etc/shadow", "root:*:19000:0:99999:7:::\n", "root", "shadow", Permissions.from_octal("640"))
	var sudoers_text := "# /etc/sudoers — who may run commands as root.\nroot    ALL=(ALL:ALL) ALL\n%sudo   ALL=(ALL:ALL) ALL\n"
	for s in m.sudoers:
		sudoers_text += "%s    ALL=(ALL:ALL) ALL\n" % s
	m.vfs.put_file("/etc/sudoers", sudoers_text, "root", "root", Permissions.from_octal("440"))
