extends Control
## The play screen. Wires the terminal to Game and renders gameplay events
## (briefings, completions, hints, narration) into the scrollback.

@onready var terminal = %Terminal
@onready var status_bar = %StatusBar
@onready var objective_panel = %ObjectivePanel
@onready var adventure_panel = %AdventurePanel
@onready var menu_button: Button = %MenuButton

var _mode := "campaign"


func _ready() -> void:
	terminal.completer = func(line: String) -> Dictionary: return Completer.complete(line, Game.session, Game.registry)
	terminal.describer = func(line: String) -> String:
		if Game.mode == "campaign" and not Game.difficulty.inline_suggestions:
			return ""
		return Completer.describe(line, Game.registry)
	terminal.set_speed(str(Game.profile.settings.get("text_speed", "fast")))
	terminal.submitted.connect(func(line: String): Game.submit(line))
	menu_button.pressed.connect(func(): Game.submit(":menu"))

	EventBus.command_output.connect(_on_command_output)
	EventBus.narrate.connect(_on_narrate)
	EventBus.challenge_started.connect(_on_challenge_started)
	EventBus.challenge_completed.connect(_on_challenge_completed)
	EventBus.hint_revealed.connect(_on_hint_revealed)
	EventBus.session_changed.connect(_refresh_session)
	EventBus.campaign_finished.connect(_on_campaign_finished)
	EventBus.rank_up.connect(_on_rank_up)


## Called by Main right after the scene is added: "campaign" or "practice".
func begin(mode: String, fresh: bool) -> void:
	_mode = mode
	_refresh_session()
	_print_login_banner(fresh)
	if mode == "practice":
		objective_panel.show_practice()
		terminal.type_text("PRACTICE LAB — a sandbox machine. No objectives, no score.", "tip")
		terminal.type_text("Try:  cat README.lab", "dim")
	elif mode == "adventure":
		objective_panel.visible = false
		adventure_panel.visible = true
		adventure_panel.refresh()
	elif Game.challenges.current != null:
		_on_challenge_started(Game.challenges.current)
	terminal.focus_input()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_hint") and _mode == "campaign":
		Game.submit(":hint")
		get_viewport().set_input_as_handled()


func _refresh_session() -> void:
	var s: ShellSession = Game.session
	if s == null:
		return
	terminal.history = s.history
	terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())
	var mode_text := "CAMPAIGN · %s" % Game.difficulty.label.to_upper()
	if _mode == "practice":
		mode_text = "PRACTICE LAB"
	elif _mode == "adventure":
		mode_text = "ADVENTURE · THE ASCENT"
	status_bar.bind(s, mode_text)


func _print_login_banner(fresh: bool) -> void:
	var motd := Game.session.machine.vfs.get_node_at("/etc/motd")
	if motd != null:
		terminal.print_text(motd.content.strip_edges(false, true), "dim")
	var when := "Fri Jun  5 09:14:02 2026 from 10.0.0.12" if fresh else "just now (session restored)"
	terminal.print_text("Last login: %s\n" % when, "dim")


# --- gameplay events ------------------------------------------------------------

func _on_command_output(outcome: ExecutionOutcome) -> void:
	terminal.print_outcome(outcome)


func _on_narrate(text: String, kind: String) -> void:
	terminal.type_text("")
	for line in text.split("\n"):
		terminal.type_text("  " + Loc.t(line) if line != "" else "", kind)
	terminal.type_text("")


func _on_challenge_started(c: Challenge) -> void:
	var diff: DifficultySettings = Game.difficulty
	var pos := Game.library.position_of(c.id)
	if int(pos.get("index", 0)) == 0:
		var lvl: Dictionary = pos.get("level", {})
		terminal.print_text("")
		terminal.print_rule(Loc.t(str(lvl.get("title", ""))).to_upper())
		if lvl.has("description"):
			terminal.type_text("  " + Loc.t(str(lvl.description)), "dim")
	terminal.print_text("")
	terminal.print_rule("%d/%d · %s" % [int(pos.get("index", 0)) + 1, int(pos.get("count", 1)), Loc.t(c.title)])
	terminal.type_text("")
	for line in c.briefing_for(diff.id):
		terminal.type_text("  " + Loc.t(str(line)), "story")
	terminal.type_text("")
	if diff.show_tips:
		for tip in c.tips:
			terminal.type_text("  › " + Loc.t(str(tip)), "tip")
		if not c.tips.is_empty():
			terminal.type_text("")
	terminal.type_text("  %s  %s" % [Loc.t("OBJECTIVE"), Loc.t(c.objective_for(diff.id))], "objective")
	terminal.type_text(("  " + Loc.t("(stuck? :hint or F1)") + "\n") if diff.max_hints > 0 else "", "dim")
	objective_panel.show_challenge(c)
	_refresh_session()


func _on_challenge_completed(c: Challenge, result: Dictionary) -> void:
	var diff: DifficultySettings = Game.difficulty
	terminal.type_text("")
	terminal.type_text("  ✔ %s — %s" % [Loc.t("OBJECTIVE COMPLETE"), Loc.t(c.title)], "success")
	var parts: Array = ["+%d XP" % int(result.base)]
	if int(result.bonus) > 0:
		parts.append("+%d %s" % [int(result.bonus), Loc.t("no-hint bonus") if int(result.hints) == 0 else Loc.t("bonus")])
	if int(result.get("time_bonus", 0)) > 0:
		parts.append("+%d %s" % [int(result.time_bonus), Loc.t("speed")])
	if float(result.multiplier) != 1.0:
		parts.append("×%s %s" % [str(result.multiplier), diff.label])
	if not result.get("first_time", true):
		parts = [Loc.t("replay — no XP")]
	terminal.type_text("    " + "   ".join(PackedStringArray(parts)), "success")
	if diff.show_explanations and c.explanation != "":
		terminal.type_text("")
		terminal.type_text("  " + Loc.t("WHAT JUST HAPPENED"), "header")
		for line in c.explanation.split("\n"):
			terminal.type_text("  " + Loc.t(line), "story")
	var fresh: Array = result.get("new_commands", [])
	if not fresh.is_empty():
		terminal.type_text("")
		terminal.type_text("  " + Loc.t("New in your toolbox:") + " " + "  ".join(PackedStringArray(fresh)), "reaction")
	objective_panel.show_completed(c, result)
	# Deferred so a rank-up triggered by this XP prints before the prompt.
	_print_continue.call_deferred(str(result.get("next", "")) != "")


func _print_continue(has_next: bool) -> void:
	terminal.type_text("")
	if has_next:
		terminal.type_text("  ▸ " + Loc.t("Press Enter to continue."), "tip")


func _on_hint_revealed(index: int, text: String) -> void:
	terminal.type_text("  %s %d/%d  %s" % [Loc.t("HINT"), index, Game.challenges.hints_available(), Loc.t(text)], "warn")


func _on_rank_up(rank: Dictionary) -> void:
	terminal.type_text("")
	terminal.type_text("  ★ %s %s" % [Loc.t("RANK UP — you are now:"), rank.name], "reaction")
	terminal.type_text("    %s" % Loc.t(str(rank.get("blurb", ""))), "dim")


func _on_adventure_won() -> void:
	var world = Game.adventure.world
	terminal.print_text("")
	terminal.print_rule("THE OTHER SIDE OF THE PROMPT")
	for line in world.outro:
		terminal.type_text("  " + str(line), "success" if line.begins_with("root@") else "story")
	terminal.type_text("")
	terminal.type_text("  Type :menu to return. This victory is saved to your rank.", "tip")


func _on_campaign_finished() -> void:
	var p: PlayerProfile = Game.profile
	var done: Array = []
	for lvl in Game.library.levels:
		if not lvl.get("challenges", []).is_empty():
			done.append(str(lvl.get("title", "")))
	terminal.print_text("")
	terminal.print_rule("THE ROAD CONTINUES")
	var lines: Array = [
		"",
		"  You started this session not knowing who you were.",
		"  Now files, permissions and a broken production box all bend to you.",
		"",
		"  Rank        %s" % Game.progression.current_rank().name,
		"  XP          %d" % p.xp,
		"  Commands    %d run, %d pipes, %d permission errors met" % [int(p.stats.commands_run), int(p.stats.pipes), int(p.stats.permission_denied)],
		"  Hints used  %d" % int(p.stats.hints_used),
		"",
		"  Finished so far:",
	]
	for title in done:
		lines.append("    ✔ %s" % title)
	lines.append_array([
		"",
		"  Next on the road: users & groups, processes, networking, services,",
		"  SSH, git, security... more levels are on the way.",
		"",
		"  Type :menu, keep exploring this machine, or try Adventure mode and",
		"  the Practice Lab — both always open.",
	])
	for line in lines:
		terminal.type_text(line, "story")
		objective_panel.show_practice()
	objective_panel.level_label.text = "CAMPAIGN COMPLETE"
	objective_panel.title.text = "The road continues"
	objective_panel.objective.text = "You've finished every level built so far. More are on the way."
