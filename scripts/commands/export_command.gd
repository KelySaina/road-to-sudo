class_name ExportCommand
extends BaseCommand


func get_command_name() -> String: return "export"
func get_category() -> String: return "shell"
func get_summary() -> String: return "set an environment variable"
func get_usage() -> String: return "export NAME=VALUE..."


func execute(ctx: CommandContext) -> int:
	if ctx.args().is_empty():
		for k in ctx.session.env:
			ctx.out("declare -x %s=\"%s\"\n" % [k, ctx.session.env[k]])
		return 0
	for a in ctx.args():
		var s: String = a
		var eq := s.find("=")
		var key := s.substr(0, eq) if eq != -1 else s
		if not key.is_valid_identifier():
			return ctx.fail("`%s'" % s, "not a valid identifier")
		if eq != -1:
			ctx.session.env[key] = s.substr(eq + 1)
		elif not ctx.session.env.has(key):
			ctx.session.env[key] = ""
		ctx.emit("variable_set", {"name": key})
	return 0
