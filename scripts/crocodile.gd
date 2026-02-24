class_name Crocodile
extends Node3D

# ── Inspector tweaks ──────────────────────────────────────────────────────────
@export var wander_speed  : float = 2.5   ## m/s while roaming
@export var chase_speed   : float = 7.0   ## m/s when hunting the player
@export var wander_radius : float = 11.0  ## max distance from current pos for next wander point
@export var water_y       : float = 0.4   ## Y the croc stays locked to (water surface height)

# ── State machine ─────────────────────────────────────────────────────────────
enum State { WANDER, CHASE }
var _state        : State   = State.WANDER
var _target       : Vector3 = Vector3.ZERO
var _player       : Player  = null
var _wander_timer : float   = 0.0
var _rng          := RandomNumberGenerator.new()

@onready var bite_zone : Area3D = $BiteZone


func _ready() -> void:
	_rng.randomize()
	position.y = water_y
	_pick_wander_target()
	bite_zone.body_entered.connect(_on_bite)


# ── Public API (called by swamp.gd) ──────────────────────────────────────────

## Swamp detected the player entering water – turn and charge.
func alert(player: Player) -> void:
	_player = player
	_state  = State.CHASE


## Player left the water (or is dead) – go back to wandering.
func dismiss() -> void:
	_player = null
	_state  = State.WANDER
	_pick_wander_target()


# ── Per-frame update ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	match _state:
		State.WANDER: _do_wander(delta)
		State.CHASE:  _do_chase(delta)


func _do_wander(delta: float) -> void:
	_wander_timer -= delta
	var d := Vector2(position.x - _target.x, position.z - _target.z).length()
	if d < 0.8 or _wander_timer <= 0.0:
		_pick_wander_target()
	_step_toward(_target, wander_speed, delta)


func _do_chase(delta: float) -> void:
	if _player == null or _player.is_dead:
		dismiss()
		return
	var tgt   := _player.global_position
	tgt.y      = water_y
	_step_toward(tgt, chase_speed, delta)


func _step_toward(target: Vector3, speed: float, delta: float) -> void:
	var dir := target - position
	dir.y    = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	# Smoothly rotate the croc to face its movement direction.
	basis    = basis.slerp(Basis.looking_at(dir, Vector3.UP), delta * 7.0)
	position += dir * speed * delta
	position.y = water_y


func _pick_wander_target() -> void:
	var angle  := _rng.randf() * TAU
	var radius := _rng.randf_range(3.0, wander_radius)
	# Clamp within the swamp bounds so crocs don't wander off into the trees.
	_target = Vector3(
		clampf(position.x + cos(angle) * radius, -11.0, 11.0),
		water_y,
		clampf(position.z + sin(angle) * radius, -11.0, 11.0)
	)
	_wander_timer = _rng.randf_range(3.0, 7.0)


# ── Bite ──────────────────────────────────────────────────────────────────────

func _on_bite(body: Node3D) -> void:
	if body is Player and not body.is_dead:
		body.die()
