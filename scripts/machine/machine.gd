class_name Machine
extends RefCounted
## A simulated host: filesystem + accounts + process table.
## Several machines can exist at once (later: SSH between them).

var hostname: String = "localhost"
var vfs: VirtualFileSystem = VirtualFileSystem.new()
## name -> {"uid": int, "gid": int, "groups": Array[String], "home": String, "shell": String}
var users: Dictionary = {}
## Each process: {"pid", "user", "cpu", "mem", "stat", "cmd"}
var processes: Array = []
## systemd-style units. name -> {"description", "active", "enabled", "sub",
## "exec", "main_pid", "since", "journal": [String], "needs": {condition}}
var services: Dictionary = {}
## Networking model: {"interfaces", "routes", "dns", "listen", "hosts"}.
## Read by ip / ss / ping / curl / dig. See MachineBuilder for the shape.
var net: Dictionary = {}
## Package database (both installed and available). name -> {"version",
## "description", "section", "installed": bool, "depends": [names]}.
## Read by apt / dpkg.
var packages: Dictionary = {}
var sudoers: Array = []
var next_pid: int = 1000


func has_user(user_name: String) -> bool:
	return users.has(user_name)


func uid_of(user_name: String) -> int:
	return int(users.get(user_name, {}).get("uid", 65534))


func groups_of(user_name: String) -> PackedStringArray:
	var groups: Array = users.get(user_name, {}).get("groups", [])
	return PackedStringArray(groups)


func gid_of_group(group_name: String) -> int:
	for u in users.values():
		var gs: Array = u.get("groups", [])
		if gs.size() > 0 and gs[0] == group_name:
			return int(u.get("gid", 100))
	return 100 if group_name == "users" else 1001


func home_of(user_name: String) -> String:
	return users.get(user_name, {}).get("home", "/")


func access_for(user_name: String) -> AccessContext:
	return AccessContext.new(user_name, groups_of(user_name))


func is_sudoer(user_name: String) -> bool:
	if user_name == "root" or sudoers.has(user_name):
		return true
	for g in groups_of(user_name):
		if g == "sudo" or g == "wheel":
			return true
	return false


func find_process(pid: int) -> Dictionary:
	for p in processes:
		if int(p.pid) == pid:
			return p
	return {}


func spawn(user_name: String, cmd: String, cpu: float = 0.0, mem: float = 0.1) -> Dictionary:
	next_pid += 1
	var p := {"pid": next_pid, "user": user_name, "cpu": cpu, "mem": mem, "stat": "S", "cmd": cmd}
	processes.append(p)
	return p


func kill(pid: int) -> bool:
	for i in processes.size():
		if int(processes[i].pid) == pid:
			processes.remove_at(i)
			return true
	return false


# --- services (systemd units) ------------------------------------------------

func has_service(unit: String) -> bool:
	return services.has(unit)


func service_active(unit: String) -> bool:
	return bool(services.get(unit, {}).get("active", false))


func service_enabled(unit: String) -> bool:
	return bool(services.get(unit, {}).get("enabled", false))


## Appends a line to a unit's journal, timestamped like journald.
func journal(unit: String, line: String) -> void:
	if not services.has(unit):
		return
	var log: Array = services[unit].get("journal", [])
	log.append("%s %s %s[%d]: %s" % [_stamp(), hostname, unit, int(services[unit].get("main_pid", 1)), line])
	services[unit]["journal"] = log


static func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	const MON := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %02d %02d:%02d:%02d" % [MON[t.month], t.day, t.hour, t.minute, t.second]


# --- networking --------------------------------------------------------------

## Resolves a name to an IPv4 string, checking /etc/hosts first (so editing it
## fixes resolution), then the machine's DNS table. An IP passes through. "".
func resolve_host(name: String) -> String:
	if _is_ipv4(name):
		return name
	for entry in _etc_hosts():
		if name in entry.names:
			return entry.ip
	var dns: Dictionary = net.get("dns", {})
	return str(dns.get(name, ""))


## The peer at an IP, from net.hosts: {"name", "up", "ports": {port: {...}}}. {}.
func host_at(ip: String) -> Dictionary:
	return net.get("hosts", {}).get(ip, {})


func _etc_hosts() -> Array:
	var out: Array = []
	var node := vfs.get_node_at("/etc/hosts")
	if node == null or node.is_dir():
		return out
	for raw in node.content.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		var fields: Array = []
		for p in parts:
			for q in p.split("\t", false):
				if q != "":
					fields.append(q)
		if fields.size() >= 2:
			out.append({"ip": fields[0], "names": fields.slice(1)})
	return out


# --- packages ----------------------------------------------------------------

func package_installed(name: String) -> bool:
	return packages.has(name) and bool(packages[name].get("installed", false))


static func _is_ipv4(s: String) -> bool:
	var octets := s.split(".")
	if octets.size() != 4:
		return false
	for o in octets:
		if not str(o).is_valid_int() or int(o) < 0 or int(o) > 255:
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"hostname": hostname,
		"users": users,
		"processes": processes,
		"services": services,
		"net": net,
		"packages": packages,
		"sudoers": sudoers,
		"next_pid": next_pid,
		"fs": vfs.to_dict(),
	}


static func from_dict(d: Dictionary) -> Machine:
	var m := Machine.new()
	m.hostname = d.get("hostname", "localhost")
	m.users = d.get("users", {})
	m.processes = d.get("processes", [])
	m.services = d.get("services", {})
	m.net = d.get("net", {})
	m.packages = d.get("packages", {})
	m.sudoers = d.get("sudoers", [])
	m.next_pid = int(d.get("next_pid", 1000))
	m.vfs = VirtualFileSystem.from_dict(d.get("fs", {}))
	return m
