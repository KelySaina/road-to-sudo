class_name AdvTalkCommand
extends BaseCommand
## Adventure verb: speak with whoever is here.


func get_command_name() -> String: return "talk"
func get_aliases() -> Array: return ["speak", "ask"]
func get_category() -> String: return "adventure"
func get_summary() -> String: return "talk to a character here (adventure)"
func get_usage() -> String: return "talk [hint]"
func get_manual() -> String:
	return "Talk to the character at your location. `talk hint` asks them for advice\nwhen one is stuck."


func execute(ctx: CommandContext) -> int:
	if ctx.session.adventure == null:
		ctx.err("talk: there is no one here. (You are not on an adventure.)\n")
		return 1
	ctx.emit("adv_talk", {"who": " ".join(PackedStringArray(ctx.args()))})
	return 0
