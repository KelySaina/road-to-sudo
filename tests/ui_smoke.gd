extends Node
## UI smoke test: boots the real main scene (autoloads included), plays the
## whole campaign through Game.submit() like the terminal does, visits every
## menu page, then quits with status 0/1.
##   godot --headless --path . res://tests/ui_smoke.tscn

var failures: Array = []
var _finished := false


func _ready() -> void:
	# Watchdog: a script error inside the coroutine must fail, never hang.
	get_tree().create_timer(90.0).timeout.connect(func():
		print("UI smoke: TIMEOUT (a script error probably aborted the run)")
		get_tree().quit(2))
	SaveManager.save_path = "user://smoke_test_save.json"
	SaveManager.delete_save()
	Game.reset_progress()
	await _run()
	check(_finished, "smoke run reached the end (a script error aborted it otherwise)")
	SaveManager.delete_save()
	print("UI smoke: %s" % ("OK" if failures.is_empty() else "FAILED"))
	for f in failures:
		print("  FAIL ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func _key(unicode: int, keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.pressed = pressed
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.unicode = unicode
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find_obj(world, node_id: String):
	for it in world._objects:
		if it.node_id == node_id:
			return it
	return null


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var main: Control = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _frames()
	var menu = main.host.get_child(main.host.get_child_count() - 1)
	check(menu.name == "MainMenu", "menu shown first")
	check(menu.continue_button.disabled, "no save -> continue disabled")
	menu._open_new_journey()
	menu._open_achievements()
	menu._open_settings()
	menu._show_home()
	await _frames()

	var achievements_seen: Array = []
	EventBus.achievement_unlocked.connect(func(a): achievements_seen.append(a.id))
	menu.journey_requested.emit("beginner", false)
	await _frames(3)
	var screen = main.host.get_child(main.host.get_child_count() - 1)
	check(screen.name == "GameScreen", "game screen shown")
	check(Game.challenges.current != null and Game.challenges.current.id == "t01_identity", "first challenge active")

	Game.submit("lss")
	Game.submit(":hint")
	check(Game.challenges.hints_shown() == 1, "hint via :hint")
	Game.submit("sudo whoami")
	for i in Game.library.order.size():
		var c: Challenge = Game.challenges.current
		for line in c.solution.split("\n"):
			screen.terminal.input.text = line
			screen.terminal._on_submitted(line)
			await _frames(1)
		check(Game.challenges.completed_pending_next, "%s completed via UI" % c.id)
		screen.terminal._on_submitted("") # Enter to continue
		await _frames(1)
	check(Game.profile.completed.size() == 10, "all ten completed (%d)" % Game.profile.completed.size())
	check(Game.challenges.current == null, "campaign finished")
	check(Game.profile.xp > 1000, "xp awarded (%d)" % Game.profile.xp)
	for a in ["first_command", "who_am_i", "sudo_please", "pipe_dream", "permission_denied", "tutorial_done"]:
		check(Game.profile.achievements.has(a), "achievement %s" % a)
	var text: String = screen.terminal.output.get_parsed_text()
	check(text.contains("OBJECTIVE COMPLETE"), "completion printed")
	check(text.contains("END OF LEVEL 0"), "ending printed")
	check(text.contains("Did you mean"), "typo suggestion printed")

	# Tab completion through the widget.
	screen.terminal.input.text = "cat /etc/pas"
	screen.terminal.input.caret_column = screen.terminal.input.text.length()
	screen.terminal._complete()
	check(screen.terminal.input.text == "cat /etc/passwd ", "tab completes paths: '%s'" % screen.terminal.input.text)
	screen.terminal.input.text = "whoa"
	screen.terminal.input.caret_column = 4
	screen.terminal._complete()
	check(screen.terminal.input.text == "whoami ", "tab completes commands")

	# Real key events through the viewport: typing, Tab, Enter, F1.
	screen.terminal.input.clear()
	screen.terminal.focus_input()
	await _frames(1)
	for ch in "ech":
		await _key(ch.unicode_at(0), KEY_NONE)
	await _key(0, KEY_TAB)
	check(screen.terminal.input.text == "echo ", "Tab key completes: '%s'" % screen.terminal.input.text)
	check(screen.terminal.input.has_focus(), "Tab keeps focus in the prompt")
	for ch in "keys-ok":
		await _key(ch.unicode_at(0), KEY_NONE)
	await _key(0, KEY_ENTER)
	check(screen.terminal.output.get_parsed_text().contains("keys-ok\n"), "Enter key submits the line")
	await _frames(2)
	check(screen.terminal.input.has_focus(), "prompt keeps focus after Enter (no click needed to type again)")
	# even if focus drifts away for a frame, the next key must refocus AND type
	screen.terminal.input.clear()
	screen.terminal.input.release_focus()
	await _frames(1)
	await _key("q".unicode_at(0), KEY_NONE)
	check(screen.terminal.input.text == "q", "a key after lost focus refocuses and types (not eaten): '%s'" % screen.terminal.input.text)
	check(screen.terminal.input.has_focus(), "focus reclaimed by that keystroke")
	screen.terminal.input.clear()
	await _key(0, KEY_UP)
	check(screen.terminal.input.text == "echo keys-ok", "Up recalls history: '%s'" % screen.terminal.input.text)
	await _key(0, KEY_F1)
	screen.terminal.flush()
	check(screen.terminal.output.get_parsed_text().contains("No active objective"), "F1 triggers :hint")

	# Save, back to menu, continue.
	Game.submit(":menu")
	await _frames(3)
	menu = main.host.get_child(main.host.get_child_count() - 1)
	check(menu.name == "MainMenu", "back at menu")
	check(menu.has_node("%AdventureButton"), "menu has an Adventure entry")
	check(not menu.continue_button.disabled, "save exists -> continue enabled")
	menu.practice_requested.emit()
	await _frames(3)
	screen = main.host.get_child(main.host.get_child_count() - 1)
	Game.submit("cat README.lab")
	Game.submit("chmod +x scripts/hello.sh && ./scripts/hello.sh world")
	await _frames(2)
	check(screen.terminal.output.get_parsed_text().contains("Hello, world!"), "practice lab script runs")

	# A fresh profile loaded from disk keeps everything.
	var reloaded := SaveManager.load_profile()
	SaveManager._cache = {}
	reloaded = SaveManager.load_profile()
	check(reloaded.completed.size() == 10, "completion persisted")
	check(reloaded.xp == Game.profile.xp, "xp persisted")
	check(reloaded.achievements.size() == Game.profile.achievements.size(), "achievements persisted")
	check(not SaveManager.load_world("campaign").is_empty(), "campaign world persisted")

	# --- Adventure (2D RPG) through the real World2D scene ---
	Game.submit(":menu"); await _frames(3)
	menu = main.host.get_child(main.host.get_child_count() - 1)
	menu.adventure_requested.emit(); await _frames(4)
	var world = main.host.get_child(main.host.get_child_count() - 1)
	check(world.name == "World2D", "World2D scene shown for adventure")
	check(world._player != null, "player character spawned")
	check(world._objects.size() >= 6, "interactables placed (%d)" % world._objects.size())
	check(world._dialogue.visible, "intro dialogue shown on entry")
	while world._dialogue.visible:
		world._advance_dialogue()
	await _frames(1)
	check(not world._player.input_locked, "input freed after the intro")

	# movement + wall collision
	var start_pos: Vector2 = world._player.global_position
	Input.action_press("move_right")
	await _phys(18)
	Input.action_release("move_right")
	await _frames(1)
	check(world._player.global_position.x > start_pos.x + 5.0, "player walks right")
	# shove into the left wall of the room and confirm it stops
	world._player.global_position = Vector2(world.TILE * 1.5, world.TILE * 5.5)
	Input.action_press("move_left")
	await _phys(20)
	Input.action_release("move_left")
	check(world._player.global_position.x > world.TILE, "wall blocks the player (no escaping the room)")

	# engage the gate console and solve it with real Linux commands
	var gate_obj = _find_obj(world, "gate")
	world._player.global_position = gate_obj.global_position + Vector2(0, 44)
	await _frames(2)
	world._interact(gate_obj)
	await _frames(2)
	check(world._overlay.visible, "terminal overlay opens at a console")
	check(Game.adventure.state.current == "gate", "engaged the gate node")
	Game.submit("cd /var"); await _frames(1)
	check(world._terminal.prompt_path.text.contains("/var"), "overlay prompt follows cd: '%s'" % world._terminal.prompt_path.text)
	Game.submit("cd"); await _frames(1)
	Game.submit("chmod +x keycard.sh"); Game.submit("./keycard.sh"); await _frames(2)
	check(Game.adventure.state.is_cleared("gate"), "gate cleared through the 2D console")
	check(gate_obj.is_cleared(), "gate console shows as cleared")
	var gate_door_open := false
	for b in world._blockers:
		if b.data.get("needs_cleared", "") == "gate":
			gate_door_open = b.is_open()
	check(gate_door_open, "the door to the Swamp opens after clearing the gate")
	world._close_terminal(); await _frames(2)
	check(not world._overlay.visible, "closing steps back to the world")
	check(not world._player.input_locked, "player can move again after the fight")

	# talk to an NPC
	var tux = _find_obj(world, "home")
	world._interact(tux)
	await _frames(1)
	check(world._dialogue.visible, "talking to an NPC opens a dialogue box")
	for i in 8:
		if not world._dialogue.visible: break
		world._advance_dialogue()
	check(not world._dialogue.visible, "advancing dialogue closes it")

	# save persists the adventure
	Game.save_now()
	check(SaveManager.load_world("adventure").has("adv_state"), "adventure state persisted")

	# fast-forward to the boss and win
	for f in ["keycard", "intel", "cpu_freed"]:
		Game.adventure.state.add_flag(f)
	for n in ["gate", "swamp", "foundry", "archive", "cutting"]:
		Game.adventure.state.cleared[n] = true
	var gk = _find_obj(world, "gatekeeper")
	world._interact(gk)  # grants sudo_access
	check(Game.adventure.state.has_flag("sudo_access"), "gatekeeper grants sudo")
	while world._dialogue.visible:
		world._advance_dialogue()
	var core_obj = _find_obj(world, "core")
	world._interact(core_obj)
	await _frames(2)
	check(world._overlay.visible, "boss console opens")
	Game.submit("sudo -i")
	Game.submit("rm /opt/initd-imposter/imposterd")
	var imp := -1
	for pr in Game.session.machine.processes:
		if str(pr.cmd).contains("imposterd"): imp = int(pr.pid)
	Game.submit("kill %d" % imp)
	await _frames(3)
	check(not Game.adventure.is_active(), "boss defeated — adventure won in 2D")
	check(Game.profile.achievements.has("the_ascent"), "The Ascent achievement unlocked")

	# Expert + skip basics: starts at t08, no solutions, :skip works.
	Game.new_journey("expert", true)
	check(Game.challenges.current.id == "t08_needle", "skip basics starts at t08")
	check(Game.profile.skipped.size() == 7, "seven challenges marked skipped")
	check(Game.profile.unlocked_commands.has("cd"), "skipped challenges still unlock their commands")
	check(Game.challenges.current.objective_for("expert").begins_with("Brute force"), "expert objective text")
	Game.submit(":hint")
	Game.submit(":hint")
	check(Game.challenges.hints_shown() == 1, "expert: a single hint")
	check(not Game.challenges.can_reveal_solution(), "expert: no solution")
	Game.submit(":skip")
	check(Game.challenges.current.id == "t09_permission", ":skip advances")

	# Save mid-challenge, continue: partial work survives, setup is not re-applied.
	Game.new_journey("beginner", false)
	for line in ["whoami", "", "pwd", "", "ls", "cat welcome.txt", "", "cat .hidden_note", "", "cd /var/log", "ls", "", "mkdir ~/projects"]:
		Game.submit(line)
	check(Game.challenges.current.id == "t06_build", "reached t06")
	Game.save_now()
	SaveManager._cache = {}
	Game.continue_journey()
	check(Game.challenges.current.id == "t06_build", "continue resumes t06")
	check(Game.session.machine.vfs.is_dir("/home/player/projects"), "partial work survives continue")
	check(Game.session.cwd == "/var/log", "cwd survives continue")
	Game.submit("touch ~/projects/todo.txt")
	check(Game.challenges.completed_pending_next, "resumed challenge completes")
	Game.submit("")
	Game.submit("rm -r ~/projects")
	Game.submit(":reset")
	check(Game.session.machine.vfs.is_dir("/home/player/projects"), ":reset restores the challenge start state")
	_finished = true
