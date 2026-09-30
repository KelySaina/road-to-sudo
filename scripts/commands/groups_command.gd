class_name GroupsCommand
extends BaseCommand


func get_command_name() -> String: return "groups"
func get_category() -> String: return "users"
func get_summary() -> String: return "print the groups a user is in"
func get_usage() -> String: return "groups [USER]"


func execute(ctx: CommandContext) -> int:
	var who: String = ctx.session.user if ctx.args().is_empty() else ctx.args()[0]
	if not ctx.machine().has_user(who):
		return ctx.fail("'%s'" % who, "no such user")
	var groups := " ".join(ctx.machine().groups_of(who))
	ctx.out((groups if ctx.args().is_empty() else "%s : %s" % [who, groups]) + "\n")
	return 0
