extends Node2D
## The playable 2D overworld for Adventure mode. You walk an operator around
## the mainframe's rooms; walking up to a console and pressing E opens a
## terminal where you fight with real Linux commands. All RPG state lives in
## Game.adventure (AdventureManager); this scene is the physical presentation.

const TILE := 48
const INTERACT_RANGE := 74.0
const TERMINAL_SCENE := preload("res://scenes/terminal/terminal.tscn")

var map: Dictionary
var world: AdventureWorld
var state: AdventureState
var adv: AdventureManager
var _theme: Theme

var _player: Player2D
var _camera: Camera2D
var _objects: Array = []          # Interactable
var _blockers: Array = []         # Blocker
var _near: Interactable = null
var _grid_w := 0
var _grid_h := 0

# UI
var _hud: CanvasLayer
var _hp_bar: ProgressBar
var _hp_text: Label
var _keys_box: HFlowContainer
var _place_label: Label
var _prompt_label: Label
var _flash: ColorRect
var _dialogue_layer: CanvasLayer
var _dialogue: Control
var _dialogue_name: Label
var _dialogue_body: RichTextLabel
var _dialogue_pages: Array = []
var _dialogue_page := 0
var _overlay: Control
var _terminal
var _overlay_title: Label
var _engaged_node := ""
var _resumed := false


func setup(resumed: bool) -> void:
	_resumed = resumed


func _ready() -> void:
	adv = Game.adventure
	world = adv.world
	state = adv.state
	map = JsonLoader.load_dict("res://data/adventure/map.json")
	_theme = UiTheme.build(int(Game.profile.settings.get("font_size", 17)))

	_build_tiles()
	_build_doors()
	_build_objects()
	_build_player()
	_build_camera()
	_build_hud()
	_build_dialogue()
	_build_overlay()

	adv.battle_won.connect(_on_battle_won)
	adv.adventure_won.connect(_on_adventure_won)
	adv.player_damaged.connect(func(_a, _h): _do_flash(UiTheme.ERROR); _refresh_hud())
	adv.player_rebooted.connect(func(): _do_flash(UiTheme.WARN); _refresh_hud())
	adv.state_changed.connect(_on_state_changed)
	EventBus.command_output.connect(_on_command_output)
	EventBus.narrate.connect(_on_narrate)

	_refresh_hud()
	_refresh_blockers()
	if not _resumed:
		_show_dialogue("The Ascent to Root", world.intro)


# --- world building ---------------------------------------------------------

func _build_tiles() -> void:
	var rows: Array = map.get("rows", [])
	_grid_h = rows.size()
	_grid_w = 0
	var floor_tiles := Node2D.new()
	floor_tiles.name = "Floor"
	add_child(floor_tiles)
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	var scale := Vector2(TILE / 16.0, TILE / 16.0)
	for y in rows.size():
		var row: String = rows[y]
		_grid_w = maxi(_grid_w, row.length())
		for x in row.length():
			var wall := row[x] == "#"
			var spr := Sprite2D.new()
			var alt: bool = not wall and (abs(hash(Vector2i(x, y))) % 100) < 14
			spr.texture = SpriteFactory.texture("wall" if wall else ("floor_alt" if alt else "floor"))
			spr.scale = scale
			spr.position = Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
			spr.z_index = 0 if not wall else 1
			floor_tiles.add_child(spr)
			if wall:
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(TILE, TILE)
				shape.shape = rect
				shape.position = spr.position
				walls.add_child(shape)


func _build_doors() -> void:
	for door in map.get("doors", []):
		var b := Blocker.new()
		add_child(b)
		b.setup(door, TILE)
		_blockers.append(b)


func _build_objects() -> void:
	for o in map.get("objects", []):
		var it := Interactable.new()
		it.kind = _kind_of(o.get("kind", "npc"))
		it.node_id = o.get("node", "")
		it.sprite_name = o.get("sprite", "console")
		it.label_text = o.get("label", "")
		it.done_sprite = "console_done" if it.sprite_name == "console" else ""
		it.set_meta("enemy", o.get("enemy", false))
		it.position = Vector2((o.at[0] + 0.5) * TILE, (o.at[1] + 0.5) * TILE)
		add_child(it)
		_objects.append(it)
		if state.is_cleared(it.node_id) and it.kind in [Interactable.Kind.CONSOLE, Interactable.Kind.BOSS]:
			_mark_object_cleared(it)


func _kind_of(k: String) -> Interactable.Kind:
	match k:
		"console": return Interactable.Kind.CONSOLE
		"boss": return Interactable.Kind.BOSS
		"key": return Interactable.Kind.KEY
		_: return Interactable.Kind.NPC


func _build_player() -> void:
	_player = Player2D.new()
	var spawn: Array = map.get("spawn", [2, 2])
	_player.position = Vector2((spawn[0] + 0.5) * TILE, (spawn[1] + 0.5) * TILE)
	add_child(_player)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.zoom = Vector2(2.1, 2.1)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 7.0
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = _grid_w * TILE
	_camera.limit_bottom = _grid_h * TILE
	_player.add_child(_camera)
	_camera.make_current()


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	_hud.add_child(root)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	var top := PanelContainer.new()
	top.theme_type_variation = &"CardPanel"
	top.position = Vector2(18, 18)
	top.custom_minimum_size = Vector2(360, 0)
	root.add_child(top)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	top.add_child(vb)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	vb.add_child(hp_row)
	var hp_lbl := Label.new(); hp_lbl.text = "HP"; hp_lbl.theme_type_variation = &"DimLabel"
	hp_row.add_child(hp_lbl)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(180, 14)
	_hp_bar.max_value = 1.0; _hp_bar.step = 0.001; _hp_bar.show_percentage = false
	hp_row.add_child(_hp_bar)
	_hp_text = Label.new(); _hp_text.theme_type_variation = &"DimLabel"
	hp_row.add_child(_hp_text)
	_keys_box = HFlowContainer.new()
	_keys_box.add_theme_constant_override("h_separation", 6)
	vb.add_child(_keys_box)

	var place_panel := PanelContainer.new()
	place_panel.theme_type_variation = &"ChipPanel"
	place_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	place_panel.position = Vector2(-260, 18)
	place_panel.custom_minimum_size = Vector2(240, 0)
	root.add_child(place_panel)
	_place_label = Label.new()
	_place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_label.theme_type_variation = &"AccentLabel"
	place_panel.add_child(_place_label)

	var prompt_panel := PanelContainer.new()
	prompt_panel.theme_type_variation = &"ChipPanel"
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.position = Vector2(-170, -70)
	prompt_panel.custom_minimum_size = Vector2(340, 0)
	root.add_child(prompt_panel)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.text = "WASD / arrows to move   ·   E to interact   ·   Esc: menu"
	_prompt_label.theme_type_variation = &"DimLabel"
	prompt_panel.add_child(_prompt_label)


func _refresh_hud() -> void:
	var frac := clampf(float(state.hp) / maxf(1.0, state.max_hp), 0.0, 1.0)
	_hp_bar.value = frac
	_hp_text.text = "%d/%d" % [state.hp, state.max_hp]
	var color := UiTheme.SUCCESS if frac > 0.6 else (UiTheme.WARN if frac > 0.3 else UiTheme.ERROR)
	_hp_bar.add_theme_stylebox_override("fill", UiTheme.box(color, Color.TRANSPARENT, 4, 0, 0))
	for c in _keys_box.get_children():
		c.queue_free()
	if state.flags.is_empty():
		var l := Label.new(); l.text = "no keys yet"; l.theme_type_variation = &"FaintLabel"
		_keys_box.add_child(l)
	else:
		for f in state.flags:
			var chip := PanelContainer.new()
			chip.theme_type_variation = &"NewChipPanel"
			var l := Label.new(); l.text = "⚿ " + str(f); l.theme_type_variation = &"AccentLabel"
			chip.add_child(l)
			_keys_box.add_child(chip)
	_place_label.text = world.node_name(state.current) if _engaged_node == "" else world.node_name(_engaged_node)


# --- dialogue ---------------------------------------------------------------

func _build_dialogue() -> void:
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.layer = 6
	add_child(_dialogue_layer)
	_dialogue = Control.new()
	_dialogue.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialogue.theme = _theme
	_dialogue_layer.add_child(_dialogue)
	var root := _dialogue
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-380, -220)
	panel.custom_minimum_size = Vector2(760, 150)
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_dialogue_name = Label.new()
	_dialogue_name.theme_type_variation = &"VioletLabel"
	vb.add_child(_dialogue_name)
	_dialogue_body = RichTextLabel.new()
	_dialogue_body.bbcode_enabled = true
	_dialogue_body.fit_content = true
	_dialogue_body.custom_minimum_size = Vector2(720, 70)
	vb.add_child(_dialogue_body)
	var hint := Label.new()
	hint.text = "[E] continue"
	hint.theme_type_variation = &"FaintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)
	_dialogue.hide()


func _show_dialogue(speaker: String, lines: Array) -> void:
	if lines.is_empty():
		lines = ["..."]
	_dialogue_name.text = speaker
	# paginate: group lines into pages of up to 4 non-empty-ish lines
	_dialogue_pages = []
	var page: Array = []
	for line in lines:
		page.append(str(line))
		if page.size() >= 5:
			_dialogue_pages.append(page); page = []
	if not page.is_empty():
		_dialogue_pages.append(page)
	_dialogue_page = 0
	_player.input_locked = true
	_dialogue.show()
	_render_dialogue_page()


func _render_dialogue_page() -> void:
	var page: Array = _dialogue_pages[_dialogue_page]
	_dialogue_body.text = "\n".join(PackedStringArray(page))


func _advance_dialogue() -> void:
	_dialogue_page += 1
	if _dialogue_page >= _dialogue_pages.size():
		_dialogue.hide()
		if _overlay == null or not _overlay.visible:
			_player.input_locked = false
	else:
		_render_dialogue_page()


# --- terminal overlay -------------------------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.theme = _theme
	layer.add_child(_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_overlay.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + m, 90)
	for m in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + m, 60)
	_overlay.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	_overlay_title = Label.new()
	_overlay_title.theme_type_variation = &"HeadingLabel"
	_overlay_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_overlay_title)
	var esc := Label.new()
	esc.text = "Esc  step back to the world"
	esc.theme_type_variation = &"FaintLabel"
	header.add_child(esc)
	_terminal = TERMINAL_SCENE.instantiate()
	_terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_terminal)
	_terminal.completer = func(line: String) -> Dictionary: return Completer.complete(line, Game.session, Game.registry)
	_terminal.describer = func(_line: String) -> String: return ""
	_terminal.set_speed(str(Game.profile.settings.get("text_speed", "fast")))
	_terminal.submitted.connect(func(line: String): Game.submit(line))
	_overlay.hide()


func _open_terminal(node_id: String) -> void:
	_engaged_node = node_id
	var node := world.node(node_id)
	var enemy: Dictionary = node.get("enemy", {})
	_overlay_title.text = "» " + str(enemy.get("name", node.get("name", "Console")))
	_terminal.clear_screen()
	_terminal.history = Game.session.history
	var s: ShellSession = Game.session
	_terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())
	_overlay.show()
	_hud.visible = false
	_player.input_locked = true
	adv.engage(node_id)
	_terminal.focus_input()
	_refresh_hud()


func _close_terminal() -> void:
	_overlay.hide()
	_hud.visible = true
	adv.disengage()
	_engaged_node = ""
	if not _dialogue.visible:
		_player.input_locked = false
	_refresh_hud()


# --- interaction ------------------------------------------------------------

func _process(_delta: float) -> void:
	if _overlay.visible or _dialogue.visible:
		if _near:
			_near.show_prompt(false)
			_near = null
		return
	var best: Interactable = null
	var best_d := INTERACT_RANGE
	for it in _objects:
		var d: float = it.global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d; best = it
	if best != _near:
		if _near: _near.show_prompt(false)
		_near = best
		if _near: _near.show_prompt(true)
		if _near != null and _place_label != null:
			_place_label.text = world.node_name(_near.node_id)


func _unhandled_input(event: InputEvent) -> void:
	if _overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			_close_terminal()
			get_viewport().set_input_as_handled()
		return
	if _dialogue.visible:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and _near:
		_interact(_near)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Game.save_now()
		EventBus.menu_requested.emit()


func _interact(it: Interactable) -> void:
	match it.kind:
		Interactable.Kind.NPC:
			var d: Dictionary = adv.visit_npc(it.node_id)
			_show_dialogue(d.name, d.lines)
			_refresh_hud()
			_refresh_blockers()
		Interactable.Kind.CONSOLE, Interactable.Kind.BOSS:
			if state.is_cleared(it.node_id):
				var enemy: Dictionary = world.node(it.node_id).get("enemy", {})
				_show_dialogue(enemy.get("name", "Console"), ["This one is already defeated. The console idles quietly."])
			else:
				_open_terminal(it.node_id)


# --- reactions --------------------------------------------------------------

func _on_command_output(outcome: ExecutionOutcome) -> void:
	if _overlay.visible:
		_terminal.print_outcome(outcome)
		var s: ShellSession = Game.session
		_terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())


func _on_narrate(text: String, kind: String) -> void:
	if not _overlay.visible:
		return
	_terminal.type_text("")
	for line in text.split("\n"):
		_terminal.type_text("  " + line if line != "" else "", kind)


func _on_state_changed() -> void:
	_refresh_hud()
	_refresh_blockers()


func _on_battle_won(node_id: String, _reward: Dictionary) -> void:
	for it in _objects:
		if it.node_id == node_id and it.kind in [Interactable.Kind.CONSOLE, Interactable.Kind.BOSS]:
			_mark_object_cleared(it)
	_refresh_hud()
	_refresh_blockers()
	if _overlay.visible:
		_terminal.type_text("")
		_terminal.type_text("  [Esc] step back to the world — a path has opened.", "tip")


func _mark_object_cleared(it: Interactable) -> void:
	it.set_cleared(true)
	if it.get_meta("enemy", false):
		var tw := create_tween()
		tw.tween_property(it, "modulate:a", 0.0, 0.6)
		tw.tween_callback(it.hide)


func _refresh_blockers() -> void:
	for b in _blockers:
		b.refresh(state)


func _do_flash(color: Color) -> void:
	_flash.color = Color(color, 0.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.3, 0.08)
	tw.tween_property(_flash, "color:a", 0.0, 0.4)


func _on_adventure_won() -> void:
	_show_victory()


func _show_victory() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = _theme
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiTheme.BG, 0.0)
	root.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.92, 1.0)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	center.add_child(vb)
	for line in world.outro:
		var l := Label.new()
		l.text = str(line)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.theme_type_variation = &"AccentLabel" if str(line).begins_with("root@") else &""
		vb.add_child(l)
	var cont := Label.new()
	cont.text = "\n[ Esc ] return to the menu"
	cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cont.theme_type_variation = &"FaintLabel"
	vb.add_child(cont)
	if _overlay.visible:
		_close_terminal()
	_player.input_locked = true
