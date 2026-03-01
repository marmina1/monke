extends Node3D

@onready var water_zone : Area3D = $WaterZone
@onready var crocs      : Node3D = $Crocodiles


func _ready() -> void:
	water_zone.body_entered.connect(_on_body_entered)
	water_zone.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	# Only the nearest crocodile reacts – they don't all pile on at once.
	var croc := _nearest_croc(body.global_position)
	if croc:
		croc.alert(body as Player)


func _on_body_exited(body: Node3D) -> void:
	if not body is Player:
		return
	# Any croc that was chasing THIS player goes back to wandering.
	for child in crocs.get_children():
		var croc := child as Crocodile
		if croc and croc._player == body:
			croc.dismiss()


func _nearest_croc(from: Vector3) -> Crocodile:
	var best   : Crocodile = null
	var best_d : float     = INF
	for child in crocs.get_children():
		var croc := child as Crocodile
		if not croc:
			continue
		var d := from.distance_squared_to(croc.global_position)
		if d < best_d:
			best_d = d
			best   = croc
	return best
