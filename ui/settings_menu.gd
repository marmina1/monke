extends Control

@onready var back_button       : Button   = $MarginContainer/VBoxContainer/HeaderRow/BackButton
@onready var master_slider     : HSlider  = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/MasterVolumeRow/MasterSlider
@onready var master_value      : Label    = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/MasterVolumeRow/MasterValue
@onready var sfx_slider        : HSlider  = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/SFXVolumeRow/SFXSlider
@onready var sfx_value         : Label    = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/SFXVolumeRow/SFXValue
@onready var sens_slider       : HSlider  = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/SensitivityRow/SensSlider
@onready var sens_value        : Label    = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/SensitivityRow/SensValue
@onready var fullscreen_toggle : CheckBox = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/FullscreenToggle
@onready var vsync_toggle      : CheckBox = $MarginContainer/VBoxContainer/CenterContainer/SettingsPanel/SettingsVBox/VSyncToggle
@onready var apply_button      : Button   = $MarginContainer/VBoxContainer/ApplyButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Load current values from GameSettings autoload if available.
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		master_slider.value     = gs.master_volume
		sfx_slider.value        = gs.sfx_volume
		sens_slider.value       = gs.mouse_sensitivity
		fullscreen_toggle.button_pressed = gs.fullscreen
		vsync_toggle.button_pressed      = gs.vsync

	# Connect signals.
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sens_slider.value_changed.connect(_on_sens_changed)
	back_button.pressed.connect(_on_back)
	apply_button.pressed.connect(_on_apply)

	# Initial label update.
	_update_labels()
	apply_button.grab_focus()


func _update_labels() -> void:
	master_value.text = "%d%%" % int(master_slider.value * 100)
	sfx_value.text    = "%d%%" % int(sfx_slider.value * 100)
	sens_value.text   = "%d%%" % int(sens_slider.value * 100)


func _on_master_changed(_val: float) -> void:
	_update_labels()


func _on_sfx_changed(_val: float) -> void:
	_update_labels()


func _on_sens_changed(_val: float) -> void:
	_update_labels()


func _on_apply() -> void:
	if has_node("/root/GameSettings"):
		var gs : Node = get_node("/root/GameSettings")
		gs.master_volume      = master_slider.value
		gs.sfx_volume         = sfx_slider.value
		gs.mouse_sensitivity  = sens_slider.value
		gs.fullscreen         = fullscreen_toggle.button_pressed
		gs.vsync              = vsync_toggle.button_pressed
		gs._apply_audio()
		gs._apply_display()


func _on_back() -> void:
	# Apply before leaving so changes aren't lost.
	_on_apply()
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")
