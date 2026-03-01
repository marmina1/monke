extends CanvasLayer

## In-game chat overlay.  Press T to open, Enter to send, Escape to cancel.
## Listens to Lobby.chat_received for incoming messages.

const MAX_MESSAGES : int = 50
const FADE_TIME    : float = 6.0   ## seconds before idle messages fade out

var _is_open : bool = false
var _messages : Array[Dictionary] = []  # { "sender": String, "text": String, "time": float }

@onready var chat_container : VBoxContainer = $Panel/Margin/VBox/ScrollContainer/ChatMessages
@onready var input_field    : LineEdit      = $Panel/Margin/VBox/InputRow/InputField
@onready var scroll         : ScrollContainer = $Panel/Margin/VBox/ScrollContainer
@onready var panel          : PanelContainer  = $Panel


func _ready() -> void:
	layer = 10
	input_field.visible = false
	# Make panel semi-transparent when not typing.
	panel.modulate.a = 0.4

	if has_node("/root/Lobby"):
		var lobby : Node = get_node("/root/Lobby")
		lobby.chat_received.connect(_on_chat_received)
		lobby.server_closed.connect(_on_server_closed)

	input_field.text_submitted.connect(_on_text_submitted)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not _is_open:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed("ui_cancel"):
		_close_chat()
		get_viewport().set_input_as_handled()


func _open_chat() -> void:
	_is_open = true
	input_field.visible = true
	input_field.text = ""
	input_field.grab_focus()
	panel.modulate.a = 0.85
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_chat() -> void:
	_is_open = false
	input_field.visible = false
	input_field.release_focus()
	panel.modulate.a = 0.4
	# Only re-capture the mouse if the local player is alive and in gameplay.
	if _should_capture_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Returns true only when the local player is alive in an active game round.
func _should_capture_mouse() -> bool:
	var players : Node = get_tree().current_scene.get_node_or_null("Players")
	if not players:
		return false
	for child : Node in players.get_children():
		if child is Player and child.is_local and not child.is_dead:
			return true
	return false


func _on_text_submitted(text: String) -> void:
	var msg := text.strip_edges()
	if msg != "" and has_node("/root/Lobby"):
		var lobby : Node = get_node("/root/Lobby")
		lobby.send_chat(msg)
	_close_chat()


func _on_chat_received(sender: String, text: String) -> void:
	_add_message(sender, text)


func _add_message(sender: String, text: String) -> void:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	label.scroll_active = false
	label.custom_minimum_size.x = 280
	if sender == "":
		# System message.
		label.text = "[color=yellow][i]%s[/i][/color]" % text
	else:
		label.text = "[b]%s:[/b] %s" % [sender, text]
	label.add_theme_font_size_override("normal_font_size", 14)
	chat_container.add_child(label)

	# Cap message count.
	while chat_container.get_child_count() > MAX_MESSAGES:
		chat_container.get_child(0).queue_free()

	# Auto-scroll to bottom.
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _on_server_closed() -> void:
	_add_message("", "Host left the server.")
	# Set disconnect message so main menu can display it.
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.disconnect_message = "Host left the server."
	# Return to menu after a short delay.
	await get_tree().create_timer(2.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
