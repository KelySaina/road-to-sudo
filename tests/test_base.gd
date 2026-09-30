extends RefCounted
## Shared helpers for test suites.

var runner: SceneTree
var _registry: CommandRegistry


func check(condition: bool, message: String) -> void:
	runner.check(condition, message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	runner.check_eq(actual, expected, message)


func registry() -> CommandRegistry:
	if _registry == null:
		_registry = CommandRegistry.create_default()
	return _registry


func new_shell(machine_id: String = "workstation") -> Shell:
	var m := MachineBuilder.load_machine(machine_id, registry().primary_names())
	var session := ShellSession.new(m, "player")
	return Shell.new(session, registry())


func run(shell: Shell, line: String) -> ExecutionOutcome:
	return shell.run_line(line)


func out(shell: Shell, line: String) -> String:
	return shell.run_line(line).stdout_text()


func text(shell: Shell, line: String) -> String:
	return shell.run_line(line).all_text()
