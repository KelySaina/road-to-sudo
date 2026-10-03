extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with status 1 if any assertion fails.

var _failures: Array = []
var _passes := 0
var _current := ""


func _initialize() -> void:
	var suites := [
		preload("res://tests/test_core.gd").new(),
		preload("res://tests/test_shell.gd").new(),
		preload("res://tests/test_challenges.gd").new(),
		preload("res://tests/test_editor.gd").new(),
		preload("res://tests/test_i18n.gd").new(),
		preload("res://tests/test_audio.gd").new(),
	]
	for suite in suites:
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			_current = "%s.%s" % [suite.get_script().resource_path.get_file().get_basename(), name]
			suite.runner = self
			suite.call(name)
	print("")
	print("%d assertions passed, %d failed" % [_passes, _failures.size()])
	for f in _failures:
		print("  FAIL ", f)
	quit(1 if not _failures.is_empty() else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append("%s: %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_passes += 1
	else:
		_failures.append("%s: %s\n      expected: %s\n      actual:   %s" % [_current, message, str(expected), str(actual)])
