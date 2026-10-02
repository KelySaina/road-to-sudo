class_name Player2D
extends CharacterBody2D
## Side-on operator for the platforming worlds: run, jump, fall. Builds its own
## avatar and collider so the world can spawn it in code. The avatar is
## CharacterSprite — vector-drawn rather than a tile, so it stays crisp at any
## zoom; this script only tells it which way it is facing and what it is doing.
##
## The origin sits at the character's FEET, which is what lets the world place
## it on a tile top with a plain `y = row * TILE`.
##
## Tuning note: with these numbers a full jump rises ~3.0 tiles and carries
## ~3.7 tiles across. The level generator assumes that — platforms never sit
## more than 2 tiles above the surface you jump from, and pits are 3 wide at
## most, so every orb is reachable without pixel-perfect timing.

const TILE := 48
const RUN_SPEED := 250.0
const ACCEL := 2400.0           # ground responsiveness
const AIR_ACCEL := 1500.0       # weaker in the air, so a jump commits a little
const FRICTION := 2800.0
const GRAVITY := 2150.0
const MAX_FALL := 1250.0
const JUMP_VELOCITY := -790.0
const JUMP_CUT := 0.42          # release early -> shorter hop
const COYOTE_TIME := 0.10       # grace after walking off a ledge
const JUMP_BUFFER := 0.12       # grace when you hit jump just before landing
const RUN_PHASE_PER_PX := 0.045  # run-cycle radians per pixel of ground covered

@warning_ignore("unused_signal")
signal moved()
signal landed()

var input_locked := false

var _char: CharacterSprite
var _facing := 1
var _coyote := 0.0
var _buffer := 0.0
var _phase := 0.0
var _was_airborne := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 8.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(26, 42)
	shape.shape = rect
	shape.position = Vector2(0, -21)
	add_child(shape)

	# CharacterSprite draws itself feet-on-origin, so scaling it keeps the feet
	# planted. Slightly larger than the collider, which is normal — the art
	# wants presence against 48px tiles, the hitbox wants to be forgiving.
	_char = CharacterSprite.new()
	_char.scale = Vector2(1.25, 1.25)
	add_child(_char)
	z_index = 10


func _physics_process(delta: float) -> void:
	var dir := 0.0
	var jump_pressed := false
	var jump_released := false
	if not input_locked:
		dir = Input.get_axis("move_left", "move_right")
		jump_pressed = Input.is_action_just_pressed("jump")
		jump_released = Input.is_action_just_released("jump")

	var on_floor := is_on_floor()

	# Horizontal: quick to start, with real friction so you can line up a landing.
	var rate := (ACCEL if on_floor else AIR_ACCEL) if not is_zero_approx(dir) else FRICTION
	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, rate * delta)

	if not on_floor:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# Coyote time and jump buffering — the two things that make a jump feel fair
	# rather than punishing. You may jump just after leaving a ledge, and a jump
	# pressed just before you land still fires.
	_coyote = COYOTE_TIME if on_floor else maxf(0.0, _coyote - delta)
	_buffer = JUMP_BUFFER if jump_pressed else maxf(0.0, _buffer - delta)
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		Audio.play("jump")
	# Variable height: let go on the way up and the hop is cut short.
	if jump_released and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	move_and_slide()
	_animate(dir, delta)

	if is_on_floor() and _was_airborne:
		landed.emit()
	_was_airborne = not is_on_floor()


func _animate(dir: float, delta: float) -> void:
	if not is_zero_approx(dir):
		_facing = 1 if dir > 0.0 else -1
	var running := is_on_floor() and absf(velocity.x) >= 12.0
	if running:
		# Advance the run cycle off ground covered rather than off time, so the
		# feet never skate when you are accelerating or shoving into a wall.
		_phase += absf(velocity.x) * delta * RUN_PHASE_PER_PX
	else:
		_phase = 0.0
	_char.facing = _facing
	_char.moving = running
	_char.airborne = not is_on_floor()
	_char.rising = velocity.y < 0.0
	_char.phase = _phase
	_char.queue_redraw()


func facing_dir() -> Vector2:
	return Vector2.RIGHT if _facing > 0 else Vector2.LEFT
