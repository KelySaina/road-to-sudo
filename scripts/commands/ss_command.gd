class_name SsCommand
extends BaseCommand
## Socket statistics — which ports this machine is listening on, and who owns them.


func get_command_name() -> String: return "ss"
func get_category() -> String: return "network"
func get_summary() -> String: return "show listening ports and sockets"
func get_usage() -> String: return "ss -tlnp  (tcp, listening, numeric, with process)"
func get_manual() -> String:
	return """`ss` lists network sockets. The everyday invocation is:
  ss -tlnp
    -t  TCP sockets      -u  UDP sockets
    -l  only listening    -n  numeric ports (don't translate to names)
    -a  all (listening + connected)   -p  show the owning process
A 'listening' socket is a service waiting for connections on a port — e.g.
sshd on 22, a web server on 80. If a port isn't listed, nothing is serving it."""


func execute(ctx: CommandContext) -> int:
	var flags := ""
	for a in ctx.args():
		var s := str(a)
		if s.begins_with("-"):
			flags += s.substr(1)
	var want_tcp := flags.contains("t")
	var want_udp := flags.contains("u")
	if not want_tcp and not want_udp:
		want_tcp = true
		want_udp = true
	var listening_only := flags.contains("l")
	var show_proc := flags.contains("p")

	var header := "State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port"
	if show_proc:
		header += "  Process"
	ctx.out(header + "\n", "header")
	for sock in ctx.machine().net.get("listen", []):
		var proto := str(sock.get("proto", "tcp"))
		if proto == "tcp" and not want_tcp:
			continue
		if proto == "udp" and not want_udp:
			continue
		var state := str(sock.get("state", "LISTEN"))
		if listening_only and state != "LISTEN":
			continue
		var local := "%s:%d" % [sock.get("addr", "0.0.0.0"), int(sock.get("port", 0))]
		var line := "%s  0       0        %s    *:*" % [state.rpad(6), local.rpad(20)]
		if show_proc:
			line += "   users:((\"%s\",pid=%d,fd=3))" % [sock.get("process", "?"), int(sock.get("pid", 0))]
		ctx.out(line + "\n")
	return 0
