class_name DigCommand
extends BaseCommand
## DNS lookups against the machine's resolver (/etc/hosts, then its DNS table).


func get_command_name() -> String: return "dig"
func get_category() -> String: return "network"
func get_aliases() -> Array: return ["host"]
func get_summary() -> String: return "look up the IP address a name resolves to (DNS)"
func get_usage() -> String: return "dig [+short] NAME"
func get_manual() -> String:
	return """`dig` asks the resolver what IP address a name points to.
  dig +short status.internal   just the address, nothing else
  dig status.internal          the full answer, with an ANSWER SECTION
No answer (NXDOMAIN / empty) means the name doesn't resolve — the service may be
unknown to DNS, or missing from /etc/hosts. Names resolve via /etc/hosts first,
then DNS, so adding a line to /etc/hosts can fix a name that won't resolve."""


func execute(ctx: CommandContext) -> int:
	var short := false
	var name := ""
	for a in ctx.args():
		var s := str(a)
		if s == "+short":
			short = true
		elif s.begins_with("+") or s == "A" or s == "AAAA":
			pass
		elif not s.begins_with("-") and name == "":
			name = s
	if name == "":
		return usage_error(ctx, "usage: dig [+short] NAME")

	var ip := ctx.machine().resolve_host(name)
	if ctx.command_name() == "host":
		if ip == "":
			ctx.err("Host %s not found: 3(NXDOMAIN)\n" % name)
			return 1
		ctx.out("%s has address %s\n" % [name, ip])
		return 0
	if short:
		if ip != "":
			ctx.out(ip + "\n")
		return 0
	ctx.out("; <<>> DiG 9.18 <<>> %s\n" % name, "dim")
	ctx.out(";; ->>HEADER<<- opcode: QUERY, status: %s\n" % ("NOERROR" if ip != "" else "NXDOMAIN"), "dim")
	ctx.out(";; QUESTION SECTION:\n", "dim")
	ctx.out(";%s.\t\tIN\tA\n\n" % name)
	if ip != "":
		ctx.out(";; ANSWER SECTION:\n", "header")
		ctx.out("%s.\t300\tIN\tA\t%s\n" % [name, ip])
	else:
		ctx.out(";; no answer — the name does not resolve.\n", "warn")
	return 0 if ip != "" else 1
