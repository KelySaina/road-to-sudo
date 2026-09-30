extends PanelContainer
## Right-hand panel during Adventure mode: location, health, objective,
## exits and keys. Reads Game.adventure; buttons route through Game.submit.

@onready var region: Label = %Region
@onready var location: Label = %Location
@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_text: Label = %HpText
@onready var objective: Label = %Objective
@onready var enemy_line: Label = %EnemyLine
@onready var exits: Label = %Exits
@onready var keys: HFlowContainer = %Keys
@onready var verbs: Label = %Verbs
@onready var hint_button: Button = %HintButton


func _ready() -> void:
	hint_button.pressed.connect(func(): Game.submit("hint"))
	EventBus.adventure_state_changed.connect(refresh)
	EventBus.adventure_node.connect(func(_n): refresh())
	EventBus.player_damaged.connect(func(_a, _h): _flash(UiTheme.ERROR))
	EventBus.player_rebooted.connect(func(): _flash(UiTheme.WARN))
	EventBus.adventure_won.connect(_on_won)


func refresh() -> void:
	var adv = Game.adventure
	if adv == null or adv.world == null:
		return
	region.text = str(adv.world.title).to_upper()
	var node: Dictionary = adv.current_node()
	location.text = str(node.get("name", "?"))
	_set_hp(adv.state.hp, adv.state.max_hp)

	if adv.in_battle():
		objective.visible = true
		objective.text = "» " + str(node.get("battle", {}).get("objective", ""))
		var enemy: Dictionary = node.get("enemy", {})
		enemy_line.text = ("Enemy: %s" % enemy.get("name", "")) if not enemy.is_empty() else ""
		enemy_line.visible = enemy_line.text != ""
		hint_button.visible = true
	else:
		objective.visible = node.has("npc")
		objective.text = ("Someone here will talk: `talk`") if node.has("npc") else ""
		enemy_line.visible = false
		hint_button.visible = false
	exits.text = adv.exits_text().trim_prefix("Exits:  ")
	_rebuild_keys(adv.state.flags)


func _set_hp(hp: int, max_hp: int) -> void:
	var frac := clampf(float(hp) / maxf(1.0, max_hp), 0.0, 1.0)
	create_tween().tween_property(hp_bar, "value", frac, 0.3)
	hp_text.text = "%d/%d" % [hp, max_hp]
	var color := UiTheme.SUCCESS if frac > 0.6 else (UiTheme.WARN if frac > 0.3 else UiTheme.ERROR)
	var fill := UiTheme.box(color, Color.TRANSPARENT, 4, 0, 0)
	hp_bar.add_theme_stylebox_override("fill", fill)


func _rebuild_keys(flags: Array) -> void:
	for c in keys.get_children():
		c.queue_free()
	if flags.is_empty():
		var l := Label.new()
		l.text = "none yet"
		l.theme_type_variation = &"FaintLabel"
		keys.add_child(l)
		return
	for f in flags:
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"NewChipPanel"
		var l := Label.new()
		l.text = "▸ " + str(f)
		l.theme_type_variation = &"AccentLabel"
		chip.add_child(l)
		keys.add_child(chip)


func _flash(color: Color) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(color, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.28, 0.08)
	tw.tween_property(overlay, "color:a", 0.0, 0.35)
	tw.tween_callback(overlay.queue_free)


func _on_won() -> void:
	objective.visible = true
	objective.text = "★ The throne is yours."
	enemy_line.visible = false
	hint_button.visible = false
	verbs.text = "Type :menu to return. Your journey is saved to your rank."
