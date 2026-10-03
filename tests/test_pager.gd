extends "res://tests/test_base.gd"
## less and tail -f: at the terminal they hand off to the read-only viewer
## (open_pager / open_follow); in a pipe or redirect they behave like plain text.
## The live overlay is exercised in tests/ui_smoke.gd.


func _event(outcome: ExecutionOutcome, name: String) -> Dictionary:
	for e in outcome.events:
		if e.name == name:
			return e.data
	return {}


func test_less_opens_the_pager() -> void:
	var sh := new_shell()
	run(sh, "echo -e 'a\\nb\\nc' > poem.txt")
	var o := run(sh, "less poem.txt")
	var d := _event(o, "open_pager")
	check(not d.is_empty(), "less at the terminal opens the pager")
	check(str(d.get("title", "")) == "poem.txt", "pager is titled for the file")
	check(str(d.get("content", "")).contains("a\nb\nc"), "pager gets the file content")


func test_less_in_a_pipe_just_prints() -> void:
	var sh := new_shell()
	run(sh, "echo -e 'x\\ny' > f.txt")
	var o := run(sh, "less f.txt | cat")
	check(_event(o, "open_pager").is_empty(), "less in a pipe does not open the pager")
	check(o.stdout_text().contains("x\ny"), "piped less still passes the text through")


func test_less_from_stdin() -> void:
	var sh := new_shell()
	var o := run(sh, "echo hello | less")
	var d := _event(o, "open_pager")
	check(not d.is_empty(), "less at the end of a pipe opens the pager")
	check(str(d.get("title", "")) == "(stdin)", "piped-in content is titled (stdin)")


func test_less_needs_input() -> void:
	var sh := new_shell()
	check(run(sh, "less").exit_code != 0, "less with no file and no pipe is a usage error")


func test_tail_follow_opens_the_viewer() -> void:
	var sh := new_shell()
	run(sh, "echo -e '1\\n2\\n3' > app.log")
	var o := run(sh, "tail -f app.log")
	var d := _event(o, "open_follow")
	check(not d.is_empty(), "tail -f at the terminal opens the follow view")
	check(str(d.get("content", "")).contains("3"), "follow view starts from the file's tail")
	check(str(d.get("kind", "")) == "sys", "a plain log streams generic syslog")


func test_tail_follow_themes_by_name() -> void:
	var sh := new_shell()
	run(sh, "echo x > auth.log")
	check(str(_event(run(sh, "tail -f auth.log"), "open_follow").get("kind", "")) == "auth", "an auth log streams auth lines")
	run(sh, "echo x > access.log")
	check(str(_event(run(sh, "tail -f access.log"), "open_follow").get("kind", "")) == "http", "a web log streams requests")


func test_tail_follow_needs_a_file() -> void:
	var sh := new_shell()
	check(run(sh, "tail -f").exit_code != 0, "tail -f with no file is a usage error")


func test_tail_follow_in_a_redirect_falls_back() -> void:
	var sh := new_shell()
	run(sh, "echo -e 'a\\nb\\nc' > r.log")
	var o := run(sh, "tail -f r.log > out.txt")
	check(_event(o, "open_follow").is_empty(), "tail -f with no screen does not open the viewer")
	check(out(sh, "cat out.txt").contains("c"), "it falls back to a normal tail")


func test_plain_tail_still_works() -> void:
	var sh := new_shell()
	run(sh, "echo -e '1\\n2\\n3\\n4' > n.txt")
	check_eq(out(sh, "tail -n 2 n.txt"), "3\n4\n", "tail -n 2 still prints the last two lines")
