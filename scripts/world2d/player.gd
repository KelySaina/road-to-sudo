class_name Player2D
extends CharacterBody2D
## Top-down operator you steer with WASD / arrows. Builds its own sprite and
## collider so the world can spawn it in code.

const SPEED := 132.0
const TILE := 48

@warning_ignore("unused_signal")
signal moved()

var _char: CharacterSprite
var _facing := "down"
var _phase := 0.0
var input_locked := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 18)
	shape.shape = rect
	shape.position = Vector2(0, 12)
	add_child(shape)

	_char = CharacterSprite.new()
	_char.position = Vector2(0, -4)
	add_child(_char)
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
	var moving := dir != Vector2.ZERO
	if moving:
		if absf(dir.x) > absf(dir.y):
			_facing = "right" if dir.x > 0 else "left"
		else:
			_facing = "down" if dir.y > 0 else "up"
		_phase += delta * 9.5
	else:
		_phase = 0.0
	_char.facing = _facing
	_char.moving = moving
	_char.phase = _phase
	_char.queue_redraw()


func facing_dir() -> Vector2:
	match _facing:
		"up": return Vector2.UP
		"down": return Vector2.DOWN
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
	return Vector2.DOWN
