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
signal alert_received(text: String)                  ## red kick/ban notices

const DEFAULT_PORT : int = 7777
const MAX_PLAYERS  : int = 8

var peer       : ENetMultiplayerPeer = null
var players    : Dictionary = {}   # peer_id → { "name": String }
var banned_ids : Array[int] = []   # peer IDs barred from reconnecting


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


# ── Kick / Ban ────────────────────────────────────────────────────────────────

## Kick a player: notify them then drop the connection.
func kick_player(pid: int) -> void:
	if not is_host() or not peer:
		return
	rpc_id(pid, "_rpc_notify_kicked", false)
	await get_tree().create_timer(0.3).timeout
	# Guard against the peer having already disconnected naturally.
	if peer and players.has(pid):
		peer.disconnect_peer(pid)

## Ban a player: add to blacklist, notify them, then drop the connection.
func ban_player(pid: int) -> void:
	if not is_host() or not peer:
		return
	if pid not in banned_ids:
		banned_ids.append(pid)
	rpc_id(pid, "_rpc_notify_kicked", true)
	await get_tree().create_timer(0.3).timeout
	if peer and players.has(pid):
		peer.disconnect_peer(pid)

## Received by the target client only: set message and return to menu.
@rpc("authority", "reliable")
func _rpc_notify_kicked(is_ban: bool) -> void:
	var msg := "You have been banned from this server." if is_ban else "You have been kicked from the game."
	if has_node("/root/GameSettings"):
		get_node("/root/GameSettings").disconnect_message = msg
	disconnect_lobby()
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")


# ── Alert messages (red, host-broadcast) ─────────────────────────────────────

func send_alert(text: String) -> void:
	rpc("_rpc_alert", text)
	alert_received.emit(text)

@rpc("authority", "reliable", "call_remote")
func _rpc_alert(text: String) -> void:
	alert_received.emit(text)


# ── Chat ──────────────────────────────────────────────────────────────────────

func send_chat(text: String) -> void:
	# Use display_name so the deduplicated name (e.g. "Player2") is shown,
	# not the raw stored name.
	var sender_name := display_name(multiplayer.get_unique_id())
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
	var my_name : String = _unique_name_for(my_id, get_local_name())
	players[my_id] = { "name": my_name }
	player_joined.emit(my_id, my_name)


## Returns a unique name for [param id] based on [param base], appending 2/3/… if taken.
func _unique_name_for(id: int, base: String) -> String:
	var candidate : String = base
	var suffix : int = 2
	while true:
		var taken : bool = false
		for existing_id : int in players:
			if existing_id != id and players[existing_id]["name"] == candidate:
				taken = true
				break
		if not taken:
			return candidate
		candidate = "%s%d" % [base, suffix]
		suffix += 1
	return candidate


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
	# Reject banned peers immediately.
	if id in banned_ids:
		rpc_id(id, "_rpc_notify_kicked", true)
		await get_tree().create_timer(0.2).timeout
		if peer:
			peer.disconnect_peer(id)
		return
	# Send our info to the newly-connected peer so they learn about us.
	rpc_id(id, "_rpc_register_player", multiplayer.get_unique_id(), get_local_name())


func _on_peer_disconnected(id: int) -> void:
	# Compute display name BEFORE erasing so deduplication still works.
	var p_name : String = display_name(id)
	players.erase(id)
	player_left.emit(id)
	# Host broadcasts the leave message.
	if is_host():
		send_system_message("%s left the game." % p_name)


## Returns the stored (already-deduplicated) name for a peer.
func display_name(pid: int) -> String:
	if not players.has(pid):
		return "Player %d" % pid
	return str(players[pid]["name"])


@rpc("any_peer", "reliable")
func _rpc_register_player(id: int, p_name: String) -> void:
	var is_new : bool = not players.has(id)
	var unique_name : String = _unique_name_for(id, p_name)
	players[id] = { "name": unique_name }
	if is_new:
		player_joined.emit(id, unique_name)
	# If the host had to rename this player, tell them their actual name.
	if is_host() and unique_name != p_name:
		rpc_id(id, "_rpc_set_your_name", unique_name)


## Called on the client when the host assigned them a different name due to a duplicate.
@rpc("authority", "reliable")
func _rpc_set_your_name(assigned_name: String) -> void:
	var my_id : int = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["name"] = assigned_name
