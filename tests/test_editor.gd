extends "res://tests/test_base.gd"
## The nano command itself: it validates the target and hands off to the UI by
## emitting `open_editor`. The full open -> type -> save -> grade path is covered
## live in tests/ui_smoke.gd, which has a real Game and the editor overlay.


func _editor_data(outcome: ExecutionOutcome) -> Dictionary:
	for e in outcome.events:
		if e.name == "open_editor":
			return e.data
	return {}


func test_nano_opens_a_new_file() -> void:
	var sh := new_shell()
	var o := run(sh, "nano fresh.txt")
	var d := _editor_data(o)
	check(not d.is_empty(), "nano emits open_editor")
	check_eq(str(d.get("content", "x")), "", "a new file opens with an empty buffer")
	check(bool(d.get("is_new", false)), "a new file is flagged is_new")
	check(bool(d.get("can_write", false)), "a new file in a writable dir can be saved")
	check_eq(o.exit_code, 0, "nano exits 0")


func test_nano_opens_an_existing_file() -> void:
	var sh := new_shell()
	run(sh, "echo hello > note.txt")
	var o := run(sh, "nano note.txt")
	var d := _editor_data(o)
	check_eq(str(d.get("content", "")), "hello\n", "an existing file opens with its content")
	check(not bool(d.get("is_new", true)), "an existing file is not flagged new")
	check(bool(d.get("can_write", false)), "the owner can write their own file")


func test_nano_rejects_a_directory() -> void:
	var sh := new_shell()
	run(sh, "mkdir adir")
	var o := run(sh, "nano adir")
	check(_editor_data(o).is_empty(), "nano on a directory does not open the editor")
	check(o.all_text().contains("Is a directory"), "nano reports the directory error")


func test_nano_refuses_to_run_off_the_terminal() -> void:
	var sh := new_shell()
	var o := run(sh, "nano note.txt | cat")
	check(_editor_data(o).is_empty(), "nano in a pipe does not open the editor")


func test_nano_needs_an_existing_parent() -> void:
	var sh := new_shell()
	var o := run(sh, "nano nope/deep.txt")
	check(_editor_data(o).is_empty(), "nano can't open a file under a missing directory")
	check(o.all_text().contains("No such file or directory"), "nano reports the missing parent")


func test_nano_wants_exactly_one_file() -> void:
	var sh := new_shell()
	check(run(sh, "nano").exit_code != 0, "nano with no file is a usage error")
	check(run(sh, "nano a.txt b.txt").exit_code != 0, "nano with two files is a usage error")
