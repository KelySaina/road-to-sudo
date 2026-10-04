extends Control
## The play screen. Wires the terminal to Game and renders gameplay events
## (briefings, completions, hints, narration) into the scrollback.

@onready var terminal = %Terminal
@onready var status_bar = %StatusBar
@onready var objective_panel = %ObjectivePanel
@onready var adventure_panel = %AdventurePanel
@onready var menu_button: Button = %MenuButton

var _mode := "campaign"
var _overlays: InteractiveOverlays


func _ready() -> void:
	terminal.completer = func(line: String) -> Dictionary: return Completer.complete(line, Game.session, Game.registry)
	terminal.describer = func(line: String) -> String:
		if Game.mode == "campaign" and not Game.difficulty.inline_suggestions:
			return ""
		return Completer.describe(line, Game.registry)
	terminal.set_speed(str(Game.profile.settings.get("text_speed", "fast")))
	terminal.submitted.connect(func(line: String): Game.submit(line))
	menu_button.pressed.connect(func(): Game.submit(":menu"))
	menu_button.text = I18n.t("⎋  Save & return to menu   (:menu)")

	EventBus.command_output.connect(_on_command_output)
	EventBus.narrate.connect(_on_narrate)
	EventBus.challenge_started.connect(_on_challenge_started)
	EventBus.challenge_completed.connect(_on_challenge_completed)
	EventBus.hint_revealed.connect(_on_hint_revealed)
	EventBus.session_changed.connect(_refresh_session)
	EventBus.campaign_finished.connect(_on_campaign_finished)
	EventBus.rank_up.connect(_on_rank_up)

	# Full-screen interactive programs (nano, less, su prompt) ride above the
	# toast layer (CanvasLayer 10), so a stray achievement toast can't draw over
	# them. The same host is used by the 2D adventure world.
	_overlays = InteractiveOverlays.new()
	_overlays.install(self, func(): terminal.focus_input())
	_overlays.editor_closed.connect(_on_editor_closed)


## Called by Main right after the scene is added: "campaign" or "practice".
func begin(mode: String, fresh: bool) -> void:
	_mode = mode
	_refresh_session()
	_print_login_banner(fresh)
	if mode == "practice":
		objective_panel.show_practice()
		terminal.type_text(I18n.t("PRACTICE LAB — a sandbox machine. No objectives, no score."), "tip")
		terminal.type_text(I18n.t("Try:  cat README.lab"), "dim")
	elif mode == "adventure":
		objective_panel.visible = false
		adventure_panel.visible = true
		adventure_panel.refresh()
	elif Game.challenges.current != null:
		_on_challenge_started(Game.challenges.current)
	terminal.focus_input()


func _unhandled_input(event: InputEvent) -> void:
	if _overlays != null and _overlays.any_visible():
		return
	if event.is_action_pressed("ui_hint") and _mode == "campaign":
		Game.submit(":hint")
		get_viewport().set_input_as_handled()


func _on_editor_closed(saved: bool) -> void:
	terminal.focus_input()
	if saved:
		terminal.print_text(I18n.t("  [ file saved ]"), "dim")


func _refresh_session() -> void:
	var s: ShellSession = Game.session
	if s == null:
		return
	terminal.history = s.history
	terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())
	var mode_text := I18n.t("CAMPAIGN · %s") % Game.difficulty.label.to_upper()
	if _mode == "practice":
		mode_text = I18n.t("PRACTICE LAB")
	elif _mode == "adventure":
		mode_text = I18n.t("ADVENTURE · THE ASCENT")
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
		terminal.type_text("  " + line if line != "" else "", kind)
	terminal.type_text("")


func _on_challenge_started(c: Challenge) -> void:
	var diff: DifficultySettings = Game.difficulty
	var pos := Game.library.position_of(c.id)
	if int(pos.get("index", 0)) == 0:
		var lvl: Dictionary = pos.get("level", {})
		terminal.print_text("")
		terminal.print_rule(str(lvl.get("title", "")).to_upper())
		if lvl.has("description"):
			terminal.type_text("  " + str(lvl.description), "dim")
	terminal.print_text("")
	terminal.print_rule("%d/%d · %s" % [int(pos.get("index", 0)) + 1, int(pos.get("count", 1)), c.title])
	terminal.type_text("")
	for line in c.briefing_for(diff.id):
		terminal.type_text("  " + str(line), "story")
	terminal.type_text("")
	if diff.show_tips:
		for tip in c.tips:
			terminal.type_text("  › " + str(tip), "tip")
		if not c.tips.is_empty():
			terminal.type_text("")
	terminal.type_text("  " + I18n.t("OBJECTIVE") + "  " + c.objective_for(diff.id), "objective")
	terminal.type_text(I18n.t("  (stuck? :hint or F1)") + "\n" if diff.max_hints > 0 else "", "dim")
	objective_panel.show_challenge(c)
	_refresh_session()


func _on_challenge_completed(c: Challenge, result: Dictionary) -> void:
	var diff: DifficultySettings = Game.difficulty
	terminal.type_text("")
	terminal.type_text(I18n.t("  ✔ OBJECTIVE COMPLETE — %s") % I18n.t(c.title), "success")
	var parts: Array = ["+%d XP" % int(result.base)]
	if int(result.bonus) > 0:
		parts.append("+%d %s" % [int(result.bonus), I18n.t("no-hint bonus") if int(result.hints) == 0 else I18n.t("bonus")])
	if int(result.get("time_bonus", 0)) > 0:
		parts.append("+%d %s" % [int(result.time_bonus), I18n.t("speed")])
	if float(result.multiplier) != 1.0:
		parts.append("×%s %s" % [str(result.multiplier), diff.label])
	if not result.get("first_time", true):
		parts = [I18n.t("replay — no XP")]
	terminal.type_text("    " + "   ".join(PackedStringArray(parts)), "success")
	if diff.show_explanations and c.explanation != "":
		terminal.type_text("")
		terminal.type_text("  " + I18n.t("WHAT JUST HAPPENED"), "header")
		for line in c.explanation.split("\n"):
			terminal.type_text("  " + line, "story")
	var fresh: Array = result.get("new_commands", [])
	if not fresh.is_empty():
		terminal.type_text("")
		terminal.type_text("  " + I18n.t("New in your toolbox:") + " " + "  ".join(PackedStringArray(fresh)), "reaction")
	objective_panel.show_completed(c, result)
	# Deferred so a rank-up triggered by this XP prints before the prompt.
	_print_continue.call_deferred(str(result.get("next", "")) != "")


func _print_continue(has_next: bool) -> void:
	terminal.type_text("")
	if has_next:
		terminal.type_text("  " + I18n.t("▸ Press Enter to continue."), "tip")


func _on_hint_revealed(index: int, text: String) -> void:
	terminal.type_text(I18n.t("  HINT %d/%d  %s") % [index, Game.challenges.hints_available(), text], "warn")


func _on_rank_up(rank: Dictionary) -> void:
	terminal.type_text("")
	terminal.type_text(I18n.t("  ★ RANK UP — you are now: %s") % I18n.t(str(rank.name)), "reaction")
	terminal.type_text("    %s" % rank.get("blurb", ""), "dim")


func _on_adventure_won() -> void:
	var world = Game.adventure.world
	terminal.print_text("")
	terminal.print_rule(I18n.t("THE OTHER SIDE OF THE PROMPT"))
	for line in world.outro:
		terminal.type_text("  " + str(line), "success" if line.begins_with("root@") else "story")
	terminal.type_text("")
	terminal.type_text("  " + I18n.t("Type :menu to return. This victory is saved to your rank."), "tip")


func _on_campaign_finished() -> void:
	var p: PlayerProfile = Game.profile
	var done: Array = []
	for lvl in Game.library.levels:
		if not lvl.get("challenges", []).is_empty():
			done.append(str(lvl.get("title", "")))
	terminal.print_text("")
	terminal.print_rule(I18n.t("THE ROAD CONTINUES"))
	var lines: Array = [
		"",
		I18n.t("  You started this session not knowing who you were."),
		I18n.t("  Now files, permissions and a broken production box all bend to you."),
		"",
		I18n.t("  Rank        %s") % I18n.t(str(Game.progression.current_rank().name)),
		"  XP          %d" % p.xp,
		I18n.t("  Commands    %d run, %d pipes, %d permission errors met") % [int(p.stats.commands_run), int(p.stats.pipes), int(p.stats.permission_denied)],
		I18n.t("  Hints used  %d") % int(p.stats.hints_used),
		"",
		I18n.t("  Finished so far:"),
	]
	for title in done:
		lines.append("    ✔ %s" % I18n.t(str(title)))
	lines.append_array([
		"",
		I18n.t("  Next on the road: users & groups, processes, networking, services,"),
		I18n.t("  SSH, git, security... more levels are on the way."),
		"",
		I18n.t("  Type :menu, keep exploring this machine, or try Adventure mode and"),
		I18n.t("  the Practice Lab — both always open."),
	])
	for line in lines:
		terminal.type_text(line, "story")
		objective_panel.show_practice()
	objective_panel.level_label.text = I18n.t("CAMPAIGN COMPLETE")
	objective_panel.title.text = I18n.t("The road continues")
	objective_panel.objective.text = I18n.t("You've finished every level built so far. More are on the way.")
