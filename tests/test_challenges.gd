extends "res://tests/test_base.gd"
## Plays every challenge: nothing completes by accident, and the documented
## solution (plus a few alternative ones) completes it.


func _manager(difficulty: String = "beginner") -> ChallengeManager:
	return ChallengeManager.new(ChallengeLibrary.load_default(), PlayerProfile.new(), DifficultySettings.load_id(difficulty))


func _play(mgr: ChallengeManager, shell: Shell, lines: Array) -> bool:
	for line in lines:
		mgr.observe(shell.run_line(line))
		if mgr.completed_pending_next:
			return true
	return false


func test_library_is_valid() -> void:
	var lib := ChallengeLibrary.load_default()
	check_eq(lib.order.size(), 16, "campaign challenges in order (Level 0 + Level 1)")
	for cid in lib.order:
		var c := lib.get_challenge(cid)
		check(c.validate().is_empty(), "%s validates: %s" % [cid, str(c.validate())])
		check(c.hints.size() == 3, "%s has 3 progressive hints" % cid)
		check(c.solution != "", "%s has a solution" % cid)


func test_every_solution_completes() -> void:
	var lib := ChallengeLibrary.load_default()
	var mgr := _manager()
	var shell := new_shell()
	for cid in lib.order:
		var c := lib.get_challenge(cid)
		mgr.begin(c, shell.session)
		check(not _play(mgr, shell, ["true"]), "%s is not complete before the player acts" % cid)
		var solved := _play(mgr, shell, Array(c.solution.split("\n")))
		check(solved, "%s: solution completes the challenge" % cid)


func test_alternative_solutions() -> void:
	var lib := ChallengeLibrary.load_default()
	var cases := {
		"t01_identity": ["id"],
		"t02_location": ["echo $PWD"],
		"t03_look_around": ["head -n 20 welcome.txt"],
		"t04_hidden": ["grep codeword .hidden_note"],
		"t05_logs": ["cd /var", "cd log", "ls -l"],
		"t06_build": ["mkdir projects", "cd projects", "touch todo.txt"],
		"t07_redirect": ["cd ~/projects", "echo buy more coffee >> todo.txt"],
		"t08_needle": ["grep Failed /var/log/auth.log | tail -n 3", "echo mallory > intruder.txt"],
		"t09_permission": ["chmod 755 backup.sh", "./backup.sh"],
		"t10_first_incident": ["mkdir -p /home/player/reports", "chmod 600 /opt/reportd/report.conf", "cd /opt/reportd", "./run_report.sh"],
	}
	for cid in cases:
		var mgr := _manager()
		var shell := new_shell()
		mgr.begin(lib.get_challenge(cid), shell.session)
		check(_play(mgr, shell, cases[cid]), "%s: alternative solution accepted" % cid)


func test_wrong_answers_do_not_pass() -> void:
	var lib := ChallengeLibrary.load_default()
	var mgr := _manager()
	var shell := new_shell()
	mgr.begin(lib.get_challenge("t08_needle"), shell.session)
	check(not _play(mgr, shell, ["echo alice > ~/intruder.txt"]), "wrong intruder rejected")
	mgr = _manager()
	shell = new_shell()
	mgr.begin(lib.get_challenge("t09_permission"), shell.session)
	check(not _play(mgr, shell, ["bash backup.sh"]), "bash loophole does not count as fixing the file")
	mgr = _manager()
	shell = new_shell()
	mgr.begin(lib.get_challenge("t10_first_incident"), shell.session)
	check(not _play(mgr, shell, ["mkdir ~/reports", "/opt/reportd/run_report.sh"]), "half a fix is not a fix")


func test_hints_and_scoring() -> void:
	var lib := ChallengeLibrary.load_default()
	var mgr := _manager("beginner")
	var shell := new_shell()
	var results: Array = []
	mgr.challenge_completed.connect(func(_c, r): results.append(r))
	mgr.begin(lib.get_challenge("t01_identity"), shell.session)
	check(not mgr.can_reveal_solution(), "solution locked before hints")
	check(mgr.request_hint() != "", "hint 1")
	check(mgr.request_hint() != "", "hint 2")
	check(mgr.request_hint() != "", "hint 3")
	check_eq(mgr.request_hint(), "", "no hint 4")
	check(mgr.can_reveal_solution(), "solution after hints")
	_play(mgr, shell, ["whoami"])
	check_eq(int(results[0].total), 100, "3 hints: base XP only")

	var expert := _manager("expert")
	expert.begin(lib.get_challenge("t01_identity"), shell.session)
	check(expert.request_hint() != "", "expert gets one hint")
	check_eq(expert.request_hint(), "", "expert gets only one hint")
	check(not expert.can_reveal_solution(), "no solutions in expert")


func test_reactions_and_protection() -> void:
	var lib := ChallengeLibrary.load_default()
	var mgr := _manager()
	var shell := new_shell()
	var said: Array = []
	mgr.narrate.connect(func(t, _k): said.append(t))
	mgr.begin(lib.get_challenge("t09_permission"), shell.session)
	_play(mgr, shell, ["bash backup.sh"])
	check(said.any(func(t): return t.contains("Sneaky")), "bash loophole reaction")
	var o := shell.run_line("rm backup.sh")
	mgr.observe(o)
	check(said.any(func(t): return t.contains("Was that intentional?")), "protected-file reaction")
	check(o.has_event("protected_deleted"), "protected_deleted event for achievements")
	check(mgr.reset(), "reset works")
	check(shell.session.machine.vfs.exists("/home/player/backup.sh"), "reset restores deleted file")
	check(_play(mgr, shell, ["chmod +x backup.sh", "./backup.sh"]), "still solvable after reset")
