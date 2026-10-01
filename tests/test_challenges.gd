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
	check_eq(lib.order.size(), 64, "full campaign in order")
	for cid in lib.order:
		var c := lib.get_challenge(cid)
		check(c.validate().is_empty(), "%s validates: %s" % [cid, str(c.validate())])
		check(c.hints.size() == 3, "%s has 3 progressive hints" % cid)
		check(c.solution != "", "%s has a solution" % cid)


func test_every_solution_completes() -> void:
	var lib := ChallengeLibrary.load_default()
	var mgr := _manager()
	for cid in lib.order:
		var c := lib.get_challenge(cid)
		# boot the challenge's own machine (the finale runs on prodserver)
		var shell := new_shell(c.machine if c.machine != "" else "workstation")
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
		"l7_start": ["sudo systemctl start nginx"],
		"l7_stop": ["sudo systemctl disable --now telnet"],
		"l7_failed": ["sudo -i", "echo 'port = 9090' > /etc/webapp/webapp.conf", "systemctl restart webapp"],
		"l8_addr": ["ip a", "echo 10.10.0.7 > ip.txt"],
		"l8_curl": ["curl http://status.internal/ > health.txt"],
		"l8_dns": ["sudo -i", "echo 10.10.0.30 api.internal >> /etc/hosts"],
		"l9_install": ["sudo apt-get install tcpdump"],
		"l9_audit": ["dpkg -s openssl", "echo 3.0.11-1~deb12u2 > openssl.txt"],
		"l9_remove": ["sudo apt purge netcat-traditional"],
		"l10_init": ["cd site", "git init", "git add index.html style.css", "git commit -m snapshot"],
		"l10_log": ["cd ~/tool", "git init", "git add .", "git commit -m one", "echo x >> tool.sh", "git add .", "git commit -m two"],
		"l11_keygen": ["ssh-keygen"],
		"l11_login": ["ssh admin@web-01", "sudo systemctl start nginx"],
		"l11_scp": ["cd ~", "scp admin@web-01:/var/log/app.log ."],
		"l11_remote": ["ssh admin@web-01", "sudo kill 6931"],
		"l12_for": ["cd ~/reports", "for f in jan feb mar; do mv $f.txt $f.txt.done; done"],
		"l12_while": ["mkdir ~/processed", "while [ -n \"$(ls ~/queue)\" ]; do f=$(ls ~/queue | head -1); mv ~/queue/$f ~/processed/; done"],
		"l12_subst": ["ls ~/logs/*.log | wc -l > ~/count.txt"],
	}
	for cid in cases:
		var c := lib.get_challenge(cid)
		var mgr := _manager()
		var shell := new_shell(c.machine if c.machine != "" else "workstation")
		mgr.begin(c, shell.session)
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
	# Services: a stop without a disable, a start without privilege, a start
	# without fixing the config — none of these should count.
	mgr = _manager()
	shell = new_shell("server")
	mgr.begin(lib.get_challenge("l7_stop"), shell.session)
	check(not _play(mgr, shell, ["sudo systemctl stop telnet"]), "stopping without disabling is not enough")
	mgr = _manager()
	shell = new_shell("server")
	mgr.begin(lib.get_challenge("l7_start"), shell.session)
	check(not _play(mgr, shell, ["systemctl start nginx"]), "systemctl start needs privilege")
	mgr = _manager()
	shell = new_shell("server")
	mgr.begin(lib.get_challenge("l7_failed"), shell.session)
	check(not _play(mgr, shell, ["sudo systemctl start webapp"]), "starting a broken service does not fix it")
	# Networking: a known-good port isn't the backdoor; a wrong DNS mapping doesn't count.
	mgr = _manager()
	shell = new_shell("netbox")
	mgr.begin(lib.get_challenge("l8_ports"), shell.session)
	check(not _play(mgr, shell, ["echo 80 > ~/finding.txt"]), "a legitimate port is not the backdoor")
	mgr = _manager()
	shell = new_shell("netbox")
	mgr.begin(lib.get_challenge("l8_dns"), shell.session)
	check(not _play(mgr, shell, ["sudo -i", "echo 10.10.0.7 api.internal >> /etc/hosts"]), "wrong IP in /etc/hosts does not resolve the name")
	# Packages: install and remove both need root.
	mgr = _manager()
	shell = new_shell("server")
	mgr.begin(lib.get_challenge("l9_install"), shell.session)
	check(not _play(mgr, shell, ["apt install tcpdump"]), "apt install needs privilege")
	mgr = _manager()
	shell = new_shell("server")
	mgr.begin(lib.get_challenge("l9_remove"), shell.session)
	check(not _play(mgr, shell, ["apt remove netcat-traditional"]), "apt remove needs privilege")
	# Git: committing everything must NOT track the secret / the WIP file.
	mgr = _manager()
	shell = new_shell("devbox")
	mgr.begin(lib.get_challenge("l10_gitignore"), shell.session)
	check(not _play(mgr, shell, ["cd ~/api", "git init", "git add .", "git commit -m all"]), "committing .env without ignoring it fails the challenge")
	mgr = _manager()
	shell = new_shell("devbox")
	mgr.begin(lib.get_challenge("l10_stage"), shell.session)
	check(not _play(mgr, shell, ["cd ~/feature", "git init", "git add .", "git commit -m all"]), "committing the WIP scratch file is not the goal")
	# SSH: a bad login gets you nowhere; connecting without fixing isn't a fix.
	mgr = _manager()
	shell = new_shell("opsbox")
	mgr.begin(lib.get_challenge("l11_login"), shell.session)
	check(not _play(mgr, shell, ["ssh bob@web-01"]), "ssh as an unknown user is refused")
	check(not shell.session.is_remote(), "a refused ssh does not open a remote shell")
	mgr = _manager()
	shell = new_shell("opsbox")
	mgr.begin(lib.get_challenge("l11_remote"), shell.session)
	check(not _play(mgr, shell, ["ssh admin@web-01", "ps aux"]), "looking at the rogue process is not killing it")
	# Bash: copying instead of renaming, and listing all hosts, both miss the goal.
	mgr = _manager()
	shell = new_shell()
	mgr.begin(lib.get_challenge("l12_for"), shell.session)
	check(not _play(mgr, shell, ["cd ~/reports", "for f in *.txt; do cp $f $f.done; done"]), "copying leaves the .txt files, so it is not a rename")
	mgr = _manager()
	shell = new_shell()
	mgr.begin(lib.get_challenge("l12_if"), shell.session)
	check(not _play(mgr, shell, ["cd ~/hosts", "for h in *; do echo $h >> ~/up.txt; done"]), "listing every host (not just the up ones) is wrong")


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
