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
	ctx.out(I18n.t("New here? Type  learn  for a cheat sheet of what each command does,") + "\n")
	ctx.out(I18n.t("or  man <command>  for the full manual.") + "\n\n", "tip")
	ctx.out(I18n.t("Commands on this machine:") + "\n\n")
	for cat in CATEGORY_ORDER:
		if not by_cat.has(cat):
			continue
		ctx.out(cat.to_upper() + "\n", "header")
		for cmd in by_cat[cat]:
			ctx.out("  %s %s\n" % [cmd.get_command_name().rpad(10), I18n.t(cmd.get_summary())])
		ctx.out("\n")
	ctx.out(I18n.t("GAME") + "\n", "header")
	ctx.out("  :hint      " + I18n.t("reveal the next hint for the current objective") + "\n")
	ctx.out("  :objective " + I18n.t("show the current objective again") + "\n")
	ctx.out("  :solution  " + I18n.t("reveal the solution (no bonus XP)") + "\n")
	ctx.out("  :reset     " + I18n.t("rewind the machine to the start of this challenge") + "\n")
	ctx.out("  :skip      " + I18n.t("skip ahead (Normal/Expert only)") + "\n")
	ctx.out("  :menu      " + I18n.t("back to the main menu") + "\n")
	return 0
