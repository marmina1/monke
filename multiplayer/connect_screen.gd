extends Control

## Connecting screen – host or join, enter player name, then go to 3D lobby room.

@onready var status_label : Label    = $VBox/StatusLabel
@onready var host_btn     : Button   = $VBox/HostBtn
@onready var join_btn     : Button   = $VBox/JoinBtn
@onready var address_edit : LineEdit = $VBox/AddressRow/AddressEdit
@onready var name_edit    : LineEdit = $VBox/NameRow/NameEdit
@onready var back_btn     : Button   = $VBox/BackBtn

@onready var lobby : Node = get_node("/root/Lobby")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	back_btn.pressed.connect(_on_back)

	lobby.connected.connect(_on_connected)
	lobby.connection_failed.connect(_on_connection_failed)

	# Pre-fill name from settings.
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		name_edit.text = gs.player_name


func _save_name() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Player"
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.player_name = n


func _on_host() -> void:
	_save_name()
	status_label.text = "Hosting..."
	host_btn.disabled = true
	join_btn.disabled = true
	var err : int = lobby.host_lobby()
	if err != OK:
		status_label.text = "Failed to host."
		host_btn.disabled = false
		join_btn.disabled = false


func _on_join() -> void:
	_save_name()
	var addr := address_edit.text.strip_edges()
	if addr == "":
		addr = "127.0.0.1"
	status_label.text = "Connecting to %s..." % addr
	host_btn.disabled = true
	join_btn.disabled = true
	var err : int = lobby.join_lobby(addr)
	if err != OK:
		status_label.text = "Failed to connect."
		host_btn.disabled = false
		join_btn.disabled = false


func _on_connected() -> void:
	status_label.text = "Connected!"
	await get_tree().create_timer(0.4).timeout
	get_tree().change_scene_to_file("res://multiplayer/LobbyRoom.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Try again."
	host_btn.disabled = false
	join_btn.disabled = false


func _on_back() -> void:
	lobby.disconnect_lobby()
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
