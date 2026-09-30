extends SceneTree
## Plays "The Ascent to Root" (skill worlds) through the manager API the World2D
## scene uses: collect every world's orbs, pass every trial, advance world to
## world, and win — all headless. Also checks orb-gating, nudges and the respawn.

var failures: Array = []
var passes := 0
var _reg: CommandRegistry
var narration: Array = []

const SOLUTIONS := [
	["chmod +x keycard.sh", "./keycard.sh"],
	["grep 'Failed password' /var/log/auth.log | grep -o 'for [a-z]*' | sort | uniq -c | sort -rn | head -1", "echo wraith > ~/intel.txt"],
	["ps aux", "kill 6660"],
	["find /etc -name backup.cfg", "mkdir ~/restored", "cp /etc/skel/.cache/hoard/deep/backup.cfg ~/restored/"],
	["cut -d, -f1 access.csv | sort | uniq -c | sort -rn | head -1", "echo nemo > ~/culprit.txt"],
	["sudo -i", "rm /opt/initd-imposter/imposterd", "kill 1313"],
]


func _initialize() -> void:
	_reg = CommandRegistry.create_default()
	test_world_valid()
	test_full_playthrough()
	test_orb_gating()
	test_wrong_answers()
	test_respawn_then_win()
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
	mgr.prepare(world, state, session)
	return {"world": world, "session": session, "shell": shell, "mgr": mgr}


func _run(ctx: Dictionary, line: String) -> ExecutionOutcome:
	var outcome: ExecutionOutcome = ctx.shell.run_line(line)
	ctx.mgr.observe(outcome)
	return outcome


func _collect_all(ctx: Dictionary, index: int) -> void:
	for i in ctx.mgr.orbs_total(index):
		ctx.mgr.collect_orb(index, i)


func test_world_valid() -> void:
	var world := AdventureWorld.load_default()
	check(world.validate().is_empty(), "world validates: %s" % str(world.validate()))
	check(world.count() == 6, "six worlds (%d)" % world.count())
	for i in world.count():
		check(not world.orbs(i).is_empty(), "world %d has orbs" % i)
		check(world.trial(i).has("learned"), "world %d trial teaches something" % i)
		check(not world.trial(i).get("hints", []).is_empty(), "world %d trial has hints" % i)


func test_full_playthrough() -> void:
	var ctx := _new()
	var mgr: AdventureManager = ctx.mgr
	for wi in mgr.world.count():
		check(mgr.current_index() == wi, "standing in world %d" % wi)
		_collect_all(ctx, wi)
		check(mgr.can_engage_trial(wi), "world %d trial unlocks once orbs are collected" % wi)
		mgr.engage_trial(wi)
		for line in SOLUTIONS[wi]:
			_run(ctx, line)
		check(mgr.is_passed(wi), "world %d trial passed" % wi)
		if wi < mgr.world.count() - 1:
			check(mgr.advance(), "portal opens to world %d" % (wi + 1))
	check(not mgr.is_active(), "passing the final trial wins the adventure")
	check(narration.any(func(t): return t.contains("WHAT YOU LEARNED")), "trials teach on success")


func test_orb_gating() -> void:
	var ctx := _new()
	var mgr: AdventureManager = ctx.mgr
	check(not mgr.can_engage_trial(0), "trial is locked before any orbs")
	mgr.collect_orb(0, 0)
	check(not mgr.can_engage_trial(0), "trial still locked with orbs missing")
	_collect_all(ctx, 0)
	check(mgr.can_engage_trial(0), "trial unlocks only once every orb is collected")
	check(mgr.state.has_skill("chmod"), "collecting an orb learns its skill")


func test_wrong_answers() -> void:
	var ctx := _new()
	ctx.mgr.enter_world(1)
	_collect_all(ctx, 1)
	ctx.mgr.engage_trial(1)
	_run(ctx, "echo alice > ~/intel.txt")
	check(not ctx.mgr.is_passed(1), "naming the wrong intruder does not pass the trial")

	var ctx2 := _new()
	ctx2.mgr.enter_world(2)
	_collect_all(ctx2, 2)
	ctx2.mgr.engage_trial(2)
	_run(ctx2, "kill 6120") # the friendly backup daemon
	check(not ctx2.mgr.is_passed(2), "killing the backup daemon does not pass the trial")
	check(narration.any(func(t): return t.contains("backup daemon")), "a nudge explains the mistake")
	_run(ctx2, "kill 6660")
	check(ctx2.mgr.is_passed(2), "killing the actual miner passes it")


func test_respawn_then_win() -> void:
	var ctx := _new()
	var mgr: AdventureManager = ctx.mgr
	mgr.enter_world(5)
	_collect_all(ctx, 5) # the sudo orb grants the sudo group
	check(ctx.session.machine.is_sudoer("player"), "the sudo orb makes you a sudoer")
	mgr.engage_trial(5)
	_run(ctx, "sudo -i")
	check(ctx.session.user == "root", "sudo -i makes you root in the final trial")
	_run(ctx, "kill 1313") # launcher still stands -> respawns, not won
	check(mgr.is_active() and not mgr.is_passed(5), "killing it early does not win — it respawns")
	check(_imposter(ctx) != -1, "the impostor respawns from its launcher")
	_run(ctx, "rm /opt/initd-imposter/imposterd")
	_run(ctx, "kill %d" % _imposter(ctx))
	check(not mgr.is_active(), "removing the launcher then killing it wins")
	check(mgr.world.outro.any(func(l): return str(l).contains("YOU MADE IT")), "the victory outro reads YOU MADE IT")


func test_talk_teaches() -> void:
	var ctx := _new()
	var o: ExecutionOutcome = ctx.shell.run_line("talk grep")
	check(o.stdout_text().contains("teach you about"), "talk <command> is in-character")
	check(o.stdout_text().contains("print lines matching"), "talk grep teaches what grep does")
	var bad: ExecutionOutcome = ctx.shell.run_line("talk notacommand")
	check(bad.stdout_text().contains("don't know a command"), "talk of an unknown command is handled")


func _imposter(ctx: Dictionary) -> int:
	for p in ctx.session.machine.processes:
		if str(p.cmd).contains("imposterd"):
			return int(p.pid)
	return -1
