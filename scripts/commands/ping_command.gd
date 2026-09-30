class_name PingCommand
extends BaseCommand
## Tests reachability of a host. Resolution and reachability come from the
## machine's networking model (DNS table, /etc/hosts, and the hosts it can see).


func get_command_name() -> String: return "ping"
func get_category() -> String: return "network"
func get_summary() -> String: return "check whether a host is reachable"
func get_usage() -> String: return "ping [-c COUNT] HOST"
func get_manual() -> String:
	return """`ping` sends probes to a host and reports whether they come back.
  ping -c 4 HOST   send 4 probes then stop
'0% packet loss' means the host answered — the network path works. '100%
packet loss' or 'Name or service not known' means it did not: either the name
doesn't resolve, or the host is down / firewalled. It's the first thing to try
when 'the server can't be reached'."""


func execute(ctx: CommandContext) -> int:
	var parsed := parse_options(ctx.args(), "c", [])
	if parsed.error != "":
		return usage_error(ctx, parsed.error)
	if parsed.operands.is_empty():
		return usage_error(ctx, "usage: ping [-c count] destination")
	var host := str(parsed.operands[0])
	var count := int(str(parsed.values.get("c", "4")))
	count = clampi(count, 1, 10)
	var m := ctx.machine()
	var ip := m.resolve_host(host)
	if ip == "":
		ctx.err("ping: %s: Name or service not known\n" % host)
		return 2

	ctx.out("PING %s (%s) 56(84) bytes of data.\n" % [host, ip])
	var reachable := _reachable(m, ip)
	var received := 0
	for seq in range(1, count + 1):
		if reachable:
			var t := 0.20 + float(seq) * 0.03
			ctx.out("64 bytes from %s: icmp_seq=%d ttl=64 time=%.2f ms\n" % [ip, seq, t])
			received += 1
		else:
			ctx.out("From %s icmp_seq=%d Destination Host Unreachable\n" % [_own_ip(m), seq])
	var loss := int(round(float(count - received) / float(count) * 100.0))
	ctx.out("\n--- %s ping statistics ---\n" % host)
	ctx.out("%d packets transmitted, %d received, %d%% packet loss, time %dms\n" % [count, received, loss, count * 1000], "" if received > 0 else "warn")
	if received > 0:
		ctx.out("rtt min/avg/max/mdev = 0.203/0.271/0.410/0.061 ms\n", "dim")
	return 0 if received > 0 else 1


func _reachable(m: Machine, ip: String) -> bool:
	if ip.begins_with("127.") or ip == _own_ip(m):
		return true
	var host := m.host_at(ip)
	if not host.is_empty():
		return bool(host.get("up", true))
	# A gateway named in the routing table is reachable even without a host entry.
	for r in m.net.get("routes", []):
		if str(r.get("via", "")) == ip:
			return true
	return false


func _own_ip(m: Machine) -> String:
	for iface in m.net.get("interfaces", []):
		if str(iface.get("name", "")) != "lo":
			return str(iface.get("ip", "127.0.0.1"))
	return "127.0.0.1"
