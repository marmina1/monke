extends Node3D

## Assign res://scenes/Player.tscn in the Inspector.
@export var player_scene : PackedScene
## Assign res://scenes/Banana.tscn in the Inspector.
@export var banana_scene : PackedScene
## How many bananas to scatter near the vines at game start.
@export var banana_count : int = 20

@onready var spawn_point : Marker3D = $SpawnPoint


func _ready() -> void:
	_spawn_player()
	_spawn_bananas()


func _spawn_player() -> void:
	if player_scene == null:
		push_error("Main: 'player_scene' export is not assigned.")
		return
	var player : Node = player_scene.instantiate()
	add_child(player)
	player.global_position = spawn_point.global_position
	player.player_died.connect(_on_player_died)


func _spawn_bananas() -> void:
	if banana_scene == null:
		push_warning("Main: 'banana_scene' not assigned, skipping banana spawn.")
		return
	var vine_list := $Vines.get_children()
	if vine_list.is_empty():
		push_warning("Main: No vines under $Vines – skipping banana spawn.")
		return

	# All bananas live in a flat container at world origin so their local
	# position equals their world position — no vine-relative offset confusion.
	var container := Node3D.new()
	container.name = "Bananas"
	add_child(container)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Cache vine world positions to use as scatter anchors.
	var vine_pos : Array[Vector3] = []
	for v in vine_list:
		vine_pos.append(v.global_position)

	for _i in banana_count:
		var banana : Node = banana_scene.instantiate()

		# Pick two random vine positions and lerp between them, then add an
		# independent jitter so bananas scatter across the whole vine field
		# without predictably clustering on any single vine.
		var va := vine_pos[rng.randi() % vine_pos.size()]
		var vb := vine_pos[rng.randi() % vine_pos.size()]
		var bx := lerpf(va.x, vb.x, rng.randf()) + rng.randf_range(-2.8, 2.8)
		var bz := lerpf(va.z, vb.z, rng.randf()) + rng.randf_range(-2.8, 2.8)

		# Height: vines are rooted at y≈11.5, GrabPoint 3 m above → top ≈14.5.
		# Chain hangs 6 m → bottom ≈8.5.  Spawn upper 60 %: world y 11 – 14.
		# Also sprinkle a few lower ones (y 9–11) for variety.
		var by : float
		if rng.randf() < 0.25:
			by = rng.randf_range(9.0, 11.0)   # occasional mid-height banana
		else:
			by = rng.randf_range(11.5, 14.2)  # high cluster near vine tops

		# MUST set position BEFORE add_child — Banana._ready() reads
		# position.y to initialise the hover-bob baseline (_base_y).
		# Container is at world origin, so local == world here.
		banana.position = Vector3(bx, by, bz)
		container.add_child(banana)


func _on_player_died() -> void:
	print("Game Over!")
	# TODO: show restart UI, handle multiplayer lobby, etc.
