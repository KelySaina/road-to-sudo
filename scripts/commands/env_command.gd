class_name EnvCommand
extends BaseCommand


func get_command_name() -> String: return "env"
func get_aliases() -> Array: return ["printenv"]
func get_category() -> String: return "shell"
func get_summary() -> String: return "print environment variables"
func get_usage() -> String: return "env  |  printenv [NAME]"
func get_manual() -> String:
	return "Environment variables configure programs: HOME, PATH, USER...\nRead one with  echo $HOME  or  printenv HOME. Set one with  export NAME=value"


func execute(ctx: CommandContext) -> int:
	var env: Dictionary = ctx.session.env
	if not ctx.args().is_empty():
		var key: String = ctx.args()[0]
		if not env.has(key):
			return 1
		ctx.out(str(env[key]) + "\n")
		return 0
	var keys := env.keys()
	keys.sort()
	for k in keys:
		ctx.out("%s=%s\n" % [k, env[k]])
	return 0
