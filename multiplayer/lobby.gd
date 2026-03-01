extends Node

## Multiplayer lobby singleton (autoload "Lobby").
## Manages ENet connections, player list with names, chat, and game-start RPC.

signal connected
signal connection_failed
signal player_joined(id: int, p_name: String)
signal player_left(id: int)
signal game_starting
signal server_closed                       ## host left / connection lost
signal chat_received(sender: String, text: String)  ## new chat message

const DEFAULT_PORT : int = 7777
const MAX_PLAYERS  : int = 8

var peer : ENetMultiplayerPeer = null
var players : Dictionary = {}   # peer_id → { "name": String }


func get_local_name() -> String:
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		return gs.player_name
	return "Player"


func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


# ── Host / Join ───────────────────────────────────────────────────────────────

func host_lobby(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Lobby: create_server failed – %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_register_self()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	connected.emit()
	return OK


func join_lobby(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Lobby: create_client failed – %s" % error_string(err))
		connection_failed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func disconnect_lobby() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	players.clear()


# ── Chat ──────────────────────────────────────────────────────────────────────

func send_chat(text: String) -> void:
	var sender_name := get_local_name()
	rpc("_rpc_chat", sender_name, text)
	# Also show locally.
	chat_received.emit(sender_name, text)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_chat(sender_name: String, text: String) -> void:
	chat_received.emit(sender_name, text)


## System message (shown without a sender name prefix).
func send_system_message(text: String) -> void:
	rpc("_rpc_system_msg", text)
	chat_received.emit("", text)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_system_msg(text: String) -> void:
	chat_received.emit("", text)


# ── Game start (host only) ────────────────────────────────────────────────────

func start_game() -> void:
	if not is_host():
		return
	rpc("_rpc_start_game")
	_rpc_start_game()


@rpc("authority", "reliable", "call_remote")
func _rpc_start_game() -> void:
	game_starting.emit()


# ── Internal ──────────────────────────────────────────────────────────────────

func _register_self() -> void:
	var my_id : int = multiplayer.get_unique_id()
	var my_name : String = get_local_name()
	players[my_id] = { "name": my_name }
	player_joined.emit(my_id, my_name)


func _on_connected() -> void:
	_register_self()
	# Broadcast our name to all existing peers.
	rpc("_rpc_register_player", multiplayer.get_unique_id(), get_local_name())
	connected.emit()


func _on_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	# Host left — clean up and notify.
	disconnect_lobby()
	server_closed.emit()


func _on_peer_connected(id: int) -> void:
	# Send our info to the newly-connected peer so they learn about us.
	rpc_id(id, "_rpc_register_player", multiplayer.get_unique_id(), get_local_name())


func _on_peer_disconnected(id: int) -> void:
	var p_name : String = "Player %d" % id
	if players.has(id):
		p_name = str(players[id]["name"])
	players.erase(id)
	player_left.emit(id)
	# Broadcast leave message. Host is the only one who reliably sees
	# peer_disconnected for all peers so it broadcasts the system message.
	if is_host():
		send_system_message("%s left the game." % p_name)


@rpc("any_peer", "reliable")
func _rpc_register_player(id: int, p_name: String) -> void:
	var is_new : bool = not players.has(id)
	players[id] = { "name": p_name }
	if is_new:
		player_joined.emit(id, p_name)
