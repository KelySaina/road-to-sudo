extends PanelContainer
## Side panel for Adventure mode. Adventure now runs in the 2D World scene (which
## has its own HUD), so this panel is a safe fallback: it shows the current world,
## the skills you've collected and the trial status. No health, no combat.

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
	EventBus.adventure_won.connect(_on_won)
	hp_bar.visible = false
	hp_text.visible = false
	enemy_line.visible = false


func refresh() -> void:
	var adv = Game.adventure
	if adv == null or adv.world == null:
		return
	region.text = str(adv.world.title).to_upper()
	var idx: int = adv.current_index()
	location.text = adv.world.world_name(idx)
	objective.visible = true
	if adv.is_passed(idx):
		objective.text = "✔ Trial passed — the portal is open."
	elif adv.all_orbs_collected(idx):
		objective.text = "Trial ready — use the console."
	else:
		objective.text = "Collect this world's skill orbs (%d/%d)." % [adv.orbs_collected_count(idx), adv.orbs_total(idx)]
	exits.text = ""
	hint_button.visible = adv.in_trial()
	_rebuild_keys(adv.state.skills)


func _rebuild_keys(skills: Array) -> void:
	for c in keys.get_children():
		c.queue_free()
	if skills.is_empty():
		var l := Label.new()
		l.text = "none yet"
		l.theme_type_variation = &"FaintLabel"
		keys.add_child(l)
		return
	for f in skills:
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"NewChipPanel"
		var l := Label.new()
		l.text = str(f)
		l.theme_type_variation = &"AccentLabel"
		chip.add_child(l)
		keys.add_child(chip)


func _on_won() -> void:
	objective.visible = true
	objective.text = "★ You reached root."
	enemy_line.visible = false
	hint_button.visible = false
	verbs.text = "Type :menu to return. Your journey is saved to your rank."
