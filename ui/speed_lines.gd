class_name SpeedLines
extends Control

# ── Inspector-tunable parameters ─────────────────────────────────────────────
## Speed (m/s) at which streaks begin to appear.
@export var fade_in_speed  : float = 8.0
## Speed (m/s) at which streaks are fully opaque.
@export var fade_max_speed : float = 22.0
## Number of radial streaks.
@export var line_count     : int   = 32
## Peak opacity of the streaks (0 – 1).
@export var max_alpha      : float = 0.65
## Width of each streak in pixels.
@export var line_width     : float = 1.8
## How fast ALL lines rotate together at full speed (rad/s).
@export var global_spin    : float = 0.55
## Extra per-line spin multiplier range (each line drifts a bit differently).
@export var per_line_spin_range : Vector2 = Vector2(0.5, 1.5)
## Inner start distance as a fraction of the screen diagonal.
@export var inner_frac     : float = 0.08
## Outer length range (fractions of diagonal) before wobble is applied.
@export var outer_frac     : Vector2 = Vector2(0.30, 0.90)
## Amplitude of the per-line length oscillation.
@export var length_wobble  : float = 0.14

# ── Internal per-line data (rebuilt in _ready / when line_count changes) ──────
var _base_angles   : PackedFloat32Array
var _spin_rates    : PackedFloat32Array   # multiplier on global_spin
var _base_lengths  : PackedFloat32Array   # 0-1 in the outer_frac range
var _wobble_freq   : PackedFloat32Array   # oscillation frequency per line
var _wobble_phase  : PackedFloat32Array   # oscillation phase offset per line

var _speed : float = 0.0
var _time  : float = 0.0   # advances only when alpha > 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_lines()


func _build_lines() -> void:
	_base_angles.resize(line_count)
	_spin_rates.resize(line_count)
	_base_lengths.resize(line_count)
	_wobble_freq.resize(line_count)
	_wobble_phase.resize(line_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in line_count:
		_base_angles[i]  = rng.randf() * TAU
		_spin_rates[i]   = rng.randf_range(per_line_spin_range.x, per_line_spin_range.y)
		_base_lengths[i] = rng.randf()                      # mapped to outer_frac in _draw
		_wobble_freq[i]  = rng.randf_range(0.7, 2.8)
		_wobble_phase[i] = rng.randf() * TAU


## Called every _process frame from hud.set_speed() with the current speed (m/s).
func set_speed(s: float) -> void:
	_speed = s


func _process(delta: float) -> void:
	var alpha := clampf((_speed - fade_in_speed) / (fade_max_speed - fade_in_speed), 0.0, 1.0)
	if alpha > 0.005:
		# Advance time proportional to how fast we're going — slow swing = lazy drift,
		# full speed = frantic spin.
		_time += delta * lerpf(0.2, 1.0, alpha)
		queue_redraw()
	elif _time > 0.0:
		# Fade out — keep redrawing until alpha hits zero.
		queue_redraw()


func _draw() -> void:
	var alpha := clampf((_speed - fade_in_speed) / (fade_max_speed - fade_in_speed), 0.0, 1.0)
	if alpha < 0.005:
		return

	var cx   : float = size.x * 0.5
	var cy   : float = size.y * 0.5
	var diag : float = Vector2(cx, cy).length()

	for i in line_count:
		# Each line rotates at its own rate around the centre.
		var angle := _base_angles[i] + _time * global_spin * _spin_rates[i]
		var dir   := Vector2(cos(angle), sin(angle))

		# Length oscillates between outer_frac.x and outer_frac.y.
		var wobble   := sin(_time * _wobble_freq[i] + _wobble_phase[i]) * length_wobble
		var length_t := clampf(_base_lengths[i] + wobble, 0.0, 1.0)
		var outer    := lerpf(outer_frac.x, outer_frac.y, length_t)

		var start := Vector2(cx, cy) + dir * (diag * inner_frac)
		var endp  := Vector2(cx, cy) + dir * (diag * outer)

		# Gradient: fully transparent at start, blue-white at tip.
		draw_polyline_colors(
			PackedVector2Array([start, endp]),
			PackedColorArray([
				Color(0.85, 0.92, 1.0, 0.0),
				Color(0.85, 0.92, 1.0, alpha * max_alpha),
			]),
			line_width
		)
