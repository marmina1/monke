extends Control

@onready var play_button       : Button = $CenterContainer/VBoxContainer/PlayButton
@onready var playground_button : Button = $CenterContainer/VBoxContainer/PlaygroundButton
@onready var settings_button   : Button = $CenterContainer/VBoxContainer/SettingsButton
@onready var exit_button       : Button = $CenterContainer/VBoxContainer/ExitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_button.pressed.connect(_on_play)
	playground_button.pressed.connect(_on_playground)
	settings_button.pressed.connect(_on_settings)
	exit_button.pressed.connect(_on_exit)
	# Give focus to the first button for keyboard / controller nav.
	play_button.grab_focus()

	# Show disconnect message if returning from a host-left scenario.
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		if gs.disconnect_message != "":
			_show_disconnect_popup(gs.disconnect_message)
			gs.disconnect_message = ""


func _show_disconnect_popup(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Disconnected"
	dialog.dialog_text = msg
	dialog.min_size = Vector2i(320, 100)
	add_child(dialog)
	dialog.popup_centered()


func _on_play() -> void:
	# Multiplayer: go to the connect / lobby screen.
	get_tree().change_scene_to_file("res://multiplayer/ConnectScreen.tscn")


func _on_playground() -> void:
	get_tree().change_scene_to_file("res://ui/PlaygroundMenu.tscn")


func _on_settings() -> void:
	get_tree().change_scene_to_file("res://ui/SettingsMenu.tscn")


func _on_exit() -> void:
	get_tree().quit()
