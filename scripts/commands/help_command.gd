class_name HelpCommand
extends BaseCommand

const CATEGORY_ORDER := ["adventure", "basics", "files", "text", "permissions", "users", "processes", "system", "shell", "misc"]


func get_command_name() -> String: return "help"
func get_category() -> String: return "basics"
func get_summary() -> String: return "list available commands"


func execute(ctx: CommandContext) -> int:
	var registry: CommandRegistry = ctx.shell.registry
	var by_cat := {}
	var in_adventure: bool = ctx.session.adventure != null
	for n in registry.primary_names():
		var cmd := registry.get_command(n)
		var cat := cmd.get_category()
		if cat == "adventure" and not in_adventure:
			continue
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(cmd)
	ctx.out("New here? Type  learn  for a cheat sheet of what each command does,\n")
	ctx.out("or  man <command>  for the full manual.\n\n", "tip")
	ctx.out("Commands on this machine:\n\n")
	for cat in CATEGORY_ORDER:
		if not by_cat.has(cat):
			continue
		ctx.out(cat.to_upper() + "\n", "header")
		for cmd in by_cat[cat]:
			ctx.out("  %s %s\n" % [cmd.get_command_name().rpad(10), cmd.get_summary()])
		ctx.out("\n")
	ctx.out("GAME\n", "header")
	ctx.out("  :hint      reveal the next hint for the current objective\n")
	ctx.out("  :objective show the current objective again\n")
	ctx.out("  :solution  reveal the solution (no bonus XP)\n")
	ctx.out("  :reset     rewind the machine to the start of this challenge\n")
	ctx.out("  :skip      skip ahead (Normal/Expert only)\n")
	ctx.out("  :menu      back to the main menu\n")
	return 0
