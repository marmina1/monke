class_name Hand
extends Node3D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var rest_length    : float = 0.7   ## arm length while dangling
@export var grab_length    : float = 1.6   ## max reach when extending to a vine
@export var tip_damping    : float = 0.06  ## 0 = infinitely floppy, 1 = rigid
## Absolute maximum arm extension during a grab (metres).
## The arm grows to match the actual distance to the click point, up to this.
@export var max_grab_reach : float = 5.0

# ── State ─────────────────────────────────────────────────────────────────────
var _tip_world      : Vector3 = Vector3.ZERO
var _tip_vel        : Vector3 = Vector3.ZERO
var _is_grabbing    : bool    = false
var _grab_world     : Vector3 = Vector3.ZERO
var _grab_reach     : float   = 1.6
var _initialized    : bool    = false
## World position the free arm tracks; zero = floppy pendulum physics.
var _guided_target  : Vector3 = Vector3.ZERO

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var pivot    : Node3D         = $Pivot
@onready var arm_mesh : MeshInstance3D = $Pivot/ArmMesh


func _ready() -> void:
	# Rotate the cylinder so its height-axis (local Y) aligns with Pivot's -Z.
	# After this rotation: cylinder starts at z=0 (shoulder) and extends toward -Z.
	arm_mesh.rotation_degrees.x = -90.0
	_set_arm_length(rest_length)


# ── Public API ────────────────────────────────────────────────────────────────

## Called by player when this hand grabs a vine.
func grab(grab_world_pos: Vector3) -> void:
	_is_grabbing = true
	_grab_world  = grab_world_pos
	_tip_vel     = Vector3.ZERO
	# Measure the actual distance from this hand's shoulder to the click point
	# and use that as the arm's displayed length.  Clamped to max_grab_reach so
	# the arm stays plausible even when the vine is far away.
	_grab_reach  = clampf((grab_world_pos - global_position).length(), 0.3, max_grab_reach)


## Called by player when this hand releases a vine.
func release() -> void:
	_is_grabbing    = false
	_guided_target  = Vector3.ZERO
	_reset_tip()
	_tip_vel = global_transform.basis.z * 2.5


## Point the resting arm toward a world position instead of floppy physics.
## Player calls this every process frame for free/poo-holding hands.
func guide_to(world_pos: Vector3) -> void:
	_guided_target = world_pos
	_tip_vel       = Vector3.ZERO


# ── Physics ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Defer initialisation to the first physics frame so global_position is valid.
	if not _initialized:
		_reset_tip()
		_initialized = true

	if _is_grabbing:
		_update_grab()
	else:
		_update_floppy(delta)


func _update_grab() -> void:
	# Recompute the reach every frame so the arm tracks the actual distance
	# as the player swings toward or away from the vine — no locked-in length.
	var to_grab := _grab_world - global_position
	if to_grab.length_squared() < 0.001:
		return
	_grab_reach = clampf(to_grab.length(), 0.25, max_grab_reach)
	_point_arm_at(_grab_world, _grab_reach)


func _update_floppy(delta: float) -> void:
	# When player sets a guide direction, track it instead of doing pendulum sim.
	if _guided_target.length_squared() > 0.001:
		_tip_world = _tip_world.lerp(_guided_target, minf(delta * 20.0, 1.0))
		_point_arm_at(_tip_world, rest_length)
		return

	const GRAVITY := 9.8

	# Particle gravity.
	_tip_vel.y -= GRAVITY * delta

	# Frame-rate-independent exponential damping.
	_tip_vel *= pow(1.0 - tip_damping, delta * 60.0)

	# Move the tip.
	_tip_world += _tip_vel * delta

	# Inextensible pendulum constraint: keep tip exactly rest_length away.
	var offset := _tip_world - global_position
	var dist   := offset.length()
	if dist > 0.001:
		_tip_world = global_position + offset.normalized() * rest_length
		# Cancel the radial (stretch) component of velocity so it can't escape.
		var dir   := offset.normalized()
		_tip_vel  -= dir * _tip_vel.dot(dir)

	_point_arm_at(_tip_world, rest_length)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _point_arm_at(target: Vector3, length: float) -> void:
	var to_target := target - global_position
	if to_target.length_squared() < 0.0001:
		return
	# Guard against degenerate up vector (arm pointing straight up/down).
	var up_hint := Vector3.UP
	if absf(to_target.normalized().dot(Vector3.UP)) > 0.98:
		up_hint = Vector3.FORWARD
	pivot.look_at(target, up_hint)
	_set_arm_length(length)


func _set_arm_length(length: float) -> void:
	# CylinderMesh height=1 unit. scale.y = actual length.
	# position.z = -length/2 so the arm base is at the pivot origin (shoulder)
	# and the tip is at z = -length.
	arm_mesh.scale.y    = length
	arm_mesh.position.z = -length * 0.5


func _reset_tip() -> void:
	# Tip starts directly in front of the hand in world space.
	_tip_world = global_position + global_transform.basis * Vector3(0, 0, -rest_length)
	_tip_vel   = Vector3.ZERO
