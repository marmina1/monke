class_name Poo
extends RigidBody3D

# ── Inspector tweaks ──────────────────────────────────────────────────────────
## Seconds before the poo auto-destroys if it doesn't hit anything.
@export var lifetime      : float = 5.0
## Hunger removed from any player struck by this poo.
@export var hunger_damage : float = 15.0

var _thrower : Player = null


func _ready() -> void:
	# Stays frozen in the thrower's hand until throw() is called.
	freeze = true
	$HitZone.body_entered.connect(_on_body_entered)


## Register the throwing player so they don't hit themselves,
## and exclude them from the RigidBody physics collision too.
func setup(owner_player: Player) -> void:
	_thrower = owner_player
	add_collision_exception_with(owner_player)


## Unfreeze and launch the poo.  Called by the player on the second Space press.
func throw(direction: Vector3, force: float) -> void:
	freeze = false
	linear_velocity = direction * force
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _on_body_entered(body: Node3D) -> void:
	# Never hit the person who threw it.
	if body == _thrower:
		return
	if body is Player:
		# Drain the victim's hunger (blind/slow mechanic later).
		body.add_hunger(-hunger_damage)
	queue_free()
