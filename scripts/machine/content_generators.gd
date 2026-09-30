class_name ContentGenerators
extends RefCounted
## Procedural file contents (big logs, noisy data) with a fixed seed, so a
## challenge file can say {"generator": "auth_log"} instead of shipping 10k lines.


static func generate(generator: String, params: Dictionary) -> String:
	match generator:
		"auth_log":
			return auth_log(params)
		"app_log":
			return app_log(params)
		"repeat":
			return repeat(params)
		"access_log":
			return access_log(params)
	push_warning("Unknown content generator: %s" % generator)
	return ""


## Mostly boring sshd noise, with one account hammering failed logins.
static func auth_log(params: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 1337))
	var lines := int(params.get("lines", 2000))
	var intruder: String = params.get("intruder", "mallory")
	var intruder_hits := int(params.get("intruder_hits", 42))
	var normal_users: Array = params.get("users", ["alice", "bob", "carol", "dave", "player"])
	var ips := ["10.0.0.12", "10.0.0.31", "192.168.1.20", "192.168.1.44", "172.16.4.2"]
	var bad_ip: String = params.get("intruder_ip", "203.0.113.66")
	var noise_fail_rate := float(params.get("noise_fail_rate", 0.01))
	var out := PackedStringArray()
	var intruder_every := maxi(1, lines / maxi(1, intruder_hits))
	var hits := 0
	for i in lines:
		var ts := _timestamp(i)
		if i % intruder_every == intruder_every / 2 and hits < intruder_hits:
			hits += 1
			out.append("%s workstation sshd[%d]: Failed password for %s from %s port %d ssh2" % [ts, 2000 + i, intruder, bad_ip, 40000 + rng.randi_range(0, 9999)])
			continue
		var u: String = normal_users[rng.randi_range(0, normal_users.size() - 1)]
		var ip: String = ips[rng.randi_range(0, ips.size() - 1)]
		var roll := rng.randf()
		if roll < 0.55:
			out.append("%s workstation sshd[%d]: Accepted publickey for %s from %s port %d ssh2" % [ts, 2000 + i, u, ip, 40000 + rng.randi_range(0, 9999)])
		elif roll < 0.75:
			out.append("%s workstation sshd[%d]: pam_unix(sshd:session): session closed for user %s" % [ts, 2000 + i, u])
		elif roll < 0.75 + noise_fail_rate:
			out.append("%s workstation sshd[%d]: Failed password for %s from %s port %d ssh2" % [ts, 2000 + i, u, ip, 40000 + rng.randi_range(0, 9999)])
		else:
			out.append("%s workstation CRON[%d]: pam_unix(cron:session): session opened for user root" % [ts, 2000 + i])
	return "\n".join(out) + "\n"


static func app_log(params: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 7))
	var lines := int(params.get("lines", 300))
	var errors := int(params.get("errors", 7))
	var app: String = params.get("app", "reportd")
	var messages := ["job queued", "job started", "rendering page", "cache hit", "cache miss", "job finished", "heartbeat ok"]
	var error_messages: Array = params.get("error_messages", ["database connection refused", "template not found", "disk quota exceeded"])
	var out := PackedStringArray()
	var error_every := maxi(1, lines / maxi(1, errors))
	var emitted := 0
	for i in lines:
		var ts := _timestamp(i * 7)
		if i % error_every == error_every - 1 and emitted < errors:
			out.append("%s [ERROR] %s: %s" % [ts, app, error_messages[emitted % error_messages.size()]])
			emitted += 1
		elif rng.randf() < 0.1:
			out.append("%s [WARN]  %s: slow response (%dms)" % [ts, app, rng.randi_range(800, 2500)])
		else:
			out.append("%s [INFO]  %s: %s" % [ts, app, messages[rng.randi_range(0, messages.size() - 1)]])
	return "\n".join(out) + "\n"


## CSV "user,resource,action" rows with one account over-represented — the
## culprit — for cut/sort/uniq practice.
static func access_log(params: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 55))
	var rows := int(params.get("rows", 300))
	var culprit: String = params.get("culprit", "nemo")
	var others: Array = params.get("users", ["alice", "bob", "carol", "dave", "erin"])
	var resources := ["/etc/passwd", "/var/www", "/home", "/opt/app", "/srv/data", "/root"]
	var actions := ["read", "write", "delete", "chmod", "list"]
	var out := PackedStringArray(["user,resource,action"])
	for i in rows:
		var user: String = culprit if rng.randf() < 0.42 else others[rng.randi_range(0, others.size() - 1)]
		out.append("%s,%s,%s" % [user, resources[rng.randi_range(0, resources.size() - 1)], actions[rng.randi_range(0, actions.size() - 1)]])
	return "\n".join(out) + "\n"


static func repeat(params: Dictionary) -> String:
	var line: String = params.get("line", "")
	var times := int(params.get("times", 1))
	var out := PackedStringArray()
	for i in times:
		out.append(line.replace("{n}", str(i + 1)))
	return "\n".join(out) + "\n"


static func _timestamp(i: int) -> String:
	var seconds := 8 * 3600 + i * 13
	return "Jun  5 %02d:%02d:%02d" % [(seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60]
