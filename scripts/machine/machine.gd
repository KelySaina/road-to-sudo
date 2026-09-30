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


func to_dict() -> Dictionary:
	return {
		"hostname": hostname,
		"users": users,
		"processes": processes,
		"sudoers": sudoers,
		"next_pid": next_pid,
		"fs": vfs.to_dict(),
	}


static func from_dict(d: Dictionary) -> Machine:
	var m := Machine.new()
	m.hostname = d.get("hostname", "localhost")
	m.users = d.get("users", {})
	m.processes = d.get("processes", [])
	m.sudoers = d.get("sudoers", [])
	m.next_pid = int(d.get("next_pid", 1000))
	m.vfs = VirtualFileSystem.from_dict(d.get("fs", {}))
	return m
