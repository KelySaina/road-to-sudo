class_name Interactable
extends Area2D
## A thing in the world you can walk up to and press E on: a console (opens a
## terminal battle), an NPC (dialogue), a boss, or a key pickup. Doors are
## separate (Blocker). Purely presentational + a bit of metadata; the World2D
## controller decides what interacting does.

enum Kind { NPC, CONSOLE, BOSS, KEY, SIGN }

var kind: Kind = Kind.NPC
var node_id: String = ""          # adventure node this maps to
var label_text: String = ""
var sprite_name: String = ""
var done_sprite: String = ""      # shown once its node is cleared
var interact_verb: String = "talk"

var _sprite: Sprite2D
var _label: Label
var _hint: Label
var _cleared := false
var _base_y := 0.0
var _t := 0.0


func setup(p_kind: Kind, p_sprite: String, p_label: String) -> void:
	kind = p_kind
	sprite_name = p_sprite
	label_text = p_label


func _ready() -> void:
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 64)
	shape.shape = rect
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = SpriteFactory.texture(sprite_name)
	_sprite.scale = Vector2(3, 3)
	add_child(_sprite)
	_base_y = _sprite.position.y

	_label = Label.new()
	_label.text = label_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-60, -52)
	_label.size = Vector2(120, 16)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", UiTheme.DIM)
	_label.add_theme_color_override("font_outline_color", UiTheme.BG)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)

	_hint = Label.new()
	_hint.text = "[E]"
	_hint.position = Vector2(-20, 26)
	_hint.size = Vector2(40, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", UiTheme.ACCENT)
	_hint.add_theme_color_override("font_outline_color", UiTheme.BG)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.visible = false
	add_child(_hint)
	z_index = int(global_position.y)


func _process(delta: float) -> void:
	_t += delta
	if kind == Kind.KEY:
		_sprite.position.y = _base_y + sin(_t * 3.0) * 4.0
	z_index = int(global_position.y)


func set_cleared(v: bool) -> void:
	_cleared = v
	if v and done_sprite != "":
		_sprite.texture = SpriteFactory.texture(done_sprite)
	if v and kind in [Kind.CONSOLE, Kind.BOSS]:
		_label.add_theme_color_override("font_color", UiTheme.SUCCESS)


func show_prompt(v: bool) -> void:
	_hint.visible = v and not (_cleared and kind != Kind.CONSOLE and kind != Kind.NPC)


func is_cleared() -> bool:
	return _cleared
