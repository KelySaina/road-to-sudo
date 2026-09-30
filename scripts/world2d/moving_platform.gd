class_name MovingPlatform
extends AnimatableBody2D
## A lift ferrying you across a gap too wide to jump.
##
## AnimatableBody2D with sync_to_physics carries whatever is standing on it, so
## the player rides it without any special handling in the controller.

const TILE := 48
const SPEED := 74.0

var _tiles := 2
var _min_x := 0.0
var _max_x := 0.0
var _dir := 1.0


## Build a lift `tiles` wide that shuttles between two tile columns on `row`.
static func make(from_col: int, to_col: int, row: int, tiles: int = 2) -> MovingPlatform:
	var p := MovingPlatform.new()
	p._tiles = tiles
	p._min_x = (from_col + 0.5) * TILE
	p._max_x = (to_col + 0.5) * TILE
	p.position = Vector2(p._min_x, (row + 0.5) * TILE)
	return p


func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1
	collision_mask = 0
	z_index = 5
	var width := _tiles * TILE
	for i in _tiles:
		var spr := Sprite2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.texture = SpriteFactory.texture("crate")
		spr.scale = Vector2(3, 3)
		spr.position = Vector2((i + 0.5) * TILE - width * 0.5, 0)
		add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, TILE)
	shape.shape = rect
	add_child(shape)


func _physics_process(delta: float) -> void:
	position.x += _dir * SPEED * delta
	if position.x <= _min_x:
		position.x = _min_x; _dir = 1.0
	elif position.x >= _max_x:
		position.x = _max_x; _dir = -1.0
