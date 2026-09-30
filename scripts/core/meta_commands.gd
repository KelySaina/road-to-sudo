class_name MetaCommands
extends RefCounted
## Game-level commands typed with a leading colon (:hint, :reset...).
## They are deliberately NOT Linux commands, so the Linux layer stays honest.

var game: Node # the Game autoload


func _init(p_game: Node) -> void:
	game = p_game


func run(line: String) -> ExecutionOutcome:
	var outcome := ExecutionOutcome.new()
	outcome.line = line
	var parts := line.strip_edges().trim_prefix(":").split(" ", false)
	var verb: String = parts[0].to_lower() if parts.size() > 0 else "help"
	var challenges: ChallengeManager = game.challenges
	match verb:
		"hint", "h":
			if game.mode != "campaign" or challenges.current == null:
				_sys(outcome, "No active objective. (Practice Lab has no hints — just curiosity.)")
			else:
				var text := challenges.request_hint()
				if text == "":
					if challenges.can_reveal_solution():
						_sys(outcome, "No hints left. Type :solution to see one possible answer (no bonus XP).")
					elif not game.difficulty.allow_solution:
						_sys(outcome, "No hints left. %s mode trusts you. Observe, hypothesize, verify." % game.difficulty.label)
					else:
						_sys(outcome, "No more hints for this one.")
		"solution", "sol":
			if challenges.current == null:
				_sys(outcome, "No active objective.")
			elif not game.difficulty.allow_solution:
				_sys(outcome, "Solutions are disabled in %s mode." % game.difficulty.label)
			elif not challenges.can_reveal_solution():
				_sys(outcome, "Try the hints first (:hint). You have %d left." % (challenges.hints_available() - challenges.hints_shown()))
			else:
				outcome.write("sys", "One possible solution:\n", "tip")
				outcome.write("sys", "    " + challenges.reveal_solution().replace("\n", "\n    ") + "\n", "solution")
				outcome.write("sys", "(Other approaches are just as valid — the game checks the result, not the keystrokes.)\n", "dim")
		"objective", "obj", "o":
			if challenges.current == null:
				_sys(outcome, "No active objective.")
			else:
				game.replay_briefing()
		"reset":
			if challenges.reset():
				game.on_machine_reset()
				_sys(outcome, "Machine restored to the start of \"%s\"." % challenges.current.title)
			else:
				_sys(outcome, "Nothing to reset here.")
		"skip":
			if not game.difficulty.allow_skip:
				_sys(outcome, "Skipping is available in Normal and Expert modes.")
			elif challenges.current == null:
				_sys(outcome, "Nothing to skip.")
			else:
				game.skip_current()
		"next", "n":
			if challenges.completed_pending_next:
				game.advance()
			else:
				_sys(outcome, "Finish the current objective first (or :hint).")
		"menu", "quit", "q":
			game.save_now()
			EventBus.menu_requested.emit()
		"save":
			game.save_now()
			_sys(outcome, "Progress saved.")
		"stats":
			var s: Dictionary = game.profile.stats
			for k in s:
				outcome.write("sys", "  %s %s\n" % [str(k).rpad(22, "."), str(s[k])], "dim")
		_:
			outcome.write("sys", "Game commands: :hint  :solution  :objective  :reset  :skip  :next  :stats  :save  :menu\n", "tip")
	return outcome


func _sys(outcome: ExecutionOutcome, text: String) -> void:
	outcome.write("sys", text + "\n", "tip")
