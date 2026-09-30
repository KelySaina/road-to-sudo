class_name IpCommand
extends BaseCommand
## A teaching subset of iproute2's `ip`: addresses, links and routes.


func get_command_name() -> String: return "ip"
func get_category() -> String: return "network"
func get_summary() -> String: return "show network interfaces, addresses and routes"
func get_usage() -> String: return "ip addr | ip route | ip link"
func get_manual() -> String:
	return """`ip` shows how this machine is wired to the network.
  ip addr    (ip a)  every interface and its IP address
  ip route   (ip r)  the routing table — where packets go, incl. the default gateway
  ip link    (ip l)  interfaces and whether they are UP
An interface is a network card (real or virtual). 'lo' is loopback (yourself);
'eth0' is usually the wire. The IP after 'inet' is this host's address."""


func execute(ctx: CommandContext) -> int:
	var operands: Array = []
	for a in ctx.args():
		if not str(a).begins_with("-"):
			operands.append(str(a))
	var obj: String = operands[0] if operands.size() > 0 else "addr"
	var dev: String = ""
	# `ip addr show eth0` / `ip a eth0`
	for i in range(1, operands.size()):
		if operands[i] != "show" and operands[i] != "list":
			dev = operands[i]
	var net := ctx.machine().net
	match obj:
		"addr", "address", "a":
			return _addr(ctx, net, dev)
		"link", "l":
			return _link(ctx, net, dev)
		"route", "r", "ro":
			return _route(ctx, net)
		"neigh", "n":
			ctx.out("(neighbour table is empty)\n", "dim")
			return 0
		_:
			ctx.err("ip: unknown object \"%s\".\n" % obj)
			return 1


func _addr(ctx: CommandContext, net: Dictionary, dev: String) -> int:
	var idx := 0
	for iface in net.get("interfaces", []):
		idx += 1
		if dev != "" and str(iface.get("name", "")) != dev:
			continue
		var name := str(iface.get("name", "eth0"))
		var is_lo := name == "lo"
		var flags := "<LOOPBACK,UP,LOWER_UP>" if is_lo else "<BROADCAST,MULTICAST,UP,LOWER_UP>"
		var mtu := 65536 if is_lo else 1500
		ctx.out("%d: %s: %s mtu %d state %s\n" % [idx, name, flags, mtu, iface.get("state", "UP")], "header")
		if not is_lo:
			ctx.out("    link/ether %s brd ff:ff:ff:ff:ff:ff\n" % iface.get("mac", "52:54:00:00:00:00"), "dim")
		var scope := "host" if is_lo else "global"
		ctx.out("    inet %s/%d scope %s %s\n" % [iface.get("ip", "0.0.0.0"), int(iface.get("cidr", 24)), scope, name])
	if dev != "" and idx == 0:
		ctx.err("Device \"%s\" does not exist.\n" % dev)
		return 1
	return 0


func _link(ctx: CommandContext, net: Dictionary, dev: String) -> int:
	var idx := 0
	for iface in net.get("interfaces", []):
		idx += 1
		if dev != "" and str(iface.get("name", "")) != dev:
			continue
		var name := str(iface.get("name", "eth0"))
		var is_lo := name == "lo"
		var flags := "<LOOPBACK,UP,LOWER_UP>" if is_lo else "<BROADCAST,MULTICAST,UP,LOWER_UP>"
		ctx.out("%d: %s: %s mtu %d state %s\n" % [idx, name, flags, 65536 if is_lo else 1500, iface.get("state", "UP")], "header")
		ctx.out("    link/ether %s brd ff:ff:ff:ff:ff:ff\n" % iface.get("mac", "00:00:00:00:00:00"), "dim")
	return 0


func _route(ctx: CommandContext, net: Dictionary) -> int:
	var routes: Array = net.get("routes", [])
	if routes.is_empty():
		ctx.out("(no routes)\n", "dim")
		return 0
	for r in routes:
		var line := str(r.get("dst", "default"))
		if r.has("via"):
			line += " via %s" % r.via
		line += " dev %s" % r.get("dev", "eth0")
		if str(r.get("dst", "")) != "default":
			line += " proto kernel scope link"
			if r.has("src"):
				line += " src %s" % r.src
		ctx.out(line + "\n")
	return 0
