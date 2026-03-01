extends Node3D

## Multiplayer voting selection screen.
## Three stations around the camera — players vote, majority wins, ties broken randomly.
##   • Front  (−Z) : Gamemode
##   • Left   (−X) : Map
##   • Back   (+Z) : Buff

# ── Data ──────────────────────────────────────────────────────────────────────
const ALL_GAMEMODES : Array[String] = [
	"Tag", "Last Person Standing", "King of the Hill", "Race"
]

const ALL_MAPS : Dictionary = {
	"Swamp Forest":  "res://maps/SwampForest.tscn",
	"Rainforest":    "res://maps/Rainforest.tscn",
	"Red Canyon":    "res://maps/RedCanyon.tscn",
	"Moon Forest":   "res://maps/MoonForest.tscn",
}

const ALL_BUFFS : Array[String] = [
	"Banana Frenzy", "Golden Banana", "Iron Stomach",
	"Monkey Speed", "Vine Master", "Poo Power",
]

# ── State ─────────────────────────────────────────────────────────────────────
enum Phase { INTRO, GAMEMODE, MAP, BUFF, LAUNCHING }
var current_phase  : int   = Phase.INTRO
var _phase_timer   : float = 10.0
var _can_select    : bool  = false
var _phase_decided : bool  = false
var _my_vote       : int   = -1   # card index this player voted for (-1 = none)

var offered_gamemodes : Array[String] = []
var offered_maps      : Array[String] = []
var offered_buffs     : Array[String] = []

var chosen_gamemode : String = ""
var chosen_map_path : String = ""
var chosen_buff     : String = ""

# Current-phase votes: peer_id (int) → card_idx (int)
var _current_votes : Dictionary = {}

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var camera       : Camera3D        = $CameraPivot/Camera3D
@onready var cam_pivot    : Node3D          = $CameraPivot
@onready var anim_player  : AnimationPlayer = $AnimationPlayer

@onready var gm_cards  : Array[Node3D] = [$Stations/GamemodeStation/Card1,
										   $Stations/GamemodeStation/Card2,
										   $Stations/GamemodeStation/Card3]
@onready var map_cards : Array[Node3D] = [$Stations/MapStation/Card1,
										   $Stations/MapStation/Card2,
										   $Stations/MapStation/Card3]
@onready var buff_cards : Array[Node3D] = [$Stations/BuffStation/Card1,
											$Stations/BuffStation/Card2,
											$Stations/BuffStation/Card3]

# UI
@onready var title_label   : Label     = $UILayer/TopBar/TitleLabel
@onready var timer_label   : Label     = $UILayer/TopBar/TimerLabel
@onready var gm_preview    : Label     = $UILayer/PreviewBar/GMPreview
@onready var map_preview   : Label     = $UILayer/PreviewBar/MapPreview
@onready var buff_preview  : Label     = $UILayer/PreviewBar/BuffPreview
@onready var blackout      : ColorRect = $UILayer/Blackout


# ══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_card_displays()

	blackout.modulate.a = 0.0
	gm_preview.text   = "Gamemode: ---"
	map_preview.text  = "Map: ---"
	buff_preview.text = "Buff: ---"

	for card : Node3D in gm_cards + map_cards + buff_cards:
		var area : Area3D = card.get_node("Area3D")
		area.input_event.connect(_on_card_input.bind(card))

	anim_player.animation_finished.connect(_on_anim_finished)

	# Chat overlay.
	var chat_scene := load("res://ui/Chat.tscn")
	if chat_scene:
		add_child(chat_scene.instantiate())

	# Host-disconnect.
	Lobby.server_closed.connect(_on_server_closed)

	if Lobby.is_host():
		_randomise_offerings()
		_apply_labels()
		title_label.text = "STARTING SOON..."
		# Brief wait so all clients have time to load the scene.
		await get_tree().create_timer(1.0).timeout
		rpc("_rpc_sync_offerings", offered_gamemodes, offered_maps, offered_buffs)
		_start_intro()
	else:
		title_label.text = "WAITING FOR HOST..."


func _process(delta : float) -> void:
	if current_phase == Phase.INTRO or current_phase == Phase.LAUNCHING:
		return
	if not _can_select or _phase_decided:
		return
	_phase_timer -= delta
	timer_label.text = "%d" % maxi(ceili(_phase_timer), 0)
	if _phase_timer <= 0.0 and Lobby.is_host():
		_finalize_current_phase()


# ══════════════════════════════════════════════════════════════════════════════
#  SETUP HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _setup_card_displays() -> void:
	for card : Node3D in gm_cards + map_cards + buff_cards:
		# Hide the old Label3D from the .tscn.
		var old_label : Label3D = card.get_node("Label3D")
		old_label.visible = false

		# ── SubViewport for text rendering ─────────────────────────
		var vp := SubViewport.new()
		vp.name = "CardVP"
		vp.size = Vector2i(256, 360)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

		var title_lbl := Label.new()
		title_lbl.name = "Title"
		title_lbl.size = Vector2(256, 200)
		title_lbl.position = Vector2(0, 20)
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_lbl.add_theme_font_size_override("font_size", 38)
		title_lbl.add_theme_color_override("font_color", Color.WHITE)
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vp.add_child(title_lbl)

		var vote_lbl := Label.new()
		vote_lbl.name = "Votes"
		vote_lbl.size = Vector2(256, 140)
		vote_lbl.position = Vector2(0, 220)
		vote_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vote_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vote_lbl.add_theme_font_size_override("font_size", 22)
		vote_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.7))
		vote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vp.add_child(vote_lbl)

		card.add_child(vp)

		# ── Sprite3D billboard overlay ─────────────────────────────
		var sprite := Sprite3D.new()
		sprite.name = "CardSprite"
		sprite.texture = vp.get_texture()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.render_priority = 1
		sprite.double_sided = true
		sprite.pixel_size = 0.008  # 256 * 0.008 ≈ 2.0m, 360 * 0.008 ≈ 2.88m
		card.add_child(sprite)


func _randomise_offerings() -> void:
	var gm_pool := ALL_GAMEMODES.duplicate()
	gm_pool.shuffle()
	offered_gamemodes = [gm_pool[0], gm_pool[1], gm_pool[2]]

	var map_names : Array[String] = []
	for k : String in ALL_MAPS.keys():
		map_names.append(k)
	map_names.shuffle()
	offered_maps = [map_names[0], map_names[1], map_names[2]]

	var buff_pool := ALL_BUFFS.duplicate()
	buff_pool.shuffle()
	offered_buffs = [buff_pool[0], buff_pool[1], buff_pool[2]]


func _apply_labels() -> void:
	for i : int in 3:
		_set_card_text(gm_cards[i],   offered_gamemodes[i])
		_set_card_text(map_cards[i],  offered_maps[i])
		_set_card_text(buff_cards[i], offered_buffs[i])


func _set_card_text(card : Node3D, text : String) -> void:
	var vp : SubViewport = card.get_node("CardVP")
	var title : Label = vp.get_node("Title")
	title.text = text


func _start_intro() -> void:
	current_phase = Phase.INTRO
	title_label.text = "CHOOSE GAMEMODE"
	_can_select = false
	anim_player.play("intro_to_gamemode")


func _cards_for(phase : int) -> Array[Node3D]:
	match phase:
		Phase.GAMEMODE: return gm_cards
		Phase.MAP:      return map_cards
		Phase.BUFF:     return buff_cards
	return gm_cards


# ══════════════════════════════════════════════════════════════════════════════
#  RPC – SYNC OFFERINGS  (host → clients)
# ══════════════════════════════════════════════════════════════════════════════

@rpc("authority", "reliable", "call_remote")
func _rpc_sync_offerings(gamemodes : Array, maps : Array, buffs : Array) -> void:
	offered_gamemodes.clear()
	offered_maps.clear()
	offered_buffs.clear()
	for g in gamemodes:
		offered_gamemodes.append(str(g))
	for m in maps:
		offered_maps.append(str(m))
	for b in buffs:
		offered_buffs.append(str(b))
	_apply_labels()
	_start_intro()


# ══════════════════════════════════════════════════════════════════════════════
#  ANIMATION CALLBACK
# ══════════════════════════════════════════════════════════════════════════════

func _on_anim_finished(anim_name : StringName) -> void:
	match anim_name:
		&"intro_to_gamemode":
			current_phase = Phase.GAMEMODE
			_begin_voting_phase()
		&"pivot_to_map":
			current_phase = Phase.MAP
			_begin_voting_phase()
		&"pivot_to_buff":
			current_phase = Phase.BUFF
			_begin_voting_phase()


func _begin_voting_phase() -> void:
	_can_select = true
	_phase_decided = false
	_my_vote = -1
	_current_votes.clear()
	_phase_timer = 10.0
	_reset_cards(_cards_for(current_phase))
	_update_vote_displays()


# ══════════════════════════════════════════════════════════════════════════════
#  CARD CLICK
# ══════════════════════════════════════════════════════════════════════════════

func _on_card_input(_cam : Node, event : InputEvent, _pos : Vector3,
					_normal : Vector3, _idx : int, card : Node3D) -> void:
	if not _can_select or _phase_decided:
		return
	if not event is InputEventMouseButton:
		return
	var mb : InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var cards : Array[Node3D] = _cards_for(current_phase)
	if card not in cards:
		return

	var idx : int = cards.find(card)
	if idx == _my_vote:
		return  # already voted for this card

	_my_vote = idx
	_show_my_selection(cards, idx)

	if Lobby.is_host():
		_handle_vote(multiplayer.get_unique_id(), idx)
	else:
		rpc_id(1, "_rpc_submit_vote", current_phase, idx)


# ══════════════════════════════════════════════════════════════════════════════
#  VISUAL HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _show_my_selection(cards : Array[Node3D], idx : int) -> void:
	for i : int in cards.size():
		var target : Vector3 = Vector3(1.12, 1.12, 1.12) if i == idx else Vector3.ONE
		var tw := create_tween()
		tw.tween_property(cards[i], "scale", target, 0.15)


func _reset_cards(cards : Array[Node3D]) -> void:
	for card : Node3D in cards:
		card.scale = Vector3.ONE
		var mesh : MeshInstance3D = card.get_node("MeshInstance3D")
		mesh.transparency = 0.0
		var vp : SubViewport = card.get_node("CardVP")
		var vote_lbl : Label = vp.get_node("Votes")
		vote_lbl.text = ""


# ══════════════════════════════════════════════════════════════════════════════
#  RPC – VOTING
# ══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func _rpc_submit_vote(phase : int, card_idx : int) -> void:
	if not Lobby.is_host():
		return
	if phase != current_phase or _phase_decided:
		return
	var sender : int = multiplayer.get_remote_sender_id()
	_handle_vote(sender, card_idx)


func _handle_vote(peer_id : int, card_idx : int) -> void:
	if _phase_decided:
		return
	_current_votes[peer_id] = card_idx
	# Broadcast updated vote map to all clients; host updates locally.
	var synced : Dictionary = _current_votes.duplicate()
	rpc("_rpc_broadcast_votes", current_phase, synced)
	_update_vote_displays()
	# If everyone has voted, finalize immediately.
	if _current_votes.size() >= Lobby.players.size():
		_finalize_current_phase()


@rpc("authority", "reliable", "call_remote")
func _rpc_broadcast_votes(phase : int, vote_dict : Dictionary) -> void:
	if phase != current_phase or _phase_decided:
		return
	_current_votes = vote_dict
	_update_vote_displays()


func _update_vote_displays() -> void:
	var cards : Array[Node3D] = _cards_for(current_phase)
	# Build per-card voter name lists.
	var names_per_card : Array = [[], [], []]
	for key in _current_votes:
		var peer_id : int = int(key)
		var idx : int = int(_current_votes[key])
		if idx < 0 or idx > 2:
			continue
		var p_name : String = "Player"
		if Lobby.players.has(peer_id):
			p_name = str(Lobby.players[peer_id]["name"])
		names_per_card[idx].append(p_name)

	for i : int in 3:
		var vp : SubViewport = cards[i].get_node("CardVP")
		var vote_lbl : Label = vp.get_node("Votes")
		var voters : Array = names_per_card[i]
		var count : int = voters.size()
		if count == 0:
			vote_lbl.text = ""
		else:
			var joined : String = ""
			for vi : int in voters.size():
				if vi > 0:
					joined += ", "
				joined += str(voters[vi])
			var suffix : String = "" if count == 1 else "s"
			vote_lbl.text = "%d vote%s\n%s" % [count, suffix, joined]


# ══════════════════════════════════════════════════════════════════════════════
#  PHASE FINALIZATION  (host only)
# ══════════════════════════════════════════════════════════════════════════════

func _finalize_current_phase() -> void:
	if _phase_decided:
		return
	_phase_decided = true
	_can_select = false

	# Tally votes per card.
	var tallies : Array[int] = [0, 0, 0]
	for key in _current_votes:
		var idx : int = int(_current_votes[key])
		if idx >= 0 and idx <= 2:
			tallies[idx] += 1

	# Determine winner — highest votes, random tie-break.
	var max_votes : int = 0
	for t : int in tallies:
		if t > max_votes:
			max_votes = t

	var winner : int = 0
	if max_votes == 0:
		winner = randi() % 3
	else:
		var tied : Array[int] = []
		for i : int in 3:
			if tallies[i] == max_votes:
				tied.append(i)
		winner = tied[randi() % tied.size()]

	# Broadcast result to all clients; apply locally on host.
	rpc("_rpc_phase_result", current_phase, winner)
	_apply_phase_result(current_phase, winner)


# ══════════════════════════════════════════════════════════════════════════════
#  RPC – PHASE RESULT  (host → clients)
# ══════════════════════════════════════════════════════════════════════════════

@rpc("authority", "reliable", "call_remote")
func _rpc_phase_result(phase : int, winner_idx : int) -> void:
	_apply_phase_result(phase, winner_idx)


func _apply_phase_result(phase : int, winner_idx : int) -> void:
	_phase_decided = true
	_can_select = false

	var cards : Array[Node3D] = _cards_for(phase)
	_highlight_winner(cards, winner_idx)

	# Store the winning selection.
	match phase:
		Phase.GAMEMODE:
			chosen_gamemode = offered_gamemodes[winner_idx]
			gm_preview.text = "Gamemode: %s" % chosen_gamemode
		Phase.MAP:
			var map_name : String = offered_maps[winner_idx]
			chosen_map_path = ALL_MAPS[map_name]
			map_preview.text = "Map: %s" % map_name
		Phase.BUFF:
			chosen_buff = offered_buffs[winner_idx]
			buff_preview.text = "Buff: %s" % chosen_buff

	await get_tree().create_timer(1.2).timeout
	_advance_phase(phase)


func _highlight_winner(cards : Array[Node3D], winner_idx : int) -> void:
	for i : int in cards.size():
		if i == winner_idx:
			var tw := create_tween()
			tw.tween_property(cards[i], "scale", Vector3(1.25, 1.25, 1.25), 0.25)
		else:
			var tw := create_tween()
			tw.tween_property(cards[i], "scale", Vector3.ONE, 0.15)
			var mesh : MeshInstance3D = cards[i].get_node("MeshInstance3D")
			var tw2 := create_tween()
			tw2.tween_property(mesh, "transparency", 0.7, 0.3)


func _advance_phase(phase : int) -> void:
	match phase:
		Phase.GAMEMODE:
			title_label.text = "CHOOSE MAP"
			anim_player.play("pivot_to_map")
		Phase.MAP:
			title_label.text = "CHOOSE BUFF"
			anim_player.play("pivot_to_buff")
		Phase.BUFF:
			title_label.text = ""
			timer_label.text = ""
			current_phase = Phase.LAUNCHING
			anim_player.play("pivot_down")
			await anim_player.animation_finished
			_launch_game()


# ══════════════════════════════════════════════════════════════════════════════
#  LAUNCH
# ══════════════════════════════════════════════════════════════════════════════

func _launch_game() -> void:
	var tw := create_tween()
	tw.tween_property(blackout, "modulate:a", 1.0, 0.6)
	await tw.finished

	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.selected_map = chosen_map_path
		gs.selected_gamemode = chosen_gamemode
		gs.selected_buff = chosen_buff

	get_tree().change_scene_to_file(chosen_map_path)


func _on_server_closed() -> void:
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.disconnect_message = "Host left the server."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")