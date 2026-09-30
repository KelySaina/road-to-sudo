extends Node2D
## The playable 2D overworld for Adventure mode: a side-on PLATFORMER.
## Each world is one side-scrolling course. You run and jump your way to glowing
## skill orbs; taking one teaches a command and drops you straight onto a real
## prompt to try it. Clear the course and the trial console (E) sets the world's
## actual problem; passing it opens the portal (E) to the next world.
## All progress lives in Game.adventure.

const TILE := 48
const ORB_PICKUP := 42.0
const INTERACT_RANGE := 88.0
const TERMINAL_SCENE := preload("res://scenes/terminal/terminal.tscn")

# --- course geometry --------------------------------------------------------
# Rows GROUND_ROW..LEVEL_H-1 are solid earth; everything above is air. Platform
# heights are expressed as rows ABOVE the surface you jump from, and are capped
# at 2 because a full jump only clears about 3 (see Player2D's tuning note).
const LEVEL_H := 15
const GROUND_ROW := 12
const START_W := 7            # flat run-up before the first obstacle
const SECTION_W := 10         # one obstacle course per skill orb
const END_W := 14             # the plateau holding the console and the portal
const PLATFORM_RISE := 2      # rows a platform sits above its launch surface

var world: AdventureWorld
var state: AdventureState
var adv: AdventureManager
var _theme: Theme

var _player: Player2D
var _camera: Camera2D
var _room: Node2D                 # holds tiles + objects for the current course
var _orbs: Array = []             # {node: Node2D, index: int}
var _console: Interactable
var _portal: Interactable
var _near: Interactable = null
var _level_w := 0
var _safe_pos := Vector2.ZERO     # last spot the player stood on solid ground
var _intro_shown: Dictionary = {} # world index -> true

# HUD / dialogue / overlay
var _hud: CanvasLayer
var _world_label: Label
var _sub_label: Label
var _skills_box: HFlowContainer
var _orb_label: Label
var _prompt_label: Label
var _dialogue_layer: CanvasLayer
var _dialogue: Control
var _dialogue_name: Label
var _dialogue_body: RichTextLabel
var _dialogue_pages: Array = []
var _dialogue_page := 0
var _overlay: Control
var _terminal
var _overlay_title: Label
var _overlay_mode := ""           # "trial" | "practice"
var _pending_practice: Dictionary = {}
var _practice_skill := ""
var _practice_done := false
var _resumed := false


func setup(resumed: bool) -> void:
	_resumed = resumed


func _ready() -> void:
	adv = Game.adventure
	world = adv.world
	state = adv.state
	_theme = UiTheme.build(int(Game.profile.settings.get("font_size", 17)))

	_build_player()
	_build_camera()
	_build_hud()
	_build_dialogue()
	_build_overlay()

	adv.battle_won.connect(_on_trial_passed)
	adv.adventure_won.connect(_on_adventure_won)
	adv.state_changed.connect(_refresh_hud)
	EventBus.command_output.connect(_on_command_output)
	EventBus.narrate.connect(_on_narrate)

	_load_world(state.world_index)
	if not _resumed:
		_show_dialogue("The Ascent to Root", world.intro)


# --- building a world's course ----------------------------------------------

## Lay out one course as a grid of solid tiles plus the spots that matter.
## Deterministic: the same world always builds the same level, whether or not
## its orbs have already been taken.
func _plan_level(orb_count: int) -> Dictionary:
	var solid: Dictionary = {}
	var orb_cells: Array = []
	var width: int = START_W + orb_count * SECTION_W + END_W

	# Earth everywhere, then carve the pits out of it.
	for x in width:
		for y in range(GROUND_ROW, LEVEL_H):
			solid[Vector2i(x, y)] = true
	# Sealed ends, so you can never run out of the level sideways.
	for y in LEVEL_H:
		solid[Vector2i(0, y)] = true
		solid[Vector2i(width - 1, y)] = true

	for i in orb_count:
		var base: int = START_W + i * SECTION_W
		if i % 2 == 0:
			# "Hop the gap": a 3-wide pit with the orb floating over it, on a
			# ledge one jump up. Clearing the pit and taking the orb are two
			# different jumps, so skipping ahead is always possible.
			for x in range(base + 4, base + 7):
				_carve_pit(solid, x)
			var row: int = GROUND_ROW - PLATFORM_RISE
			for x in range(base + 4, base + 7):
				solid[Vector2i(x, row)] = true
			orb_cells.append(Vector2i(base + 5, row - 1))
		else:
			# "Staircase": a step, then a higher ledge — each one rise apart, so
			# the climb is two ordinary jumps rather than one heroic one. The
			# step sits over solid ground and the pit comes after it, so the
			# route reads left to right: hop up, hop across, take the orb.
			for x in range(base + 4, base + 6):
				_carve_pit(solid, x)
			var step_row: int = GROUND_ROW - PLATFORM_RISE
			for x in range(base + 2, base + 4):
				solid[Vector2i(x, step_row)] = true
			var top_row: int = step_row - PLATFORM_RISE
			for x in range(base + 5, base + 8):
				solid[Vector2i(x, top_row)] = true
			orb_cells.append(Vector2i(base + 6, top_row - 1))

	var end_base: int = START_W + orb_count * SECTION_W
	return {
		"w": width,
		"solid": solid,
		"orb_cells": orb_cells,
		"console_x": end_base + 4,
		"portal_x": end_base + 10,
		"spawn": Vector2i(2, GROUND_ROW),
	}


func _carve_pit(solid: Dictionary, x: int) -> void:
	for y in range(GROUND_ROW, LEVEL_H):
		solid.erase(Vector2i(x, y))


func _load_world(index: int) -> void:
	adv.enter_world(index)
	if _room != null:
		_room.queue_free()
	_orbs.clear()
	_console = null
	_portal = null
	_near = null
	_room = Node2D.new()
	add_child(_room)

	var orb_count: int = adv.orbs_total(index)
	var plan := _plan_level(orb_count)
	_level_w = plan.w
	_build_level_geometry(plan)

	# Skill orbs (only the ones still uncollected — the ground stays the same).
	var world_id := str(world.world_at(index).get("id", ""))
	for i in orb_count:
		var skill := str(world.orbs(index)[i].get("skill", "?"))
		if state.has_orb(world_id, skill):
			continue
		_add_orb(i, skill, plan.orb_cells[i])

	# Trial console and the portal, standing on the end plateau.
	_console = _make_interactable(Interactable.Kind.CONSOLE, "console", "TRIAL", plan.console_x)
	_console.done_sprite = "console_done"
	if adv.is_passed(index):
		_console.set_cleared(true)
	var portal_label := "PORTAL" if not world.is_final(index) else "THE THRONE"
	_portal = _make_interactable(Interactable.Kind.SIGN, "door", portal_label, plan.portal_x)

	_camera.limit_right = _level_w * TILE
	_camera.limit_bottom = LEVEL_H * TILE
	_player.position = Vector2((plan.spawn.x + 0.5) * TILE, plan.spawn.y * TILE)
	_player.velocity = Vector2.ZERO
	_safe_pos = _player.position

	_refresh_hud()
	if not _resumed and not _intro_shown.has(index):
		_intro_shown[index] = true
		var wd := world.world_at(index)
		_show_dialogue(str(wd.get("name", "")), wd.get("intro", ["A new world."]))


func _build_level_geometry(plan: Dictionary) -> void:
	var tiles := Node2D.new()
	tiles.name = "Tiles"
	_room.add_child(tiles)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_room.add_child(body)
	var scale := Vector2(TILE / 16.0, TILE / 16.0)
	var solid: Dictionary = plan.solid

	for cell in solid:
		var c: Vector2i = cell
		# A tile with nothing above it is a surface you can stand on; draw those
		# as floor and everything buried below as wall, so the course reads at a
		# glance as ground, ledges and pits.
		var exposed: bool = not solid.has(Vector2i(c.x, c.y - 1))
		var art := "floor" if exposed else "wall"
		var roll: int = abs(hash(c)) % 100
		if exposed and roll < 16:
			art = "floor_alt"
		elif not exposed and roll < 34:
			art = "wall_alt"
		var spr := Sprite2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.texture = SpriteFactory.texture(art)
		spr.scale = scale
		spr.position = Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)
		spr.z_index = 1 if not exposed else 2
		tiles.add_child(spr)

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = spr.position
		body.add_child(shape)


func _add_orb(index: int, skill: String, cell: Vector2i) -> void:
	var node := Node2D.new()
	node.position = Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
	_room.add_child(node)
	var spr := Sprite2D.new()
	spr.texture = _orb_texture()
	spr.scale = Vector2(2.4, 2.4)
	node.add_child(spr)
	var label := Label.new()
	label.text = skill
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-60, -54)
	label.size = Vector2(120, 16)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiTheme.ACCENT)
	label.add_theme_color_override("font_outline_color", UiTheme.BG)
	label.add_theme_constant_override("outline_size", 6)
	node.add_child(label)
	node.z_index = 6
	node.set_meta("spr", spr)
	node.set_meta("base_y", spr.position.y)
	_orbs.append({"node": node, "index": index})


static var _orb_tex: ImageTexture
func _orb_texture() -> ImageTexture:
	if _orb_tex != null:
		return _orb_tex
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := UiTheme.ACCENT
	var center := Vector2(n / 2.0 - 0.5, n / 2.0 - 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(center) / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	_orb_tex = ImageTexture.create_from_image(img)
	return _orb_tex


## Place a prop standing on the ground at a column, sprite resting on the surface.
func _make_interactable(kind: Interactable.Kind, sprite: String, label: String, col: int) -> Interactable:
	var it := Interactable.new()
	it.kind = kind
	it.sprite_name = sprite
	it.label_text = label
	it.position = Vector2((col + 0.5) * TILE, GROUND_ROW * TILE - 24)
	it.z_index = 6
	_room.add_child(it)
	return it


func _build_player() -> void:
	_player = Player2D.new()
	add_child(_player)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.5, 1.5)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 7.0
	_camera.limit_left = 0
	_camera.limit_top = 0
	_player.add_child(_camera)
	_camera.position = Vector2(0, -60)   # look a little above the feet
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

	var top := PanelContainer.new()
	top.theme_type_variation = &"CardPanel"
	top.position = Vector2(18, 18)
	top.custom_minimum_size = Vector2(420, 0)
	root.add_child(top)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	top.add_child(vb)
	_world_label = Label.new()
	_world_label.theme_type_variation = &"AccentLabel"
	vb.add_child(_world_label)
	_sub_label = Label.new()
	_sub_label.theme_type_variation = &"DimLabel"
	vb.add_child(_sub_label)
	var skills_title := Label.new()
	skills_title.text = "SKILLS"
	skills_title.theme_type_variation = &"CapsLabel"
	vb.add_child(skills_title)
	_skills_box = HFlowContainer.new()
	_skills_box.add_theme_constant_override("h_separation", 6)
	vb.add_child(_skills_box)

	var orb_panel := PanelContainer.new()
	orb_panel.theme_type_variation = &"ChipPanel"
	orb_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	orb_panel.position = Vector2(-260, 18)
	orb_panel.custom_minimum_size = Vector2(240, 0)
	root.add_child(orb_panel)
	_orb_label = Label.new()
	_orb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_orb_label.theme_type_variation = &"AccentLabel"
	orb_panel.add_child(_orb_label)

	var prompt_panel := PanelContainer.new()
	prompt_panel.theme_type_variation = &"ChipPanel"
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.position = Vector2(-250, -70)
	prompt_panel.custom_minimum_size = Vector2(500, 0)
	root.add_child(prompt_panel)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.text = "A D / ← → run   ·   Space or W jump   ·   E at a console   ·   Esc menu"
	_prompt_label.theme_type_variation = &"DimLabel"
	prompt_panel.add_child(_prompt_label)


func _refresh_hud() -> void:
	if _world_label == null:
		return
	var idx := state.world_index
	var wd := world.world_at(idx)
	_world_label.text = str(wd.get("name", "?"))
	_sub_label.text = str(wd.get("subtitle", ""))
	for c in _skills_box.get_children():
		c.queue_free()
	if state.skills.is_empty():
		var l := Label.new(); l.text = "none yet"; l.theme_type_variation = &"FaintLabel"
		_skills_box.add_child(l)
	else:
		for skill in state.skills:
			var chip := PanelContainer.new()
			chip.theme_type_variation = &"NewChipPanel"
			var l := Label.new(); l.text = str(skill); l.theme_type_variation = &"AccentLabel"
			chip.add_child(l)
			_skills_box.add_child(chip)
	if adv.is_passed(idx):
		_orb_label.text = "TRIAL PASSED ✔"
	elif adv.all_orbs_collected(idx):
		_orb_label.text = "TRIAL READY — use the console"
	else:
		_orb_label.text = "ORBS  %d / %d" % [adv.orbs_collected_count(idx), adv.orbs_total(idx)]


# --- dialogue (world intros + lesson cards) ---------------------------------

func _build_dialogue() -> void:
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.layer = 6
	add_child(_dialogue_layer)
	_dialogue = Control.new()
	_dialogue.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialogue.theme = _theme
	_dialogue_layer.add_child(_dialogue)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-380, -230)
	panel.custom_minimum_size = Vector2(760, 150)
	_dialogue.add_child(panel)
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
	_dialogue_pages = []
	var page: Array = []
	for line in lines:
		page.append(str(line))
		if page.size() >= 6:
			_dialogue_pages.append(page); page = []
	if not page.is_empty():
		_dialogue_pages.append(page)
	_dialogue_page = 0
	_player.input_locked = true
	_dialogue.show()
	_render_dialogue_page()


func _render_dialogue_page() -> void:
	_dialogue_body.text = "\n".join(PackedStringArray(_dialogue_pages[_dialogue_page]))


func _advance_dialogue() -> void:
	_dialogue_page += 1
	if _dialogue_page >= _dialogue_pages.size():
		_dialogue.hide()
		# A lesson card hands straight over to a prompt to try the command on.
		if not _pending_practice.is_empty():
			var lesson: Dictionary = _pending_practice
			_pending_practice = {}
			_open_practice(lesson)
			return
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


func _open_overlay(title: String) -> void:
	_overlay_title.text = title
	_terminal.clear_screen()
	_terminal.history = Game.session.history
	_overlay.show()
	_hud.visible = false
	_player.input_locked = true
	var s: ShellSession = Game.session
	_terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())
	_terminal.focus_input()


func _open_terminal() -> void:
	var idx := state.world_index
	var trial: Dictionary = world.world_at(idx).get("trial", {})
	_overlay_mode = "trial"
	adv.engage_trial(idx)
	_open_overlay("TRIAL — " + str(trial.get("name", world.world_at(idx).get("name", "Console"))))


## Taking an orb doesn't just explain a command — it hands you a prompt to run
## it on. The world's trial files are laid out first so the example actually
## works, but nothing here is graded: any use of the command counts, and you can
## poke at anything else you like.
func _open_practice(lesson: Dictionary) -> void:
	_overlay_mode = "practice"
	_practice_skill = str(lesson.get("skill", ""))
	_practice_done = false
	adv.prepare_practice(state.world_index)
	_open_overlay("PRACTICE — " + _practice_skill)
	_terminal.print_rule("NEW SKILL  ·  " + _practice_skill)
	_terminal.type_text("")
	_terminal.type_text("  " + str(lesson.get("teaches", "")), "story")
	var example := str(lesson.get("example", ""))
	if example != "":
		_terminal.type_text("")
		_terminal.type_text("  try it:   " + example, "tip")
	_terminal.type_text("")
	_terminal.type_text("  Nothing is graded here — run it, break it, look around.", "dim")
	_terminal.type_text("  [Esc] when you're done.", "dim")
	_terminal.type_text("")


func _close_terminal() -> void:
	_overlay.hide()
	_hud.visible = true
	adv.disengage()
	_overlay_mode = ""
	if not _dialogue.visible:
		_player.input_locked = false
	_refresh_hud()


# --- interaction ------------------------------------------------------------

## Orbs are picked up against the player's chest rather than their feet, so an
## orb floating a tile above a ledge is taken by standing under it or jumping
## through it — either reads as "I touched it".
func _player_center() -> Vector2:
	return _player.global_position + Vector2(0, -21)


func _process(delta: float) -> void:
	for o in _orbs:
		var node: Node2D = o.node
		if not is_instance_valid(node):
			continue
		var spr: Sprite2D = node.get_meta("spr")
		spr.position.y = node.get_meta("base_y") + sin(Time.get_ticks_msec() / 1000.0 * 3.0 + o.index) * 4.0
	if _overlay.visible or _dialogue.visible:
		if _near:
			_near.show_prompt(false); _near = null
		return

	# Remember the last solid footing, and fish the player out of a pit rather
	# than punishing them for it — mistakes here are always recoverable.
	if _player.is_on_floor():
		_safe_pos = _player.global_position
	elif _player.global_position.y > (LEVEL_H + 3) * TILE:
		_respawn()

	for o in _orbs.duplicate():
		var node: Node2D = o.node
		if is_instance_valid(node) and node.global_position.distance_to(_player_center()) < ORB_PICKUP:
			_collect_orb(o)
	# Nearest console/portal for the [E] prompt.
	var best: Interactable = null
	var best_d := INTERACT_RANGE
	for it in [_console, _portal]:
		if it == null or not is_instance_valid(it):
			continue
		var d: float = it.global_position.distance_to(_player_center())
		if d < best_d:
			best_d = d; best = it
	if best != _near:
		if _near: _near.show_prompt(false)
		_near = best
		if _near: _near.show_prompt(true)


func _respawn() -> void:
	_player.global_position = _safe_pos
	_player.velocity = Vector2.ZERO
	_player.modulate = Color(1, 1, 1, 0.25)
	create_tween().tween_property(_player, "modulate:a", 1.0, 0.45)


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
	var idx := state.world_index
	if it == _console:
		if adv.is_passed(idx):
			_show_dialogue("Trial", ["You've already passed this trial. The console idles quietly.", "The portal ahead is open — step through it."])
		elif adv.all_orbs_collected(idx):
			_open_terminal()
		else:
			var missing := adv.orbs_total(idx) - adv.orbs_collected_count(idx)
			_show_dialogue("Trial", ["The console is locked.", "Collect the remaining %d skill orb%s first — the trial needs them." % [missing, "" if missing == 1 else "s"]])
	elif it == _portal:
		if adv.is_passed(idx):
			if adv.advance():
				if adv.is_active():
					_load_world(state.world_index)
		else:
			_show_dialogue("Portal", ["The portal is dark.", "Pass this world's trial at the console to wake it."])


func _collect_orb(o: Dictionary) -> void:
	var idx := state.world_index
	var lesson := adv.collect_orb(idx, o.index)
	_orbs.erase(o)
	if is_instance_valid(o.node):
		var node: Node2D = o.node
		var tw := create_tween()
		tw.tween_property(node, "scale", Vector2(1.6, 1.6), 0.15)
		tw.parallel().tween_property(node, "modulate:a", 0.0, 0.2)
		tw.tween_callback(node.queue_free)
	if not lesson.is_empty():
		_pending_practice = lesson
		_show_dialogue("Skill learned:  %s" % lesson.get("skill", "?"), [
			str(lesson.get("teaches", "")),
			"",
			"[E] — try it at a real prompt",
		])
	_refresh_hud()


# --- signal handlers --------------------------------------------------------

func _on_command_output(outcome: ExecutionOutcome) -> void:
	if not _overlay.visible:
		return
	_terminal.print_outcome(outcome)
	var s: ShellSession = Game.session
	_terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())
	if _overlay_mode != "practice" or _practice_done:
		return
	for r in outcome.records:
		if str(r.get("name", "")) == _practice_skill:
			_practice_done = true
			_terminal.type_text("")
			_terminal.type_text("  ✔ that's `%s` — it's yours now. [Esc] back to the climb." % _practice_skill, "success")
			break


func _on_narrate(text: String, kind: String) -> void:
	if not _overlay.visible:
		return
	_terminal.type_text("")
	for line in text.split("\n"):
		_terminal.type_text("  " + line if line != "" else "", kind)


func _on_trial_passed(_world_id: String, _reward: Dictionary) -> void:
	if _console != null and is_instance_valid(_console):
		_console.set_cleared(true)
	_refresh_hud()
	if _overlay.visible:
		_terminal.type_text("")
		_terminal.type_text("  [Esc] step back — the portal ahead is open.", "tip")


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
	create_tween().tween_property(dim, "color:a", 0.94, 1.0)
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
		l.theme_type_variation = &"AccentLabel" if str(line).begins_with("root@") or str(line).begins_with("YOU MADE IT") else &""
		vb.add_child(l)
	var cont := Label.new()
	cont.text = "\n[ Esc ] return to the menu"
	cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cont.theme_type_variation = &"FaintLabel"
	vb.add_child(cont)
	if _overlay.visible:
		_close_terminal()
	_player.input_locked = true
