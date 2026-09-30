class_name DateCommand
extends BaseCommand


func get_command_name() -> String: return "date"
func get_category() -> String: return "system"
func get_summary() -> String: return "print the date and time"


func execute(ctx: CommandContext) -> int:
	var t := Time.get_datetime_dict_from_system()
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	ctx.out("%s %s %2d %02d:%02d:%02d UTC %d\n" % [days[int(t.weekday)], months[int(t.month) - 1], int(t.day), int(t.hour), int(t.minute), int(t.second), int(t.year)])
	return 0
