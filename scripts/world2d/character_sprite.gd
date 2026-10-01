class_name CharacterSprite
extends Node2D
## A smooth, vector-drawn operator avatar — no pixel art, so it stays crisp at
## any zoom. A stylized "netrunner": dark jacket with neon trim, glowing visor,
## animated run cycle.
##
## Drawn side-on for the platforming worlds, so there are two facings rather
## than four, plus poses for rising and falling. The origin sits at the
## character's FEET, matching Player2D's collider, which is what lets the world
## place it on a tile top with a plain `y = row * TILE`.
##
## Set `facing`, `moving`, `airborne` / `rising` and advance `phase` each frame,
## then call queue_redraw().

var facing := 1           # 1 right, -1 left
var moving := false
var airborne := false
var rising := false       # only meaningful while airborne
var phase := 0.0          # run cycle, radians

# Neon-operator palette (kept in sync with the UI accent).
const SUIT := Color("1b2150")
const SUIT_HI := Color("2a3270")
const SUIT_LO := Color("12153a")
const SKIN := Color("e7b187")
const SKIN_LO := Color("c98f67")
const HAIR := Color("191c38")
const BOOT := Color("0d1030")
const SHADOW := Color(0, 0, 0, 0.26)
const INK := Color("05030f")
var ACCENT := Color("00e5ff")
var ACCENT_SOFT := Color("00e5ff")

## Everything below is authored around a figure standing at the origin, so the
## whole drawing is shifted up by this much to put the feet on y = 0.
const FOOT_OFFSET := -21.0


func _ready() -> void:
	ACCENT = UiTheme.ACCENT
	ACCENT_SOFT = Color(UiTheme.ACCENT, 0.33)


func _draw() -> void:
	var stride: float = sin(phase) if (moving and not airborne) else 0.0
	var swing: float = stride * 3.6
	var bob: float = (-1.5 if (moving and not airborne and sin(phase) > 0.0) else 0.0)
	# Ground shadow: it stays put while the body bobs above it, and shrinks away
	# as you leave the ground, which is most of what sells a jump.
	if not airborne:
		_ellipse(Vector2(0, 21.0 + FOOT_OFFSET), 12.5, 4.2, SHADOW)
	draw_set_transform(Vector2(0, bob + FOOT_OFFSET), 0.0, Vector2.ONE)
	if airborne:
		_draw_air(facing, rising)
	else:
		_draw_side(facing, swing)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- poses ------------------------------------------------------------------

## Running or standing: a 3/4 profile with one arm leading, one trailing.
func _draw_side(side: int, swing: float) -> void:
	_leg(Vector2(-1.5, 11), swing, true)
	_leg(Vector2(3.0 * side, 11), -swing, true)
	_torso()
	_arm(Vector2(-2.0 * side, 1), swing)          # trailing arm (behind torso)
	_head(float(side))
	_arm(Vector2(9.0 * side, 1), -swing)          # leading arm (in front)


## In the air: legs tucked on the way up, reaching on the way down, with the
## arms counter-posed so the two read apart at a glance.
func _draw_air(side: int, up: bool) -> void:
	if up:
		_leg(Vector2(-1.5, 9), -3.5, true)
		_leg(Vector2(3.0 * side, 9), -5.5, true)
		_torso()
		_arm(Vector2(-2.0 * side, 0), -5.0)
		_head(float(side))
		_arm(Vector2(9.0 * side, -1), -6.0)       # leading arm thrown up
	else:
		_leg(Vector2(-2.5, 12), 4.5, true)
		_leg(Vector2(3.5 * side, 12), 2.0, true)
		_torso()
		_arm(Vector2(-2.0 * side, 1), 4.0)
		_head(float(side))
		_arm(Vector2(9.0 * side, 2), 5.5)         # arms out, catching balance


# --- parts ------------------------------------------------------------------

func _torso() -> void:
	# Jacket: a tapered capsule, darker at the bottom, with a neon seam.
	var pts := PackedVector2Array([
		Vector2(-8.5, -4), Vector2(8.5, -4), Vector2(7, 11), Vector2(-7, 11)])
	draw_colored_polygon(pts, SUIT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7.2, 4), Vector2(7.2, 4), Vector2(7, 11), Vector2(-7, 11)]), SUIT_LO)
	# shoulders
	draw_circle(Vector2(-8, -3.5), 3.6, SUIT_HI)
	draw_circle(Vector2(8, -3.5), 3.6, SUIT_HI)
	# neon seam + collar
	draw_line(Vector2(0, -3), Vector2(0, 10), Color(ACCENT, 0.9), 1.5, true)
	draw_line(Vector2(-6, -3.2), Vector2(6, -3.2), Color(ACCENT, 0.8), 1.6, true)
	# a soft rim glow down one side
	draw_line(Vector2(8, -3), Vector2(6.6, 10.5), ACCENT_SOFT, 2.2, true)


func _head(side: float) -> void:
	var cx := 2.6 * side
	var c := Vector2(cx, -13.0)
	# neck
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 3, -6.5), Vector2(cx + 3, -6.5), Vector2(cx + 2.4, -3.2), Vector2(cx - 2.4, -3.2)]), SKIN_LO)
	draw_circle(c, 8.4, SKIN)
	# hair cap
	_arc_cap(c, 8.4, HAIR)
	# profile visor on the facing side
	var dirx := 1.0 if side >= 0.0 else -1.0
	draw_line(c + Vector2(1.5 * dirx, 1.0), c + Vector2(6.6 * dirx, 1.0), ACCENT_SOFT, 5.0, true)
	draw_line(c + Vector2(1.8 * dirx, 1.0), c + Vector2(6.2 * dirx, 1.0), ACCENT, 2.6, true)


func _arm(at: Vector2, swing: float) -> void:
	var top := at + Vector2(0, -2)
	var hand := at + Vector2(swing * 0.6, 7.5)
	_capsule(top, hand, 2.8, SUIT)
	draw_circle(hand, 2.3, SKIN)


func _leg(at: Vector2, swing: float, _boot: bool) -> void:
	var hip := at + Vector2(0, -2)
	var foot := at + Vector2(swing, 7.5)
	_capsule(hip, foot, 3.1, SUIT_LO)
	draw_circle(foot + Vector2(0, 0.5), 3.0, BOOT)


# --- primitives -------------------------------------------------------------

func _capsule(a: Vector2, b: Vector2, r: float, color: Color) -> void:
	draw_line(a, b, color, r * 2.0, true)
	draw_circle(a, r, color)
	draw_circle(b, r, color)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 22:
		var a := TAU * i / 22.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


## The top hair cap: the upper ~55% of the head circle.
func _arc_cap(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var a0 := PI * 1.08
	var a1 := TAU + PI * -0.08
	var steps := 16
	for i in range(steps + 1):
		var a: float = a0 + (a1 - a0) * i / steps
		pts.append(c + Vector2(cos(a) * r, sin(a) * r))
	draw_colored_polygon(pts, color)
