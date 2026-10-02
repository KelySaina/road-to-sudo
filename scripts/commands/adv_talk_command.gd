class_name AdvTalkCommand
extends BaseCommand
## Adventure verb: speak with whoever is here.
##   talk            what the character wants to say (teaches their specialty)
##   talk hint       ask them for a hint on the current fight
##   talk <command>  ask them to explain a command, e.g. `talk grep`


func get_command_name() -> String: return "talk"
func get_aliases() -> Array: return ["speak", "ask"]
func get_category() -> String: return "adventure"
func get_summary() -> String: return "talk to a character; `talk <command>` to learn one"
func get_usage() -> String: return "talk [hint | COMMAND]"
func get_manual() -> String:
	return "Talk to the character at your location. `talk hint` asks for advice on the\ncurrent fight. `talk <command>` — like `talk grep` — has them teach you that command."


func execute(ctx: CommandContext) -> int:
	if ctx.session.adventure == null:
		ctx.err("talk: there is no one here. (You are not on an adventure.)\n")
		return 1
	var args := ctx.args()
	var topic: String = args[0] if not args.is_empty() else ""
	# "talk grep" -> teach that command (but keep hint/help for the fight).
	if topic != "" and topic not in ["hint", "help"]:
		var registry: CommandRegistry = ctx.shell.registry
		var cmd := registry.get_command(topic)
		if cmd != null:
			ctx.out(I18n.t("They lean in and teach you about") + " ", "reaction")
			ctx.out(cmd.get_command_name() + ":\n", "exec")
			ctx.out("  %s\n" % I18n.t(cmd.get_summary()))
			ctx.out("  %s  %s\n" % [I18n.t("use it like:"), I18n.t(cmd.get_usage())], "dim")
			for line in I18n.t(cmd.get_manual()).split("\n"):
				ctx.out("  " + line + "\n")
			ctx.out("  " + I18n.t("(`learn` lists every command; `man %s` is the full page.)") % cmd.get_command_name() + "\n", "dim")
			ctx.emit("manual_read", {"topic": cmd.get_command_name()})
			return 0
		ctx.out(I18n.t("They tilt their head — they don't know a command called '%s'. Try `learn` for the list.") % topic + "\n", "dim")
		return 0
	ctx.emit("adv_talk", {"who": topic})
	return 0
