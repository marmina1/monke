extends CanvasLayer

# Node paths match the hierarchy defined in Player.tscn.
@onready var hunger_label     : Label       = $Control/TopLeft/VBox/HungerLabel
@onready var hunger_bar       : ProgressBar = $Control/TopLeft/VBox/HungerBar
@onready var starvation_label : Label       = $Control/TopLeft/VBox/StarvationLabel
@onready var death_label      : Label       = $Control/DeathLabel
@onready var crosshair        : Label       = $Control/Crosshair
@onready var combo_label      : Label       = $Control/ComboLabel
@onready var speed_lines                    = $Control/SpeedLines


func _ready() -> void:
	starvation_label.visible = false
	death_label.visible      = false
	combo_label.visible      = false


## Called every frame by the player's `hunger_changed` signal.
func update_hunger(value: float, max_value: float) -> void:
	hunger_bar.max_value = max_value
	hunger_bar.value     = value
	hunger_label.text    = "Hunger  %d / %d" % [int(value), int(max_value)]

	# Colour-code the bar: green → yellow → red.
	var ratio := value / max_value
	if ratio > 0.5:
		hunger_bar.modulate = Color(0.2, 0.9, 0.2)    # green
	elif ratio > 0.25:
		hunger_bar.modulate = Color(1.0, 0.75, 0.0)   # yellow
	else:
		hunger_bar.modulate = Color(1.0, 0.25, 0.25)  # red


## Called every frame by the player's `starvation_tick` signal.
## time_left == 0.0 means the starvation was cancelled – hide the label.
func update_starvation_timer(time_left: float) -> void:
	if time_left > 0.0:
		starvation_label.visible = true
		starvation_label.text    = "STARVING  dying in %.1fs" % time_left
	else:
		starvation_label.visible = false


## Called once by the player's `player_died` signal.
func show_death_screen() -> void:
	death_label.visible = true


## Called every frame from player._process().
## White = nothing in range. Yellow = vine is grabbable.
func set_vine_targeted(targeting: bool) -> void:
	crosshair.modulate = Color(1.0, 0.9, 0.1) if targeting else Color(1, 1, 1, 0.7)


## Called by the player's combo_changed signal.
## Shows a coloured counter when the chain is 2+; hides it otherwise.
func update_combo(count: int) -> void:
	if count < 2:
		combo_label.visible = false
		return
	combo_label.visible = true
	combo_label.text    = "×%d" % count
	# Colour ramp: green → yellow → orange → red.
	var col: Color
	if   count >= 8: col = Color(1.0, 0.15, 0.15)
	elif count >= 5: col = Color(1.0, 0.50, 0.10)
	elif count >= 3: col = Color(1.0, 0.85, 0.00)
	else:            col = Color(0.45, 1.0,  0.30)
	combo_label.add_theme_color_override("font_color", col)
	# Overbright flash that settles to normal – cheap punch-in animation.
	combo_label.modulate = Color(2.5, 2.5, 2.5, 1.0)
	var tw := create_tween()
	tw.tween_property(combo_label, "modulate", Color.WHITE, 0.25)


## Called by the player's speed_changed signal every process frame.
func set_speed(speed: float) -> void:
	speed_lines.set_speed(speed)
