class_name AdvHintCommand
extends BaseCommand
## Adventure verb: reveal the next hint for the fight you're in.
## (The campaign uses `:hint` instead; this is the in-world version.)


func get_command_name() -> String: return "hint"
func get_category() -> String: return "adventure"
func get_summary() -> String: return "get help with the current fight (adventure)"
func get_usage() -> String: return "hint"


func execute(ctx: CommandContext) -> int:
	var adv = ctx.session.adventure
	if adv == null:
		ctx.err("hint: no fight here. (In the campaign, type `:hint`.)\n")
		return 1
	ctx.emit("adv_hint", {})
	return 0
