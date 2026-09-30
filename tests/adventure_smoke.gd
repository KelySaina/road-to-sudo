extends SceneTree
## Plays "The Ascent to Root" through the 2D engage/visit_npc API (what the
## World2D scene uses): every fight, both new stages, the traps, the reboot
## and the respawning boss — all headless.

var failures: Array = []
var passes := 0
var _reg: CommandRegistry
var narration: Array = []


func _initialize() -> void:
	_reg = CommandRegistry.create_default()
	test_world_valid()
	test_full_playthrough()
	test_alternative_solutions()
	test_wrong_answers()
	test_traps_and_reboot()
	test_elevation_unwind()
	test_nudges()
	test_talk_teaches()
	print("\nadventure: %d passed, %d failed" % [passes, failures.size()])
	for f in failures:
		print("  FAIL ", f)
	quit(1 if not failures.is_empty() else 0)


func check(cond: bool, msg: String) -> void:
	if cond: passes += 1
	else: failures.append(msg)


func _new() -> Dictionary:
	var world := AdventureWorld.load_default()
	var m := MachineBuilder.load_machine(world.machine, _reg.primary_names())
	var session := ShellSession.new(m, "player")
	var shell := Shell.new(session, _reg)
	var mgr := AdventureManager.new()
	mgr.machine_factory = func(mid): return MachineBuilder.load_machine(mid, _reg.primary_names())
	narration = []
	mgr.narrate.connect(func(t, _k): narration.append(t))
	var state := AdventureState.new()
	state.max_hp = world.max_hp; state.hp = world.max_hp
	mgr.prepare(world, state, session)
	return {"world": world, "session": session, "shell": shell, "mgr": mgr}


func _engage(ctx: Dictionary, node: String) -> void:
	ctx.mgr.engage(node)


func _run(ctx: Dictionary, line: String) -> ExecutionOutcome:
	var outcome: ExecutionOutcome = ctx.shell.run_line(line)
	ctx.mgr.observe(outcome)
	return outcome


func test_world_valid() -> void:
	var world := AdventureWorld.load_default()
	check(world.validate().is_empty(), "world validates: %s" % str(world.validate()))
	check(world.nodes.size() == 8, "eight nodes (%d)" % world.nodes.size())
	check(world.start == "home", "starts at home")
	for nid in ["gate", "swamp", "foundry", "archive", "cutting", "core"]:
		check(world.node(nid).get("battle", {}).has("hints"), "%s battle has hints" % nid)
		check(world.node(nid).get("battle", {}).has("learned"), "%s teaches something" % nid)


func test_full_playthrough() -> void:
	var ctx := _new()
	var mgr: AdventureManager = ctx.mgr

	_engage(ctx, "gate")
	check(mgr.in_battle(), "gate is a battle")
	_run(ctx, "chmod +x keycard.sh"); _run(ctx, "./keycard.sh")
	check(mgr.state.is_cleared("gate") and mgr.state.has_flag("keycard"), "gate cleared, keycard gained")
	check(narration.any(func(t): return t.contains("WHAT YOU LEARNED")), "victory teaches the command")

	_engage(ctx, "swamp")
	check(ctx.session.cwd == "/var/log", "swamp puts you in /var/log")
	_run(ctx, "grep 'Failed password' /var/log/auth.log | grep -o 'for [a-z]*' | sort | uniq -c | sort -rn | head -1")
	_run(ctx, "echo wraith > ~/intel.txt")
	check(mgr.state.is_cleared("swamp") and mgr.state.has_flag("intel"), "swamp cleared, intel gained")

	_engage(ctx, "foundry")
	check(_run(ctx, "ps aux").stdout_text().contains("xmrig"), "miner visible")
	_run(ctx, "kill 6660")
	check(mgr.state.is_cleared("foundry") and mgr.state.has_flag("cpu_freed"), "foundry cleared")

	_engage(ctx, "archive")
	var found := _run(ctx, "find /etc -name backup.cfg").stdout_text().strip_edges()
	check(found.contains("backup.cfg"), "find locates backup.cfg: %s" % found)
	_run(ctx, "mkdir ~/restored"); _run(ctx, "cp %s ~/restored/" % found)
	check(mgr.state.is_cleared("archive") and mgr.state.has_flag("config_key"), "archive cleared with find+cp")

	_engage(ctx, "cutting")
	check(ctx.session.cwd == "/var/data", "cutting puts you in /var/data")
	var top := _run(ctx, "cut -d, -f1 access.csv | sort | uniq -c | sort -rn | head -1").stdout_text()
	check(top.contains("nemo"), "cut|sort|uniq finds nemo: %s" % top.strip_edges())
	_run(ctx, "echo nemo > ~/culprit.txt")
	check(mgr.state.is_cleared("cutting") and mgr.state.has_flag("audit_key"), "cutting cleared with cut/sort/uniq")

	var d: Dictionary = mgr.visit_npc("gatekeeper")
	check(mgr.state.has_flag("sudo_access"), "gatekeeper grants sudo_access")
	check(ctx.session.machine.is_sudoer("player"), "player is now a sudoer")

	_engage(ctx, "core")
	_run(ctx, "sudo -i")
	check(ctx.session.user == "root", "sudo -i makes you root")
	_run(ctx, "rm /opt/initd-imposter/imposterd")
	_run(ctx, "kill %d" % _imposter(ctx))
	check(not mgr.is_active(), "boss defeated — adventure won")
	check(narration.any(func(t): return t.contains("YOU MADE IT")), "victory text shown")


func test_alternative_solutions() -> void:
	var cases := {
		"gate": ["chmod 755 keycard.sh", "bash keycard.sh"],
		"swamp": ["grep Failed /var/log/auth.log | tail -n 2", "echo wraith >> ~/intel.txt"],
		"foundry": ["kill 6660"],
		"cutting": ["grep root access.csv | head", "echo nemo > ~/culprit.txt"],
	}
	for nid in cases:
		var ctx := _new()
		ctx.mgr.engage(nid)
		if nid == "foundry":
			_run(ctx, "ps aux")
		for line in cases[nid]:
			_run(ctx, line)
		check(ctx.mgr.state.is_cleared(nid), "%s: alternative solution accepted" % nid)


func test_wrong_answers() -> void:
	var ctx := _new()
	ctx.mgr.engage("swamp")
	_run(ctx, "echo alice > ~/intel.txt")
	check(not ctx.mgr.state.is_cleared("swamp"), "wrong intruder rejected")
	ctx = _new()
	ctx.mgr.engage("archive")
	_run(ctx, "mkdir ~/restored")
	check(not ctx.mgr.state.is_cleared("archive"), "empty restored dir is not a fix")
	ctx = _new()
	ctx.mgr.engage("cutting")
	_run(ctx, "echo alice > ~/culprit.txt")
	check(not ctx.mgr.state.is_cleared("cutting"), "wrong culprit rejected")


func test_traps_and_reboot() -> void:
	var ctx := _new()
	var mgr: AdventureManager = ctx.mgr
	mgr.engage("foundry")
	var hp := mgr.state.hp
	_run(ctx, "kill 6120")  # the friendly backup daemon
	check(mgr.state.hp == hp - 7, "friendly fire costs 7 HP")
	check(not mgr.state.is_cleared("foundry"), "friendly fire does not clear the fight")
	_run(ctx, "kill 6660")
	check(mgr.state.is_cleared("foundry"), "killing the miner clears it")

	ctx.session.machine.users["player"]["groups"].append("sudo")
	mgr.engage("core")
	_run(ctx, "sudo -i")
	var before := mgr.state.hp
	_run(ctx, "kill %d" % _imposter(ctx))  # before removing the launcher -> respawn
	check(mgr.state.hp < before, "killing the boss early costs HP")
	check(_imposter(ctx) != -1, "the boss respawns from its launcher")
	check(mgr.is_active(), "not won while the launcher stands")
	_run(ctx, "rm /opt/initd-imposter/imposterd")
	_run(ctx, "kill %d" % _imposter(ctx))
	check(not mgr.is_active(), "won after removing the launcher then killing it")

	# drain HP to zero -> reboot
	var ctx2 := _new()
	var m2: AdventureManager = ctx2.mgr
	ctx2.session.machine.users["player"]["groups"].append("sudo")
	m2.engage("core")
	_run(ctx2, "sudo -i")
	var deaths := m2.state.deaths
	for i in 6:
		_run(ctx2, "kill %d" % _imposter(ctx2))
		if m2.state.deaths > deaths: break
	check(m2.state.deaths > deaths, "HP reaching 0 triggers a reboot")
	check(m2.state.hp == m2.state.max_hp, "reboot restores full HP")


func test_elevation_unwind() -> void:
	var ctx := _new()
	ctx.session.machine.users["player"]["groups"].append("sudo")
	ctx.mgr.engage("core")
	_run(ctx, "sudo -i")
	check(ctx.session.user == "root", "sudo -i elevates inside a fight")
	_run(ctx, "cd /etc")
	ctx.mgr.disengage()
	check(ctx.session.user == "player", "stepping away from a console drops root")
	check(ctx.session.home() == "/home/player", "home is the player's again")
	ctx.mgr.engage("gate")
	check(ctx.session.user == "player", "the next console opens as player")
	_run(ctx, "cd")
	check(ctx.session.cwd == "/home/player", "cd with no arg goes to player home, not /root")
	check(_run(ctx, "ls").stdout_text().contains("keycard.sh"), "ls shows the room, not a leaked /etc")


func test_nudges() -> void:
	# Hunting the buried file with ls should nudge the player toward find.
	var ctx := _new()
	ctx.mgr.engage("archive")
	narration = []
	_run(ctx, "ls /etc")
	check(narration.any(func(t): return t.contains("find /etc -name backup.cfg")), "archive nudges toward find after ls")
	# once find is used, the nudge condition no longer holds (and it is fire-once)
	var ctx2 := _new()
	ctx2.mgr.engage("archive")
	narration = []
	_run(ctx2, "find /etc -name backup.cfg")
	check(not narration.any(func(t): return t.contains("Buried means buried")), "no nudge once find is used")
	# swamp nudges toward grep
	var ctx3 := _new()
	ctx3.mgr.engage("swamp")
	narration = []
	_run(ctx3, "cat /var/log/auth.log")
	check(narration.any(func(t): return t.contains("grep")), "swamp nudges toward grep after cat")


func test_talk_teaches() -> void:
	var ctx := _new()
	var o: ExecutionOutcome = ctx.shell.run_line("talk grep")
	check(o.stdout_text().contains("teach you about"), "talk <command> is in-character")
	check(o.stdout_text().contains("print lines matching"), "talk grep teaches what grep does")
	check(o.stdout_text().contains("use it like"), "talk shows how to use it")
	var bad: ExecutionOutcome = ctx.shell.run_line("talk notacommand")
	check(bad.stdout_text().contains("don't know a command"), "talk of an unknown command is handled")


func _imposter(ctx: Dictionary) -> int:
	for p in ctx.session.machine.processes:
		if str(p.cmd).contains("imposterd"):
			return int(p.pid)
	return -1
