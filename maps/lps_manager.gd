extends Node

## Last Person Standing gamemode manager.
## Features: rounds, time limit, sudden death (floor = death, fewer bananas),
## spectator camera for dead players, podium between rounds, alive-count HUD.

# ── Config ────────────────────────────────────────────────────────────────────
var total_rounds       : int   = 3
var current_round      : int   = 0
var round_time_limit   : float = 120.0   ## seconds per round before sudden death
var _round_timer       : float = 0.0
var _deathmatch_active : bool  = false

# ── State ─────────────────────────────────────────────────────────────────────
var _alive_peers   : Array[int] = []     # peer IDs still alive this round
var _scores        : Dictionary = {}     # peer_id → cumulative points
var _round_active  : bool = false
var _all_peer_ids  : Array[int] = []     # every peer that started the match
var _death_order   : Array[int] = []     # host-only: peer IDs in order of death

# ── Spectator ─────────────────────────────────────────────────────────────────
var _spectating        : bool     = false
var _spectate_targets  : Array[Player] = []   # alive players to cycle through
var _spectate_index    : int      = 0
var _spectate_camera   : Camera3D = null
var _local_player      : Player   = null      # cached ref to local Player node

# ── Podium ────────────────────────────────────────────────────────────────────
var _podium_layer  : CanvasLayer = null
var _podium_label  : Label       = null
var _scores_label  : Label       = null


func _ready() -> void:
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		total_rounds = gs.round_count
		# Resume a multi-round match if one is active.
		if gs.lps_match_active:
			_scores = gs.lps_scores.duplicate()
			current_round = gs.lps_current_round

	# Listen for players leaving mid-game.
	if has_node("/root/Lobby"):
		Lobby.player_left.connect(_on_peer_left)
		Lobby.server_closed.connect(_on_server_closed)

	# Wait one frame so all Player nodes are spawned by main.gd.
	await get_tree().process_frame
	_cache_local_player()
	_start_round()


func _process(delta: float) -> void:
	if not _round_active:
		return

	# ── Round timer ──────────────────────────────────────────────────────
	if not _deathmatch_active:
		_round_timer -= delta
		if _round_timer <= 0.0 and Lobby.is_host():
			rpc("_rpc_start_deathmatch")
			_rpc_start_deathmatch()
		# Update HUD timer for local player.
		_update_local_hud_timer()

	# ── Spectator camera follow ──────────────────────────────────────────
	if _spectating and _spectate_camera and _spectate_targets.size() > 0:
		_spectate_index = clampi(_spectate_index, 0, _spectate_targets.size() - 1)
		var target : Player = _spectate_targets[_spectate_index]
		if is_instance_valid(target) and not target.is_dead:
			var behind := target.global_position + target.global_transform.basis.z * 3.0 + Vector3.UP * 1.5
			_spectate_camera.global_position = _spectate_camera.global_position.lerp(behind, delta * 5.0)
			_spectate_camera.look_at(target.global_position + Vector3.UP * 0.8)
		else:
			# Current target died or was freed — refresh immediately.
			_refresh_spectate_targets()
			_update_spectate_hud()

	# ── Deathmatch: floor kills ──────────────────────────────────────────
	if _deathmatch_active and Lobby.is_host():
		var players_container : Node = get_parent().get_node_or_null("Players")
		if players_container:
			for child : Node in players_container.get_children():
				if child is Player and not child.is_dead:
					if child.is_on_floor():
						var pid : int = child.get_multiplayer_authority()
						rpc("_rpc_force_kill", pid)
						_rpc_force_kill(pid)


func _input(event: InputEvent) -> void:
	if not _spectating:
		return
	if event.is_action_pressed("spectate_next"):
		_cycle_spectate(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("spectate_prev"):
		_cycle_spectate(-1)
		get_viewport().set_input_as_handled()


# ══════════════════════════════════════════════════════════════════════════════
#  ROUND LOGIC
# ══════════════════════════════════════════════════════════════════════════════

func _start_round() -> void:
	current_round += 1
	_round_active = true
	_deathmatch_active = false
	_round_timer = round_time_limit
	_alive_peers.clear()
	_all_peer_ids.clear()
	_death_order.clear()

	var players_container : Node = get_parent().get_node_or_null("Players")
	if not players_container:
		push_error("LPS: No 'Players' container found!")
		return

	for child : Node in players_container.get_children():
		if child is Player:
			var pid : int = child.get_multiplayer_authority()
			_alive_peers.append(pid)
			_all_peer_ids.append(pid)
			if not _scores.has(pid):
				_scores[pid] = 0
			# Reset the player for the new round.
			child.is_dead = false
			if child.is_local:
				child.hunger = child.max_hunger
			if not child.player_died.is_connected(_on_player_died.bind(pid)):
				child.player_died.connect(_on_player_died.bind(pid))

	# Stop spectating from previous round.
	_stop_spectating()

	# Update HUD.
	_update_local_hud_round()
	_update_local_hud_alive()

	# Flash round text.
	_show_round_banner("Round %d" % current_round)
	await get_tree().create_timer(2.5).timeout
	if is_inside_tree():
		_hide_round_banner()


func _on_player_died(peer_id : int) -> void:
	if not _round_active:
		return
	if peer_id in _alive_peers:
		_alive_peers.erase(peer_id)
	# Host tracks death order for placement scoring.
	if Lobby.is_host() and peer_id not in _death_order:
		_death_order.append(peer_id)
	_update_local_hud_alive()

	# If the local player just died, enter spectator mode.
	if _local_player and peer_id == _local_player.get_multiplayer_authority():
		_start_spectating()
	elif _spectating:
		# Someone we might be watching died — refresh targets and auto-switch.
		_refresh_spectate_targets()
		_update_spectate_hud()

	# Check for round end — only the host decides.
	if Lobby.is_host() and _alive_peers.size() <= 1:
		var winner_id : int = _alive_peers[0] if _alive_peers.size() == 1 else -1
		_award_round_points(winner_id)
		rpc("_rpc_round_over", winner_id, _scores)
		_rpc_round_over(winner_id, _scores)


func _on_peer_left(peer_id: int) -> void:
	# Treat as death for the round.
	if peer_id in _alive_peers:
		_alive_peers.erase(peer_id)
		_update_local_hud_alive()
	# Host tracks death order.
	if Lobby.is_host() and peer_id not in _death_order:
		_death_order.append(peer_id)
	# Refresh spectate targets.
	_refresh_spectate_targets()
	# Check round end.
	if _round_active and Lobby.is_host() and _alive_peers.size() <= 1:
		var winner_id : int = _alive_peers[0] if _alive_peers.size() == 1 else -1
		_award_round_points(winner_id)
		rpc("_rpc_round_over", winner_id, _scores)
		_rpc_round_over(winner_id, _scores)


func _on_server_closed() -> void:
	# Host left — lobby.gd handles the scene change via chat.gd.
	_round_active = false


# ══════════════════════════════════════════════════════════════════════════════
#  SUDDEN DEATH / DEATHMATCH
# ══════════════════════════════════════════════════════════════════════════════

@rpc("authority", "reliable", "call_remote")
func _rpc_start_deathmatch() -> void:
	_deathmatch_active = true
	# Update HUD.
	if _local_player and _local_player.hud:
		_local_player.hud.show_deathmatch_warning()
	# Reduce banana spawning.
	_reduce_bananas()


func _reduce_bananas() -> void:
	for child : Node in get_parent().get_children():
		if child is BananaSpawner:
			child.max_bananas = maxi(child.max_bananas / 3, 2)


@rpc("authority", "reliable", "call_remote")
func _rpc_force_kill(peer_id: int) -> void:
	var players_container : Node = get_parent().get_node_or_null("Players")
	if not players_container:
		return
	var node : Node = players_container.get_node_or_null("Player_%d" % peer_id)
	if node and node is Player and not node.is_dead:
		node.die()


# ══════════════════════════════════════════════════════════════════════════════
#  ROUND OVER
# ══════════════════════════════════════════════════════════════════════════════

@rpc("authority", "reliable", "call_remote")
func _rpc_round_over(winner_id : int, updated_scores : Dictionary) -> void:
	_round_active = false
	_scores = updated_scores

	_stop_spectating()

	# Check if match is over.
	if current_round >= total_rounds:
		_show_podium(true, winner_id)
		await get_tree().create_timer(6.0).timeout
		_end_match()
	else:
		_show_podium(false, winner_id)
		# Save match state so it persists across scene change.
		_save_match_state()
		await get_tree().create_timer(5.0).timeout
		_hide_podium()
		_go_to_selection()


## Host-only: compute placement points for this round.
func _award_round_points(winner_id : int) -> void:
	# Build placements: winner is 1st, then reverse death order gives 2nd, 3rd, …
	var placements : Array[int] = []
	if winner_id >= 0:
		placements.append(winner_id)
	# _death_order = [first_to_die, …, last_to_die]
	# Reverse it so the last to die (before the winner) = 2nd place.
	for i : int in range(_death_order.size() - 1, -1, -1):
		placements.append(_death_order[i])

	var points := [3, 2, 1]
	for i : int in placements.size():
		var pid : int = placements[i]
		if not _scores.has(pid):
			_scores[pid] = 0
		if i < points.size():
			_scores[pid] += points[i]


## Persist scores & round number in GameSettings so they survive scene changes.
func _save_match_state() -> void:
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.lps_scores = _scores.duplicate()
		gs.lps_current_round = current_round
		gs.lps_match_active = true


## Return to selection screen between rounds.
func _go_to_selection() -> void:
	_hide_podium()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://multiplayer/SelectionScreen.tscn")


# ══════════════════════════════════════════════════════════════════════════════
#  PODIUM
# ══════════════════════════════════════════════════════════════════════════════

func _show_podium(is_final: bool, round_winner_id: int) -> void:
	_ensure_podium_ui()

	# Build sorted leaderboard.
	var sorted_peers : Array[int] = []
	for pid : int in _scores:
		sorted_peers.append(pid)
	sorted_peers.sort_custom(func(a: int, b: int) -> bool: return _scores[a] > _scores[b])

	if is_final:
		var best_name := _peer_name(sorted_peers[0]) if sorted_peers.size() > 0 else "Nobody"
		_podium_label.text = "%s WINS THE MATCH!" % best_name
	else:
		var winner_name := _peer_name(round_winner_id) if round_winner_id >= 0 else "Draw"
		_podium_label.text = "%s wins Round %d!" % [winner_name, current_round]

	# Build scores text with medal emojis.
	var medals : Array[String] = ["1st", "2nd", "3rd"]
	var lines : String = ""
	for i : int in sorted_peers.size():
		var pid : int = sorted_peers[i]
		var prefix : String = medals[i] if i < medals.size() else "%dth" % (i + 1)
		lines += "%s  %s  —  %d pts\n" % [prefix, _peer_name(pid), _scores[pid]]
	_scores_label.text = lines

	_podium_layer.visible = true

	# Animate camera to look at the winner's player node.
	if round_winner_id >= 0:
		var players_container : Node = get_parent().get_node_or_null("Players")
		if players_container:
			var winner_node : Node = players_container.get_node_or_null("Player_%d" % round_winner_id)
			if winner_node and winner_node is Player:
				_animate_podium_camera(winner_node as Player)


func _hide_podium() -> void:
	if _podium_layer:
		_podium_layer.visible = false


func _ensure_podium_ui() -> void:
	if _podium_layer:
		return
	_podium_layer = CanvasLayer.new()
	_podium_layer.layer = 9
	_podium_layer.name = "PodiumUI"
	add_child(_podium_layer)

	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.offset_left = -280.0
	panel.offset_right = 280.0
	panel.offset_top = -160.0
	panel.offset_bottom = 160.0
	_podium_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_podium_label = Label.new()
	_podium_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_podium_label.add_theme_font_size_override("font_size", 32)
	_podium_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(_podium_label)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20.0
	vbox.add_child(spacer)

	_scores_label = Label.new()
	_scores_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scores_label.add_theme_font_size_override("font_size", 20)
	_scores_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_scores_label)


func _animate_podium_camera(winner: Player) -> void:
	# Orbit camera around the winner.
	if not _spectate_camera:
		_spectate_camera = Camera3D.new()
		_spectate_camera.name = "SpectateCamera"
		get_parent().add_child(_spectate_camera)

	_spectate_camera.current = true
	var orbit_pos := winner.global_position + Vector3(0, 2.5, 4.0)
	var tw := create_tween()
	tw.tween_property(_spectate_camera, "global_position", orbit_pos, 1.0).set_trans(Tween.TRANS_SINE)
	await tw.finished
	if is_instance_valid(_spectate_camera) and is_instance_valid(winner):
		_spectate_camera.look_at(winner.global_position + Vector3.UP * 0.8)


# ══════════════════════════════════════════════════════════════════════════════
#  SPECTATOR SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

func _start_spectating() -> void:
	if _spectating:
		return
	_spectating = true
	_refresh_spectate_targets()

	if _spectate_targets.is_empty():
		return

	# Create spectator camera if needed.
	if not _spectate_camera:
		_spectate_camera = Camera3D.new()
		_spectate_camera.name = "SpectateCamera"
		get_parent().add_child(_spectate_camera)

	_spectate_index = 0
	_spectate_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Show spectating HUD.
	_update_spectate_hud()


func _stop_spectating() -> void:
	if not _spectating:
		return
	_spectating = false
	_spectate_targets.clear()

	if _spectate_camera:
		_spectate_camera.queue_free()
		_spectate_camera = null

	# Restore local camera.
	if _local_player and is_instance_valid(_local_player) and not _local_player.is_dead:
		_local_player.camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Hide spectate bar on HUD.
	if _local_player and _local_player.hud:
		_local_player.hud.hide_spectating()


func _cycle_spectate(direction: int) -> void:
	_refresh_spectate_targets()
	if _spectate_targets.is_empty():
		return
	_spectate_index = (_spectate_index + direction) % _spectate_targets.size()
	if _spectate_index < 0:
		_spectate_index = _spectate_targets.size() - 1
	_update_spectate_hud()


func _refresh_spectate_targets() -> void:
	_spectate_targets.clear()
	var players_container : Node = get_parent().get_node_or_null("Players")
	if not players_container:
		return
	for child : Node in players_container.get_children():
		if child is Player and not child.is_dead and not child.is_local:
			_spectate_targets.append(child as Player)
	# Clamp index.
	if _spectate_targets.size() > 0:
		_spectate_index = clampi(_spectate_index, 0, _spectate_targets.size() - 1)


func _update_spectate_hud() -> void:
	if not _local_player or not _local_player.hud:
		return
	if _spectate_targets.is_empty():
		_local_player.hud.show_spectating("No one")
		return
	_spectate_index = clampi(_spectate_index, 0, _spectate_targets.size() - 1)
	var target : Player = _spectate_targets[_spectate_index]
	var pid : int = target.get_multiplayer_authority()
	_local_player.hud.show_spectating(_peer_name(pid))


# ══════════════════════════════════════════════════════════════════════════════
#  RESPAWN / END
# ══════════════════════════════════════════════════════════════════════════════

func _respawn_all() -> void:
	var players_container : Node = get_parent().get_node_or_null("Players")
	if not players_container:
		return
	var spawn_pt : Marker3D = get_parent().get_node("SpawnPoint") as Marker3D
	var idx : int = 0
	for child : Node in players_container.get_children():
		if child is Player:
			child.is_dead = false
			if child.has_node("PuppetBody"):
				child.get_node("PuppetBody").visible = not child.is_local
			child.velocity = Vector3.ZERO
			var offset := Vector3(idx * 3.0, 0.0, 0.0)
			child.global_position = spawn_pt.global_position + offset
			if child.is_local:
				child.hunger = child.max_hunger
				child.is_starving = false
				if child.hunger_death_timer and not child.hunger_death_timer.is_queued_for_deletion():
					child.hunger_death_timer.stop()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				# Re-enable camera.
				child.camera.make_current()
				# Hide death label.
				if child.hud:
					child.hud.death_label.visible = false
			idx += 1

	# Reset banana spawner counts.
	for child : Node in get_parent().get_children():
		if child is BananaSpawner:
			child.max_bananas = 20  # original value


func _end_match() -> void:
	_hide_podium()
	# Clear persisted LPS state.
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.lps_clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Lobby.is_host():
		Lobby.disconnect_lobby()
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")


# ══════════════════════════════════════════════════════════════════════════════
#  HUD HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _cache_local_player() -> void:
	var players_container : Node = get_parent().get_node_or_null("Players")
	if not players_container:
		return
	for child : Node in players_container.get_children():
		if child is Player and child.is_local:
			_local_player = child as Player
			return


func _update_local_hud_round() -> void:
	if _local_player and _local_player.hud:
		_local_player.hud.update_round_info(current_round, total_rounds)


func _update_local_hud_alive() -> void:
	if _local_player and _local_player.hud:
		_local_player.hud.update_alive_count(_alive_peers.size())


func _update_local_hud_timer() -> void:
	if _local_player and _local_player.hud:
		_local_player.hud.update_game_timer(_round_timer)


func _show_round_banner(text: String) -> void:
	_ensure_podium_ui()
	_podium_label.text = text
	_scores_label.text = ""
	_podium_layer.visible = true


func _hide_round_banner() -> void:
	if _podium_layer:
		_podium_layer.visible = false


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _peer_name(peer_id : int) -> String:
	if Lobby.players.has(peer_id):
		return str(Lobby.players[peer_id]["name"])
	return "Player %d" % peer_id
