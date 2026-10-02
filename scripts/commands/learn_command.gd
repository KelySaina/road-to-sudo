class_name LearnCommand
extends BaseCommand
## A friendly, example-driven cheat sheet — "what does each command do?".
## `learn` shows the whole guide; `learn <command>` shows one command's card.
## Data lives in res://data/cheatsheet.json so it is easy to extend.

const DATA := "res://data/cheatsheet.json"


func get_command_name() -> String: return "learn"
func get_aliases() -> Array: return ["cheatsheet", "guide"]
func get_category() -> String: return "basics"
func get_summary() -> String: return "a cheat sheet of what each command does"
func get_usage() -> String: return "learn [COMMAND]"
func get_manual() -> String:
	return "Prints a field guide of the most useful commands, grouped by task,\nwith an example for each. `learn ls` focuses on one command."


func execute(ctx: CommandContext) -> int:
	if not ctx.args().is_empty():
		return _one(ctx, ctx.args()[0])
	var data := JsonLoader.load_content_dict(DATA)
	ctx.out(str(data.get("intro", "")) + "\n\n", "dim")
	for section in data.get("sections", []):
		ctx.out(I18n.t(str(section.get("title", ""))).to_upper() + "\n", "header")
		var width := 0
		for item in section.get("items", []):
			width = maxi(width, str(item.cmd).length())
		for item in section.get("items", []):
			ctx.out("  " + str(item.cmd).rpad(width + 2), "exec")
			ctx.out(I18n.t(str(item.desc)).rpad(34))
			ctx.out(str(item.ex) + "\n", "dim")
		ctx.out("\n")
	ctx.out(I18n.t("Full details for any command:  man <command>") + "\n", "tip")
	return 0


func _one(ctx: CommandContext, name: String) -> int:
	var registry: CommandRegistry = ctx.shell.registry
	var cmd := registry.get_command(name)
	if cmd == null:
		ctx.err(I18n.t("learn: no command called '%s'. Type `learn` for the whole guide.") % name + "\n")
		var near := registry.suggest(name)
		if not near.is_empty():
			ctx.err(I18n.t("Did you mean: %s") % "  ".join(PackedStringArray(near)) + "\n")
		return 1
	ctx.out(cmd.get_command_name() + "  —  " + I18n.t(cmd.get_summary()) + "\n", "header")
	ctx.out("\n" + I18n.t("Use it like:") + "\n  " + I18n.t(cmd.get_usage()) + "\n\n")
	for line in cmd.get_manual().split("\n"):
		ctx.out("  " + line + "\n")
	ctx.out("\n" + I18n.t("(`man %s` shows the full manual.)") % cmd.get_command_name() + "\n", "dim")
	ctx.emit("manual_read", {"topic": cmd.get_command_name()})
	return 0
