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


func _drain_dialogue(world) -> void:
	for i in 12:
		if not world._dialogue.visible:
			break
		world._advance_dialogue()


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
	# This test asserts on the English UI, so pin the locale regardless of any
	# language the developer has saved locally. Go through Game.set_locale so the
	# challenge library is RELOADED in English — just setting the I18n map leaves
	# content that was cached at boot (in the dev's saved language) untranslated.
	Game.set_locale("en")
	menu.journey_requested.emit("beginner", false)
	await _frames(3)
	var screen = main.host.get_child(main.host.get_child_count() - 1)
	check(screen.name == "GameScreen", "game screen shown")
	check(Game.challenges.current != null and Game.challenges.current.id == "t01_identity", "first challenge active")

	Game.submit("lss")
	Game.submit(":hint")
	check(Game.challenges.hints_shown() == 1, "hint via :hint")
	Game.submit("sudo whoami")
	var solved_by_editor := false
	for i in Game.library.order.size():
		var c: Challenge = Game.challenges.current
		if c.id == "l2_note":
			# Solve a real campaign challenge through the editor, not a command:
			# open nano, type the line, save. Saving must re-grade and complete it.
			Game.submit("nano ~/handoff.txt")
			await _frames(1)
			check(screen._overlays.editor.visible, "nano opened the editor on the challenge file")
			screen._overlays.editor._text.text = "deploy at dawn\n"
			screen._overlays.editor._save()
			await _frames(1)
			check(screen._overlays.editor._saved_once, "the editor reported a successful save")
			screen._overlays.editor._request_exit()
			await _frames(1)
			solved_by_editor = Game.challenges.completed_pending_next
		else:
			for line in c.solution.split("\n"):
				screen.terminal.input.text = line
				screen.terminal._on_submitted(line)
				await _frames(1)
		check(Game.challenges.completed_pending_next, "%s completed via UI" % c.id)
		screen.terminal._on_submitted("") # Enter to continue
		await _frames(1)
	check(solved_by_editor, "editing a file in nano completes a campaign challenge (grade-on-save)")
	check(Game.profile.completed.size() == Game.library.order.size(), "whole campaign completed (%d/%d)" % [Game.profile.completed.size(), Game.library.order.size()])
	check(Game.challenges.current == null, "campaign finished")
	check(Game.profile.xp > 1000, "xp awarded (%d)" % Game.profile.xp)
	for a in ["first_command", "who_am_i", "sudo_please", "pipe_dream", "permission_denied", "tutorial_done"]:
		check(Game.profile.achievements.has(a), "achievement %s" % a)
	var text: String = screen.terminal.output.get_parsed_text()
	check(text.contains("OBJECTIVE COMPLETE"), "completion printed")
	check(text.contains("THE ROAD CONTINUES"), "ending printed")
	check(text.contains("Level 1 — The Filesystem"), "Level 1 banner shown during the campaign")
	check(text.contains("YOU MADE IT"), "the finale crowns the player")
	check(Game.progression.current_rank().name == "sudo", "final rank is sudo (%s, %d XP)" % [Game.progression.current_rank().name, Game.profile.xp])
	check(Game.profile.achievements.has("root_access"), "Root Access achievement unlocked")
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

	# Journey & stats screen, and a checkpoint jump back to a cleared challenge.
	menu._open_journey()
	await _frames(1)
	check(menu._journey_page.visible, "Journey screen opens")
	check(menu._journey_list.get_child_count() > 10, "journey lists stats and per-level checkpoints")
	menu.checkpoint_requested.emit("t01_identity")
	await _frames(3)
	screen = main.host.get_child(main.host.get_child_count() - 1)
	check(screen.name == "GameScreen", "a checkpoint jumps into the game")
	check(Game.challenges.current != null and Game.challenges.current.id == "t01_identity", "and starts at the chosen checkpoint")
	Game.submit(":menu")
	await _frames(3)
	menu = main.host.get_child(main.host.get_child_count() - 1)

	menu.practice_requested.emit()
	await _frames(3)
	screen = main.host.get_child(main.host.get_child_count() - 1)
	Game.submit("cat README.lab")
	Game.submit("chmod +x scripts/hello.sh && ./scripts/hello.sh world")
	await _frames(2)
	check(screen.terminal.output.get_parsed_text().contains("Hello, world!"), "practice lab script runs")

	# The text editor: nano opens an overlay; saving writes through the session.
	Game.submit("nano ~/mynote.txt")
	await _frames(2)
	check(screen._overlays.editor.visible, "nano opens the editor overlay")
	check(screen._overlays.editor._text.text == "", "a new file opens empty in the editor")
	var edited_path: String = screen._overlays.editor._path
	screen._overlays.editor._text.text = "edited in nano\n"
	screen._overlays.editor._save()
	await _frames(1)
	var saved_node = Game.session.machine.vfs.get_node_at(edited_path)
	check(saved_node != null and saved_node.content == "edited in nano\n", "saving (^O) writes the buffer to disk")
	screen._overlays.editor._request_exit()
	await _frames(1)
	check(not screen._overlays.editor.visible, "exiting (^X) closes the editor")
	Game.submit("nano ~/mynote.txt")
	await _frames(1)
	check(screen._overlays.editor._text.text == "edited in nano\n", "reopening an existing file shows its saved content")
	screen._overlays.editor._request_exit()
	await _frames(1)

	# less: an interactive pager overlay that scrolls and quits.
	Game.submit("less README.lab")
	await _frames(2)
	check(screen._overlays.pager.visible, "less opens the pager overlay")
	check(screen._overlays.pager._text.text.length() > 0, "the pager shows the file")
	screen._overlays.pager._close()
	await _frames(1)
	check(not screen._overlays.pager.visible, "q closes the pager")

	# tail -f: a live follow view that streams new lines until stopped.
	Game.submit("echo following-demo > ~/live.log")
	await _frames(1)
	Game.submit("tail -f ~/live.log")
	await _frames(2)
	check(screen._overlays.pager.visible, "tail -f opens the follow view")
	var lines_before: int = screen._overlays.pager._text.get_line_count()
	screen._overlays.pager._tick_feed()
	screen._overlays.pager._tick_feed()
	await _frames(1)
	check(screen._overlays.pager._text.get_line_count() > lines_before, "new lines stream into the follow view")
	screen._overlays.pager._close()
	await _frames(1)
	check(not screen._overlays.pager.visible, "Ctrl-C / q stops following")

	# su: an interactive masked password prompt that switches the user.
	# (The practice lab's bob has the password "builder".)
	check(Game.session.user == "player", "in the lab as player")
	Game.submit("su bob")
	await _frames(2)
	check(screen._overlays.prompt.visible, "su opens the password prompt")
	screen._overlays.prompt._on_submit("builder")
	await _frames(2)
	check(Game.session.user == "bob", "the right password switches the user")
	Game.submit("exit")
	await _frames(2)
	check(Game.session.user == "player", "exit returns to the previous user")
	Game.submit("su bob")
	await _frames(2)
	screen._overlays.prompt._on_submit("wrong")
	await _frames(2)
	check(Game.session.user == "player", "a wrong password does not switch the user")

	# A fresh profile loaded from disk keeps everything.
	var reloaded := SaveManager.load_profile()
	SaveManager._cache = {}
	reloaded = SaveManager.load_profile()
	check(reloaded.completed.size() == Game.library.order.size(), "completion persisted")
	check(reloaded.xp == Game.profile.xp, "xp persisted")
	check(reloaded.achievements.size() == Game.profile.achievements.size(), "achievements persisted")
	check(not SaveManager.load_world("campaign").is_empty(), "campaign world persisted")

	# --- Adventure (skill worlds) through the real World2D scene ---
	Game.submit(":menu"); await _frames(3)
	menu = main.host.get_child(main.host.get_child_count() - 1)
	menu.adventure_requested.emit(); await _frames(4)
	var world = main.host.get_child(main.host.get_child_count() - 1)
	check(world.name == "World2D", "World2D scene shown for adventure")
	check(world._player != null, "player character spawned")
	check(world._orbs.size() == Game.adventure.orbs_total(0), "world 1 skill orbs placed (%d)" % world._orbs.size())
	check(world._console != null and world._portal != null, "trial console and portal placed")
	check(world._dialogue.visible, "world intro shown on entry")
	_drain_dialogue(world)
	await _frames(1)
	check(not world._player.input_locked, "input freed after the intro")

	# platforming: run, land on the ground, jump, and bump into the end wall
	await _phys(12)
	check(world._player.is_on_floor(), "gravity settles the player onto the ground")
	var start_pos: Vector2 = world._player.global_position
	Input.action_press("move_right")
	await _phys(18)
	Input.action_release("move_right")
	await _frames(1)
	check(world._player.global_position.x > start_pos.x + 5.0, "player runs right")

	# Measure the real jump arc and hold the level generator to it: if a full
	# jump can't clear a ledge, the orbs are unreachable and the mode is broken.
	var ground_y: float = world._player.global_position.y
	var peak: float = ground_y
	Input.action_press("jump")
	for i in 40:
		await get_tree().physics_frame
		peak = minf(peak, world._player.global_position.y)
	var rise: float = ground_y - peak
	var needed: float = world.PLATFORM_RISE * world.TILE
	check(rise > needed, "a full jump (%d px) clears a ledge (%d px)" % [int(rise), int(needed)])
	Input.action_release("jump")
	await _phys(60)
	check(world._player.is_on_floor(), "and gravity brings them back down")
	check(absf(world._player.global_position.y - ground_y) < 2.0, "landing returns to the same ground height")

	world._player.global_position = Vector2(world.TILE * 1.5, world.GROUND_ROW * world.TILE)
	Input.action_press("move_left")
	await _phys(20)
	Input.action_release("move_left")
	check(world._player.global_position.x > world.TILE, "wall blocks the player (no escaping the level)")

	# falling into a pit puts you back on solid ground instead of ending the run
	var rescued_from: Vector2 = world._player.global_position
	world._player.global_position = Vector2(rescued_from.x, (world.LEVEL_H + 5) * world.TILE)
	await _phys(4)
	check(world._player.global_position.y < world.LEVEL_H * world.TILE, "falling off the level respawns the player on solid ground")

	# take every skill orb — each one teaches, then opens a prompt to try it on
	var learned_before: int = Game.adventure.state.skills.size()
	world._player.global_position = world._orbs[0].node.global_position
	await _frames(2)
	check(world._dialogue.visible, "touching an orb shows what the command does")
	var first_skill: String = str(Game.adventure.state.skills[Game.adventure.state.skills.size() - 1])
	_drain_dialogue(world)
	await _frames(2)
	check(world._overlay.visible, "the lesson hands over to a real prompt")
	check(world._overlay_mode == "practice", "that prompt is practice, not the trial")
	check(world._overlay_title.text.contains(first_skill), "practice prompt is titled for the skill: '%s'" % world._overlay_title.text)
	check(not Game.adventure.in_trial(), "practice never opens a trial, so nothing is graded")
	Game.submit("echo just poking around"); await _frames(2)
	check(not world._practice_done, "an unrelated command doesn't count as trying the skill")
	Game.submit(str(Game.adventure.world.orbs(0)[0].get("example", ""))); await _frames(2)
	check(world._practice_done, "running the command is recognised as having tried it")

	# Interactive programs must also work inside the Ascent, not just the campaign:
	# nano opens the editor overlay above the trial console, saves through the live
	# session, and hands focus back to the world terminal when it closes.
	Game.submit("nano ascent_note.txt"); await _frames(2)
	check(world._overlays.editor.visible, "nano opens the editor overlay inside the adventure world")
	world._overlays.editor._text.text = "root is near\n"
	world._overlays.editor._save(); await _frames(1)
	check(Game.session.machine.vfs.exists(Game.session.resolve("ascent_note.txt")), "editing in the adventure world writes through the live session")
	world._overlays.editor._request_exit(); await _frames(2)
	check(not world._overlays.editor.visible, "closing nano returns to the adventure console")

	world._close_terminal(); await _frames(2)
	check(not world._overlay.visible, "Esc leaves practice and returns to the course")
	check(not world._player.input_locked, "and hands control back to the player")

	for guard in 10:
		if world._orbs.is_empty():
			break
		world._player.global_position = world._orbs[0].node.global_position
		await _frames(2)
		_drain_dialogue(world)
		await _frames(2)
		if world._overlay.visible:
			world._close_terminal()
		await _frames(1)
	# Every course must be climbable: orbs sit on ledges, ledges are within one
	# jump of a lower surface, and pits are narrow enough to clear.
	var bad_orb := ""
	var bad_ledge := ""
	var bad_pit := ""
	for wi in Game.adventure.world.count():
		var plan: Dictionary = world._plan_level(wi)
		var solid: Dictionary = plan.solid
		# Columns a lift crosses: an orb may hang over one, and the pit under it
		# is allowed to be wider than a jump, because the lift is the way across.
		var lift_cols: Dictionary = {}
		for l in plan.lifts:
			for x in range(int(l.from) - 1, int(l.to) + 2):
				lift_cols[x] = true
		for cell in plan.orb_cells:
			if not solid.has(Vector2i(cell.x, cell.y + 1)) and not lift_cols.has(cell.x):
				bad_orb = "world %d orb at %s floats with no ledge or lift under it" % [wi + 1, cell]
		# Exposed tops only — those are the surfaces you can actually stand on.
		var surfaces: Dictionary = {}
		var rows_above: Dictionary = {}   # row -> [x] for ledges above the ground
		for cell in solid:
			var c: Vector2i = cell
			if solid.has(Vector2i(c.x, c.y - 1)):
				continue
			surfaces[c] = true
			if c.y < world.GROUND_ROW and c.x > 0 and c.x < int(plan.w) - 1:
				var xs: Array = rows_above.get(c.y, [])
				xs.append(c.x)
				rows_above[c.y] = xs
		# A ledge is a contiguous run: reachable if ANY of its tiles is within a
		# jump of a lower surface, since you can walk along the rest of it.
		for row in rows_above:
			var xs: Array = rows_above[row]
			xs.sort()
			var run: Array = []
			for i in xs.size():
				run.append(xs[i])
				if i < xs.size() - 1 and xs[i + 1] == xs[i] + 1:
					continue
				var reachable := false
				for x in run:
					for dx in range(-3, 4):
						for dy in range(1, world.PLATFORM_RISE + 1):
							if surfaces.has(Vector2i(int(x) + dx, int(row) + dy)):
								reachable = true
				if not reachable:
					bad_ledge = "world %d ledge on row %d at x%s is out of jump range" % [wi + 1, row, str(run)]
				run = []
		var run := 0
		for x in int(plan.w):
			if solid.has(Vector2i(x, world.GROUND_ROW)):
				run = 0
			elif lift_cols.has(x):
				run = 0
			else:
				run += 1
				if run > 3:
					bad_pit = "world %d has a %d-tile pit at x=%d with no lift" % [wi + 1, run, x]
	check(bad_orb == "", "every orb sits on a ledge (%s)" % bad_orb)
	check(bad_ledge == "", "every ledge is within one jump of a lower surface (%s)" % bad_ledge)
	check(bad_pit == "", "no pit is wider than a jump (%s)" % bad_pit)

	check(Game.adventure.all_orbs_collected(0), "all world-1 orbs collected by reaching them")
	check(Game.adventure.state.skills.size() > learned_before, "collecting orbs learns skills")
	check(Game.adventure.can_engage_trial(0), "trial unlocks once every orb is collected")

	# engage the trial console and solve it with real Linux commands
	world._player.global_position = world._console.global_position + Vector2(0, 44)
	await _frames(2)
	world._interact(world._console)
	await _frames(2)
	check(world._overlay.visible, "terminal overlay opens at the trial console")
	# The trial must open with its briefing — objective, kit, hint prompt — not a
	# blank console. It once opened blank: engage_trial narrated the objective
	# before the overlay was visible, so _on_narrate dropped the whole intro.
	# The briefing is ~200 chars; a dropped one leaves the console empty.
	# (get_parsed_text() is unreliable headless, so count characters instead.)
	world._terminal.flush()
	check(world._terminal.output.get_total_character_count() > 80,
		"the trial opens with its briefing, not a blank console (%d chars)"
		% world._terminal.output.get_total_character_count())
	Game.submit("cd /var"); await _frames(1)
	check(world._terminal.prompt_path.text.contains("/var"), "overlay prompt follows cd: '%s'" % world._terminal.prompt_path.text)
	Game.submit("cd"); await _frames(1)
	Game.submit("chmod +x keycard.sh"); Game.submit("./keycard.sh"); await _frames(2)
	check(Game.adventure.is_passed(0), "world-1 trial passed through the 2D console")
	check(world._console.is_cleared(), "console shows as cleared")
	world._close_terminal(); await _frames(2)
	check(not world._overlay.visible, "closing steps back to the world")
	check(not world._player.input_locked, "player can move again after the trial")

	# step through the portal to world 2
	world._player.global_position = world._portal.global_position + Vector2(0, 44)
	await _frames(2)
	world._interact(world._portal)
	await _frames(3)
	check(Game.adventure.current_index() == 1, "portal advances to world 2")
	check(world._orbs.size() == Game.adventure.orbs_total(1), "world 2 room rebuilt with its own orbs")

	# World 2 is the first with hazards. Touching one must cost progress, never
	# the run — there is no death in this mode and there must never be one.
	_drain_dialogue(world)
	await _phys(8)
	# Every sprite the world asks for must exist. A missing one doesn't crash —
	# it silently degrades to a placeholder that nobody notices until a
	# screenshot, which is exactly the kind of rot a test should catch.
	var sprite_names: Array = ["spikes", "crate", "console", "console_done", "door"]
	for colour in ["blue", "red", "green", "orange", "violet"]:
		for role in ["_floor", "_floor_alt", "_wall", "_wall_alt"]:
			sprite_names.append(colour + role)
	for i in 4:
		sprite_names.append("rover_%d" % i)
		sprite_names.append("burst_%d" % i)
	var missing: Array = []
	for n in sprite_names:
		if not SpriteFactory.has(str(n)):
			missing.append(n)
	check(missing.is_empty(), "every sprite the world uses exists (missing: %s)" % str(missing))
	# And every palette a world names must have a full tile set behind it.
	var bad_palette := ""
	for wi in Game.adventure.world.count():
		var pal: String = world._palette_for(wi)
		if not SpriteFactory.has(pal + "_floor"):
			bad_palette = "world %d asks for palette '%s', which has no tiles" % [wi + 1, pal]
	check(bad_palette == "", "every world's palette has tiles (%s)" % bad_palette)

	check(world._hazards.size() > 0, "world 2 has hazards on its course (%d)" % world._hazards.size())
	var skills_before: int = Game.adventure.state.skills.size()
	var hazard = world._hazards[0]
	check(hazard.is_live(), "a spike strip is always dangerous")
	world._player.global_position = hazard.global_position
	await _phys(4)
	await _frames(2)
	check(world._player.global_position.distance_to(hazard.global_position) > 60.0,
		"touching a hazard sets the player back to solid ground")
	check(Game.adventure.current_index() == 1, "a hazard costs progress, not the world")
	check(Game.adventure.state.skills.size() == skills_before, "and costs no skills")
	check(world._hazard_grace > 0.0, "a setback grants brief grace, so you can't be re-hit instantly")

	# save persists the adventure
	Game.save_now()
	check(SaveManager.load_world("adventure").has("adv_state"), "adventure state persisted")

	# fast-forward to the final world (the Throne) and win it
	var throne := Game.adventure.world.count() - 1
	for i in throne:
		Game.adventure.state.mark_passed(str(Game.adventure.world.world_at(i).get("id", "")))
	Game.adventure.state.world_index = throne
	world._load_world(throne)
	await _frames(2)
	_drain_dialogue(world)
	for guard in 10:
		if world._orbs.is_empty():
			break
		world._player.global_position = world._orbs[0].node.global_position
		await _frames(2)
		_drain_dialogue(world)
		await _frames(2)
		if world._overlay.visible:
			world._close_terminal()
		await _frames(1)
	check(Game.session.machine.is_sudoer("player"), "the sudo orb made the player a sudoer")
	world._interact(world._console)
	await _frames(2)
	check(world._overlay.visible, "final trial console opens")
	Game.submit("sudo -i")
	Game.submit("rm /opt/initd-imposter/imposterd")
	var imp := -1
	for pr in Game.session.machine.processes:
		if str(pr.cmd).contains("imposterd"): imp = int(pr.pid)
	Game.submit("kill %d" % imp)
	await _frames(3)
	check(not Game.adventure.is_active(), "final trial won the adventure in 2D")
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
