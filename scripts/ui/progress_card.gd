extends PanelContainer
## Rank, XP bar and the chips of commands the player has learned.

@onready var rank_label: Label = %Rank
@onready var xp_label: Label = %Xp
@onready var bar: ProgressBar = %Bar
@onready var next_label: Label = %Next
@onready var commands: HFlowContainer = %Commands

var _fresh: Array = []


func _ready() -> void:
	EventBus.xp_changed.connect(func(_xp, _rank, _p): refresh())
	EventBus.commands_unlocked.connect(_on_commands_unlocked)
	var ct := get_node_or_null(^"VBox/CommandsTitle")
	if ct != null and ct is Label:
		ct.text = I18n.t("COMMANDS LEARNED")
	refresh()


func refresh() -> void:
	var prog: Progression = Game.progression
	var rank := prog.current_rank()
	rank_label.text = str(rank.name)
	xp_label.text = "%d XP" % Game.profile.xp
	var tween := create_tween()
	tween.tween_property(bar, "value", prog.progress_to_next(), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var nxt := prog.next_rank()
	if nxt.is_empty():
		next_label.text = I18n.t("Nothing left above you.")
	elif Game.profile.xp >= int(nxt.xp):
		next_label.text = I18n.t("Next: %s — needs a special challenge") % nxt.name
	else:
		next_label.text = I18n.t("Next: %s at %d XP") % [nxt.name, int(nxt.xp)]
	_rebuild_chips()


func _on_commands_unlocked(names: Array) -> void:
	_fresh = names.duplicate()
	_rebuild_chips()


func _rebuild_chips() -> void:
	for c in commands.get_children():
		c.queue_free()
	for n in Game.profile.unlocked_commands:
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"NewChipPanel" if _fresh.has(n) else &"ChipPanel"
		var l := Label.new()
		l.text = str(n)
		l.theme_type_variation = &"AccentLabel" if _fresh.has(n) else &"DimLabel"
		chip.add_child(l)
		commands.add_child(chip)
		if _fresh.has(n):
			chip.modulate.a = 0.0
			create_tween().tween_property(chip, "modulate:a", 1.0, 0.5)
