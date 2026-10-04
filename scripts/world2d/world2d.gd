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
const END_W := 14             # the plateau holding the console and the portal
const PLATFORM_RISE := 2      # rows a platform sits above its launch surface

## The pieces a course is built from. `w` is its width in tiles; `orb` marks the
## ones that can hold a skill orb, and the generator fills those left to right.
const SEGMENTS := {
	"flat":   {"w": 5,  "orb": false},   # breathing room
	"gap":    {"w": 6,  "orb": false},   # a pit to clear
	"spikes": {"w": 6,  "orb": false},   # a strip of ground you must jump
	"rover":  {"w": 9,  "orb": false},   # a patrol to time
	"burst":  {"w": 7,  "orb": false},   # a pulse to read
	"ledge":  {"w": 9,  "orb": true},    # orb on a ledge over a pit
	"stair":  {"w": 10, "orb": true},    # orb at the top of a two-step climb
	"lift":   {"w": 11, "orb": true},    # orb over a gap only a lift crosses
	"tower":  {"w": 9,  "orb": true},    # orb at the top of a zig-zag climb
}

## What each world is built from when its JSON doesn't say, and the colour its
## tiles are cut from. The order is the difficulty curve: world 1 only asks you
## to jump, and every world after it adds exactly one new thing to read.
const DEFAULT_COURSES := [
	["ledge", "gap", "ledge", "flat", "stair"],
	["ledge", "spikes", "stair", "spikes", "ledge"],
	["ledge", "rover", "stair", "rover", "ledge"],
	["tower", "gap", "lift", "spikes", "tower"],
	["ledge", "burst", "stair", "burst", "tower"],
	["rover", "tower", "spikes", "lift", "burst", "stair"],
]
const DEFAULT_PALETTES := ["blue", "green", "red", "violet", "orange", "red"]

## Backdrop tint per palette — the machine receding into the dark behind you.
const PALETTE_TINTS := {
	"blue": Color("2b3a7a"), "red": Color("7a2b35"), "green": Color("1f6b4e"),
	"orange": Color("8a4a1f"), "violet": Color("53398c"),
}
const LOOKAHEAD := 96.0         # how far the camera leads you when running

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
var _backdrop: CanvasLayer
var _hazards: Array = []
var _hazard_grace := 0.0          # brief immunity after a setback
var _safe_pos := Vector2.ZERO     # last spot the player stood on solid ground
var _intro_shown: Dictionary = {} # world index -> true

# HUD / dialogue / overlay
var _hud: CanvasLayer
var _world_label: Label
var _sub_label: Label
var _skills_box: HFlowContainer
var _orb_label: Label
var _prompt_label: Label
var _flash_label: Label
var _dialogue_layer: CanvasLayer
var _dialogue: Control
var _dialogue_name: Label
var _dialogue_body: RichTextLabel
var _dialogue_pages: Array = []
var _dialogue_page := 0
var _overlay: Control
var _overlays: InteractiveOverlays
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

	# Interactive programs (nano, less, tail -f, su) open above the trial console,
	# the same host the campaign screen uses, so they work inside the Ascent too.
	_overlays = InteractiveOverlays.new()
	_overlays.install(self, _focus_terminal)
	_overlays.editor_closed.connect(func(saved: bool):
		if saved and _terminal != null:
			_terminal.print_text(I18n.t("  [ file saved ]"), "dim"))

	adv.battle_won.connect(_on_trial_passed)
	adv.adventure_won.connect(_on_adventure_won)
	adv.state_changed.connect(_refresh_hud)
	EventBus.command_output.connect(_on_command_output)
	EventBus.narrate.connect(_on_narrate)

	_load_world(state.world_index)
	if not _resumed:
		_show_dialogue(I18n.t("The Ascent to Root"), world.intro)


# --- building a world's course ----------------------------------------------

## What a world is built from: its own `course` if the JSON names one, else the
## default recipe for its position in the climb. Never returns a course with
## fewer orb slots than the world has orbs.
func _course_for(index: int) -> Array:
	var course: Array = world.world_at(index).get("course", [])
	if course.is_empty():
		course = DEFAULT_COURSES[index % DEFAULT_COURSES.size()]
	course = course.duplicate()
	var slots := 0
	for seg in course:
		if SEGMENTS.get(seg, {}).get("orb", false):
			slots += 1
	while slots < adv.orbs_total(index):
		course.append("ledge")
		slots += 1
	return course


func _palette_for(index: int) -> String:
	var fallback: String = DEFAULT_PALETTES[index % DEFAULT_PALETTES.size()]
	return str(world.world_at(index).get("palette", fallback))


## Lay a course out as a grid of solid tiles plus the things that sit on it.
## Deterministic: the same world always builds the same level, whether or not
## its orbs have already been taken.
func _plan_level(index: int) -> Dictionary:
	var orb_count: int = adv.orbs_total(index)
	var course := _course_for(index)
	var solid: Dictionary = {}
	var orb_cells: Array = []
	var hazards: Array = []
	var lifts: Array = []

	var width := START_W + END_W
	for seg in course:
		width += int(SEGMENTS.get(seg, {}).get("w", 5))

	# Earth everywhere, then carve each segment out of it.
	for x in width:
		for y in range(GROUND_ROW, LEVEL_H):
			solid[Vector2i(x, y)] = true
	# Sealed ends, so you can never run out of the level sideways.
	for y in LEVEL_H:
		solid[Vector2i(0, y)] = true
		solid[Vector2i(width - 1, y)] = true

	var base := START_W
	for seg in course:
		var want_orb: bool = SEGMENTS.get(seg, {}).get("orb", false) and orb_cells.size() < orb_count
		_carve_segment(str(seg), base, solid, orb_cells, hazards, lifts, want_orb)
		base += int(SEGMENTS.get(seg, {}).get("w", 5))

	return {
		"w": width,
		"solid": solid,
		"orb_cells": orb_cells,
		"hazards": hazards,
		"lifts": lifts,
		"palette": _palette_for(index),
		"console_x": base + 4,
		"portal_x": base + 10,
		"spawn": Vector2i(2, GROUND_ROW),
	}


## Write one segment into the level. Every ledge is PLATFORM_RISE above the
## surface you jump from and every pit is at most 3 wide, except a lift's, which
## is meant to be uncrossable on foot — ui_smoke holds this to those rules.
func _carve_segment(seg: String, base: int, solid: Dictionary, orbs: Array,
		hazards: Array, lifts: Array, want_orb: bool) -> void:
	var r2: int = GROUND_ROW - PLATFORM_RISE
	var r4: int = GROUND_ROW - PLATFORM_RISE * 2
	var r6: int = GROUND_ROW - PLATFORM_RISE * 3
	match seg:
		"gap":
			for x in range(base + 2, base + 5):
				_carve_pit(solid, x)
		"spikes":
			for x in range(base + 2, base + 4):
				hazards.append({"kind": Hazard.Kind.SPIKES, "cell": Vector2i(x, GROUND_ROW - 1)})
		"rover":
			hazards.append({"kind": Hazard.Kind.ROVER, "cell": Vector2i(base + 4, GROUND_ROW - 1),
				"from": base + 2, "to": base + 7})
		"burst":
			hazards.append({"kind": Hazard.Kind.BURST, "cell": Vector2i(base + 3, GROUND_ROW - 1)})
		"ledge":
			# The orb floats over the pit, on a ledge one jump up: clearing the
			# pit and taking the orb are different jumps, so you can always skip.
			for x in range(base + 3, base + 6):
				_carve_pit(solid, x)
				solid[Vector2i(x, r2)] = true
			if want_orb:
				orbs.append(Vector2i(base + 4, r2 - 1))
		"stair":
			for x in range(base + 4, base + 6):
				_carve_pit(solid, x)
			for x in range(base + 2, base + 4):
				solid[Vector2i(x, r2)] = true
			for x in range(base + 5, base + 8):
				solid[Vector2i(x, r4)] = true
			if want_orb:
				orbs.append(Vector2i(base + 6, r4 - 1))
		"lift":
			for x in range(base + 2, base + 9):
				_carve_pit(solid, x)
			lifts.append({"from": base + 2, "to": base + 8, "row": GROUND_ROW - 1, "tiles": 2})
			if want_orb:
				orbs.append(Vector2i(base + 5, GROUND_ROW - 3))
		"tower":
			# A zig-zag climb: left, right, left, with the orb at the top.
			for x in range(base + 2, base + 4):
				solid[Vector2i(x, r2)] = true
			for x in range(base + 5, base + 7):
				solid[Vector2i(x, r4)] = true
			for x in range(base + 2, base + 4):
				solid[Vector2i(x, r6)] = true
			if want_orb:
				orbs.append(Vector2i(base + 2, r6 - 1))


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
	var plan := _plan_level(index)
	_level_w = plan.w
	_build_backdrop(str(plan.palette))
	_build_level_geometry(plan)

	_hazards.clear()
	for h in plan.hazards:
		var hz := Hazard.make(h.kind, h.cell)
		if h.has("from"):
			hz.patrol(int(h.from), int(h.to))
		_room.add_child(hz)
		_hazards.append(hz)
	for l in plan.lifts:
		_room.add_child(MovingPlatform.make(int(l.from), int(l.to), int(l.row), int(l.tiles)))

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
	var portal_label := I18n.t("PORTAL") if not world.is_final(index) else I18n.t("THE THRONE")
	_portal = _make_interactable(Interactable.Kind.SIGN, "door", portal_label, plan.portal_x)

	_camera.limit_right = _level_w * TILE
	_camera.limit_bottom = LEVEL_H * TILE
	_player.position = Vector2((plan.spawn.x + 0.5) * TILE, plan.spawn.y * TILE)
	_player.velocity = Vector2.ZERO
	_safe_pos = _player.position
	_hazard_grace = 0.0

	_refresh_hud()
	if not _resumed and not _intro_shown.has(index):
		_intro_shown[index] = true
		var wd := world.world_at(index)
		_show_dialogue(str(wd.get("name", "")), wd.get("intro", [I18n.t("A new world.")]))


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
		var pal: String = plan.palette
		var art: String = pal + "_floor" if exposed else pal + "_wall"
		var roll: int = abs(hash(c)) % 100
		if exposed and roll < 22:
			art = pal + "_floor_alt"
		elif not exposed and roll < 34:
			art = pal + "_wall_alt"
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
	spr.texture = SpriteFactory.glow(UiTheme.ACCENT)
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


## Racks of machine receding into the dark, on two parallax layers. Without
## these the courses float on flat black, which reads as unfinished rather than
## as depth. Generated rather than drawn: it is a silhouette, and a seed gives
## every world its own skyline.
func _build_backdrop(palette: String) -> void:
	if _backdrop != null:
		_backdrop.queue_free()
	var tint: Color = PALETTE_TINTS.get(palette, Color("2b3a7a"))
	_backdrop = ParallaxBackground.new()
	_backdrop.layer = -10
	add_child(_backdrop)
	# Far layer sits low and barely moves; the near one is taller and darker,
	# so the two read as distance rather than as one wallpaper.
	for spec in [
		{"seed": 11, "scale": Vector2(0.10, 0.03), "y": 150.0, "shade": 0.45, "h": 74},
		{"seed": 29, "scale": Vector2(0.28, 0.07), "y": 250.0, "shade": 0.24, "h": 110},
	]:
		var layer := ParallaxLayer.new()
		layer.motion_scale = spec.scale
		_backdrop.add_child(layer)
		var tex := _rack_texture(int(spec.seed), tint * float(spec.shade), int(spec.h))
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = false
		spr.scale = Vector2(3, 3)
		spr.position = Vector2(0, float(spec.y))
		layer.add_child(spr)
		layer.motion_mirroring = Vector2(tex.get_width() * 3, 0)


## One tile of skyline: racks of varying height with a lit top edge and a few
## status LEDs, on transparent. Deterministic for a given seed.
func _rack_texture(rack_seed: int, tint: Color, height: int) -> ImageTexture:
	var w := 192
	var img := Image.create(w, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = rack_seed
	var x := 0
	while x < w:
		var rw := rng.randi_range(7, 17)
		var top := rng.randi_range(int(height * 0.18), int(height * 0.72))
		for px in range(x, mini(x + rw, w)):
			for py in range(top, height):
				img.set_pixel(px, py, tint if py > top else tint.lightened(0.45))
		# A couple of lit vents, so it reads as machine and not as buildings.
		for i in 3:
			var ly := rng.randi_range(top + 3, height - 2)
			var lx := x + rng.randi_range(1, maxi(1, rw - 2))
			if lx < w and ly < height:
				img.set_pixel(lx, ly, tint.lightened(0.7))
		x += rw + rng.randi_range(2, 7)
	return ImageTexture.create_from_image(img)


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
	skills_title.text = I18n.t("SKILLS")
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
	_prompt_label.text = I18n.t("A D / ← → run   ·   Space or W jump   ·   E at a console   ·   Esc menu")
	_prompt_label.theme_type_variation = &"DimLabel"
	prompt_panel.add_child(_prompt_label)

	# Says what just happened when you are put back — a flash alone leaves you
	# wondering whether you lost something.
	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash_label.position = Vector2(-220, 120)
	_flash_label.size = Vector2(440, 24)
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.theme_type_variation = &"AccentLabel"
	_flash_label.add_theme_color_override("font_color", UiTheme.WARN)
	_flash_label.add_theme_color_override("font_outline_color", UiTheme.BG)
	_flash_label.add_theme_constant_override("outline_size", 6)
	_flash_label.modulate.a = 0.0
	root.add_child(_flash_label)


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
		var l := Label.new(); l.text = I18n.t("none yet"); l.theme_type_variation = &"FaintLabel"
		_skills_box.add_child(l)
	else:
		for skill in state.skills:
			var chip := PanelContainer.new()
			chip.theme_type_variation = &"NewChipPanel"
			var l := Label.new(); l.text = str(skill); l.theme_type_variation = &"AccentLabel"
			chip.add_child(l)
			_skills_box.add_child(chip)
	if adv.is_passed(idx):
		_orb_label.text = I18n.t("TRIAL PASSED ✔")
	elif adv.all_orbs_collected(idx):
		_orb_label.text = I18n.t("TRIAL READY — use the console")
	else:
		_orb_label.text = I18n.t("ORBS  %d / %d") % [adv.orbs_collected_count(idx), adv.orbs_total(idx)]


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
	hint.text = I18n.t("[E] continue")
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
	esc.text = I18n.t("Esc  step back to the world")
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


func _focus_terminal() -> void:
	if _terminal != null:
		_terminal.focus_input()


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
	# Show and clear the terminal BEFORE engaging the trial: engage_trial emits
	# the objective briefing as narration, and _on_narrate only prints while the
	# overlay is visible. Then re-set the prompt, because engage_trial moves the
	# shell into the trial's cwd.
	_open_overlay(I18n.t("TRIAL — %s") % str(trial.get("name", world.world_at(idx).get("name", "Console"))))
	adv.engage_trial(idx)
	var s: ShellSession = Game.session
	_terminal.set_prompt(s.user, s.machine.hostname, s.pretty_cwd(), s.prompt_symbol())


## Taking an orb doesn't just explain a command — it hands you a prompt to run
## it on. The world's trial files are laid out first so the example actually
## works, but nothing here is graded: any use of the command counts, and you can
## poke at anything else you like.
func _open_practice(lesson: Dictionary) -> void:
	_overlay_mode = "practice"
	_practice_skill = str(lesson.get("skill", ""))
	_practice_done = false
	adv.prepare_practice(state.world_index)
	_open_overlay(I18n.t("PRACTICE — %s") % _practice_skill)
	_terminal.print_rule(I18n.t("NEW SKILL  ·  %s") % _practice_skill)
	_terminal.type_text("")
	_terminal.type_text("  " + str(lesson.get("teaches", "")), "story")
	var example := str(lesson.get("example", ""))
	if example != "":
		_terminal.type_text("")
		_terminal.type_text("  " + I18n.t("try it:") + "   " + example, "tip")
	_terminal.type_text("")
	_terminal.type_text("  " + I18n.t("Nothing is graded here — run it, break it, look around."), "dim")
	_terminal.type_text("  " + I18n.t("[Esc] when you're done."), "dim")
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
	# Lead the camera in the direction of travel, so you can see what you are
	# running into rather than what you already cleared.
	var lead := 0.0
	if absf(_player.velocity.x) > 20.0:
		lead = signf(_player.velocity.x) * LOOKAHEAD
	_camera.position.x = move_toward(_camera.position.x, lead, delta * 180.0)

	_hazard_grace = maxf(0.0, _hazard_grace - delta)
	if _overlay.visible or _dialogue.visible:
		if _near:
			_near.show_prompt(false); _near = null
		return

	# Remember the last solid footing — but never a spot inside a hazard, or a
	# setback would drop you straight back into the thing that got you.
	if _player.is_on_floor() and _clear_of_hazards(_player.global_position):
		_safe_pos = _player.global_position
	elif _player.global_position.y > (LEVEL_H + 3) * TILE:
		_setback()

	if _hazard_grace <= 0.0:
		for hz in _hazards:
			if is_instance_valid(hz) and hz.is_live() and hz.overlaps_body(_player):
				_setback()
				break

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


func _clear_of_hazards(p: Vector2) -> bool:
	for hz in _hazards:
		if is_instance_valid(hz) and p.distance_to(hz.global_position) < TILE * 1.6:
			return false
	return true


## The only consequence in the whole mode: you are put back down on the last
## ground you stood on. No health, no lives, no run to lose.
func _setback() -> void:
	Audio.play("setback")
	_player.global_position = _safe_pos
	_player.velocity = Vector2.ZERO
	_hazard_grace = 1.0
	_player.modulate = Color(1.0, 0.45, 0.6, 0.35)
	create_tween().tween_property(_player, "modulate", Color.WHITE, 0.5)
	if _flash_label != null:
		_flash_label.text = I18n.t("set back — nothing lost, try it again")
		_flash_label.modulate.a = 1.0
		create_tween().tween_property(_flash_label, "modulate:a", 0.0, 1.6)


func _unhandled_input(event: InputEvent) -> void:
	# An interactive program (editor/pager/prompt) is modal: it handles its own
	# keys, so the world and the trial console below must stay inert.
	if _overlays != null and _overlays.any_visible():
		return
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
			_show_dialogue(I18n.t("Trial"), [I18n.t("You've already passed this trial. The console idles quietly."), I18n.t("The portal ahead is open — step through it.")])
		elif adv.all_orbs_collected(idx):
			_open_terminal()
		else:
			var missing := adv.orbs_total(idx) - adv.orbs_collected_count(idx)
			var need := I18n.t("Collect the remaining skill orb first — the trial needs it.") if missing == 1 else (I18n.t("Collect the remaining %d skill orbs first — the trial needs them.") % missing)
			_show_dialogue(I18n.t("Trial"), [I18n.t("The console is locked."), need])
	elif it == _portal:
		if adv.is_passed(idx):
			if adv.advance():
				Audio.play("portal")
				if adv.is_active():
					_load_world(state.world_index)
		else:
			_show_dialogue(I18n.t("Portal"), [I18n.t("The portal is dark."), I18n.t("Pass this world's trial at the console to wake it.")])


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
		_show_dialogue(I18n.t("Skill learned:  %s") % lesson.get("skill", "?"), [
			str(lesson.get("teaches", "")),
			"",
			I18n.t("[E] — try it at a real prompt"),
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
			_terminal.type_text(I18n.t("  ✔ that's `%s` — it's yours now. [Esc] back to the climb.") % _practice_skill, "success")
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
		_terminal.type_text("  " + I18n.t("[Esc] step back — the portal ahead is open."), "tip")


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
	cont.text = "\n" + I18n.t("[ Esc ] return to the menu")
	cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cont.theme_type_variation = &"FaintLabel"
	vb.add_child(cont)
	if _overlay.visible:
		_close_terminal()
	_player.input_locked = true
