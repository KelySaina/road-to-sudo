extends PanelContainer
## Right-hand panel: where you are in the level, the objective, revealed
## hints and the help buttons. Buttons route through Game.submit(":hint")
## so mouse and keyboard share exactly one code path.

@onready var level_label: Label = %Level
@onready var steps: Label = %Steps
@onready var title: Label = %Title
@onready var objective: Label = %Objective
@onready var status: Label = %Status
@onready var hints_title: Label = %HintsTitle
@onready var hints: VBoxContainer = %Hints
@onready var hint_button: Button = %HintButton
@onready var solution_button: Button = %SolutionButton
@onready var reset_button: Button = %ResetButton
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	hint_button.pressed.connect(func(): Game.submit(":hint"))
	solution_button.pressed.connect(func(): Game.submit(":solution"))
	reset_button.pressed.connect(func(): Game.submit(":reset"))
	continue_button.pressed.connect(func(): Game.submit(":next"))
	EventBus.hint_revealed.connect(func(_i, _t): _refresh_hints())
	hint_button.text = Loc.t("Hint  F1")
	solution_button.text = Loc.t("Solution")


func show_practice() -> void:
	level_label.text = "PRACTICE LAB"
	steps.text = ""
	title.text = "Free play"
	objective.text = "No objectives. No XP. Nothing can break for real."
	status.text = "Start with:  cat README.lab\nEverything is simulated: experiment, break things, read man pages."
	hints_title.text = "IDEAS"
	_clear_hints()
	for idea in ["ls -la ~", "sort fruits.txt | uniq -c | sort -rn", "grep -c ERROR /var/log/app.log", "find / -name '*.log' 2> /dev/null", "chmod +x scripts/hello.sh && ./scripts/hello.sh you", "ps aux"]:
		_add_hint_label("$ " + idea, "dim")
	for b in [hint_button, solution_button, reset_button]:
		b.visible = false
	continue_button.visible = false


func show_challenge(c: Challenge) -> void:
	var pos := Game.library.position_of(c.id)
	var lvl: Dictionary = pos.get("level", {})
	level_label.text = Loc.t(str(lvl.get("title", ""))).to_upper()
	var idx := int(pos.get("index", 0))
	var count := int(pos.get("count", 1))
	var dots := ""
	for i in count:
		dots += "●" if i < idx else ("◉" if i == idx else "○")
	steps.text = "%s  %d/%d" % [dots, idx + 1, count]
	title.text = Loc.t(c.title)
	objective.text = Loc.t(c.objective_for(Game.difficulty.id))
	status.text = "%s %s" % [Loc.t("Difficulty:"), Game.difficulty.label]
	if Game.difficulty.time_bonus and c.time_limit > 0:
		status.text += "  ·  " + Loc.t("time bonus under") + " %d:%02d" % [c.time_limit / 60, c.time_limit % 60]
	for b in [hint_button, solution_button, reset_button]:
		b.visible = true
		b.disabled = false
	continue_button.visible = false
	_refresh_hints()


func show_completed(_c: Challenge, result: Dictionary) -> void:
	status.text = "✔ %s  ·  +%d XP" % [Loc.t("Complete"), int(result.get("granted", 0))]
	status.add_theme_color_override("font_color", UiTheme.SUCCESS)
	continue_button.visible = not str(result.get("next", "")).is_empty()
	hint_button.disabled = true
	solution_button.disabled = true
	if continue_button.visible:
		continue_button.text = Loc.t("Continue  ⏎")
	var tween := create_tween()
	title.modulate = UiTheme.SUCCESS
	tween.tween_property(title, "modulate", Color.WHITE, 1.2)


func _refresh_hints() -> void:
	var mgr: ChallengeManager = Game.challenges
	if mgr.current == null:
		return
	status.remove_theme_color_override("font_color")
	var shown := mgr.shown_hint_texts()
	hints_title.text = "%s %d/%d" % [Loc.t("HINTS"), shown.size(), mgr.hints_available()]
	_clear_hints()
	for i in shown.size():
		_add_hint_label("%d. %s" % [i + 1, Loc.t(str(shown[i]))], "")
	if shown.is_empty():
		_add_hint_label(Loc.t("Stuck? Observe first: what does the system tell you?\nHints get more explicit each time you ask."), "dim")
	hint_button.disabled = shown.size() >= mgr.hints_available()
	solution_button.disabled = not Game.difficulty.allow_solution
	solution_button.tooltip_text = Loc.t("Available after all hints") if not mgr.can_reveal_solution() else Loc.t("Reveal one possible solution (no bonus XP)")


func _clear_hints() -> void:
	for h in hints.get_children():
		h.queue_free()


func _add_hint_label(text: String, style: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = &"DimLabel" if style == "dim" else &""
	hints.add_child(l)
