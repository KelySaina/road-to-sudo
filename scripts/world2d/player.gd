class_name Player2D
extends CharacterBody2D
## Top-down operator you steer with WASD / arrows. Builds its own sprite and
## collider so the world can spawn it in code.

const SPEED := 132.0
const TILE := 48

@warning_ignore("unused_signal")
signal moved()

var _sprite: Sprite2D
var _facing := "down"
var _bob := 0.0
var input_locked := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 20)
	shape.shape = rect
	shape.position = Vector2(0, 10)
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = SpriteFactory.texture("player")
	_sprite.scale = Vector2(3, 3)
	_sprite.position = Vector2(0, -14)
	add_child(_sprite)
	z_index = 10


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if not input_locked:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	_animate(dir, delta)
	z_index = 10 + int(global_position.y)


func _animate(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		_bob = 0.0
		_sprite.position.y = -14
		return
	if absf(dir.x) > absf(dir.y):
		_facing = "right" if dir.x > 0 else "left"
		_sprite.flip_h = dir.x < 0
	else:
		_facing = "down" if dir.y > 0 else "up"
	_bob += delta * 11.0
	_sprite.position.y = -14 + (2.0 if sin(_bob) > 0 else 0.0)


func facing_dir() -> Vector2:
	match _facing:
		"up": return Vector2.UP
		"down": return Vector2.DOWN
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
	return Vector2.DOWN
