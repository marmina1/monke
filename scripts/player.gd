class_name Player
extends CharacterBody3D

# ── Movement constants ────────────────────────────────────────────────────────
const GRAVITY           := 9.8
const MOUSE_SENSITIVITY := 0.003

# ── Hunger settings (tweak in the Inspector) ──────────────────────────────────
@export var max_hunger             : float = 100.0
@export var hunger_drain_rate      : float = 1.25  ## units drained per second (1 per 0.8 s)
@export var starvation_death_delay : float = 10.0  ## seconds at zero before death

# ── Push settings (tweak in the Inspector) ────────────────────────────────────
## Velocity impulse applied per hand push (m/s).
@export var push_force     : float = 10.0
## Minimum seconds between successive pushes on the same hand.
@export var push_cooldown  : float = 0.35
## Horizontal speed multiplier per physics frame while on the floor.
## 0.85^60fps ≈ stops in ~0.5 s – gives a crisp "planted" feel.
@export var floor_friction : float = 0.85
## Horizontal speed multiplier per physics frame while airborne.
## 0.9998^60fps ≈ 0.988/s — barely any drag so momentum carries naturally.
@export var air_damping    : float = 0.9998
## Minimum speed injected when grabbing a vine from a standstill.
## Gives the pendulum an initial kick so it swings immediately.
@export var swing_launch_speed : float = 5.0

# ── Release feel (tweak in the Inspector) ──────────────────────────────────────
## Horizontal speed multiplier applied on every last-hand release with no combo.
## Combo adds +15 % per step: ×2 combo = ×1.5, ×3 = ×1.65, etc.
@export var release_boost_mult : float = 1.2
## Camera FOV at rest.
@export var fov_base       : float = 70.0
## Camera FOV at full swing speed (fov_speed_full m/s).
@export var fov_max        : float = 108.0
## Speed (m/s) at which FOV reaches fov_max.
@export var fov_speed_full : float = 14.0

# ── Combo system (tweak in the Inspector) ──────────────────────────────────────
## Max seconds to hold a vine before the alternating combo resets on release.
@export var combo_hold_limit       : float = 2.0
## Hunger drain reduction per combo step (0.15 = −15 % drain per step).
@export var combo_hunger_reduction : float = 0.15
## Minimum hunger drain multiplier at high combo (0.10 = 90 % reduction cap).
@export var min_hunger_drain_mult  : float = 0.10
## Extra release-boost fraction per combo step (0.15 = +15 % per step).
## No combo=×1.2 | ×2=×1.5 | ×3=×1.65 | ×5=×1.95 …
@export var combo_speed_bonus      : float = 0.15

# ── Poo system (tweak in the Inspector) ──────────────────────────────────────────
## Poo projectile scene – assigned via the Inspector (or Player.tscn).
@export var poo_scene       : PackedScene
## Hunger consumed when creating a poo.  Fails silently if hunger is below this.
@export var poo_hunger_cost : float = 10.0
## Launch speed of a thrown poo (m/s).
@export var poo_throw_force : float = 22.0

# ── Runtime state ─────────────────────────────────────────────────────────────
var hunger      : float = 100.0
var is_dead     : bool  = false
var is_starving : bool  = false

# Per-hand cooldown timers.
var _left_cooldown  : float = 0.0
var _right_cooldown : float = 0.0

# ── Vine / hand state ─────────────────────────────────────────────────────────────
enum HandState { FREE, GRABBING, HOLDING_POO }
var left_hand_state  : HandState = HandState.FREE
var right_hand_state : HandState = HandState.FREE
var left_grab_point  : Marker3D  = null   ## GrabPoint on the grabbed vine
var right_grab_point : Marker3D  = null

# ── Swing pivot state (set on grab, consumed by rope constraint every frame) ──
## World position of the vine's top anchor used as the pendulum pivot.
var _left_pivot     : Vector3 = Vector3.ZERO
var _left_rope_len  : float   = 0.0
var _right_pivot    : Vector3 = Vector3.ZERO
var _right_rope_len : float   = 0.0

## Live reference to the grabbed Vine so we can update its chain each frame.
var _left_vine  : Vine = null
var _right_vine : Vine = null

## Extra FOV degrees injected on a timed release; decays to 0 each frame.
var _fov_pulse : float = 0.0

# ── Combo state ───────────────────────────────────────────────────────────────
## Current alternating-grab streak.  0 = inactive.
var _combo            : int   = 0
## 0 = left grabbed last,  1 = right grabbed last,  -1 = no grab yet.
var _last_grab_hand   : int   = -1
## The vine grabbed most recently – grabbing it again breaks the combo.
var _last_vine        : Vine  = null
## Time (s) held on the vine since the most-recent grab.
var _combo_hold_timer : float = 0.0

# ── Poo state ──────────────────────────────────────────────────────────────────────────────
## Lightweight visual (MeshInstance3D) parented to the holding hand.
## Freed on throw; a fresh physics Poo.tscn is spawned at that moment.
var _held_poo_visual  : Node3D = null
## Which hand is holding the poo.  true = left, false = right.
var _poo_hand_is_left : bool = true
## Seconds remaining in the double-tap window per hand (0 = window closed).
var _left_dtap_timer  : float = 0.0
var _right_dtap_timer : float = 0.0
const DTAP_WINDOW     : float = 0.35  ## seconds between taps to count as double
## Emitted every frame with the new hunger value (used by HUD).
signal hunger_changed(value: float, max_value: float)
## Emitted every frame while the starvation timer is running (0 = cancelled).
signal starvation_tick(time_left: float)
## Emitted once when the player actually dies.
signal player_died
## Emitted on every grab or combo reset – count is the new combo value.
signal combo_changed(count: int)
## Emitted every _process frame with the player's current speed in m/s.
signal speed_changed(speed: float)

# ── Cached node references ────────────────────────────────────────────────────
@onready var head               : Node3D   = $Head
@onready var camera             : Camera3D = $Head/Camera3D
@onready var hunger_death_timer : Timer    = $HungerDeathTimer
@onready var hud                           = $HUD
@onready var left_hand_ray      : RayCast3D  = $Head/LeftHandRay
@onready var right_hand_ray     : RayCast3D  = $Head/RightHandRay
@onready var vine_ray           : ShapeCast3D = $Head/VineRay
@onready var left_hand          : Hand        = $Head/LeftHand
@onready var right_hand         : Hand        = $Head/RightHand


func _ready() -> void:
	# Activate this camera (important when the player is instanced at runtime).
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Exclude the player's own body from all raycasts.
	# Head is a plain Node3D so Godot does NOT auto-exclude the CharacterBody3D;
	# without this the hand rays hit the player's own capsule from inside.
	left_hand_ray.add_exception(self)
	right_hand_ray.add_exception(self)
	vine_ray.add_exception(self)   # ShapeCast3D also supports add_exception

	# Configure the starvation timer.
	hunger_death_timer.wait_time = starvation_death_delay
	hunger_death_timer.one_shot  = true
	hunger_death_timer.timeout.connect(_on_death_timer_timeout)

	# Wire hunger signals directly into the HUD (self-contained).
	hunger_changed.connect(hud.update_hunger)
	starvation_tick.connect(hud.update_starvation_timer)
	player_died.connect(hud.show_death_screen)
	combo_changed.connect(hud.update_combo)
	speed_changed.connect(hud.set_speed)

	# Prime the HUD with the starting value immediately.
	hunger_changed.emit(hunger, max_hunger)


func _input(event: InputEvent) -> void:
	if is_dead:
		return

	# ── Mouse look ────────────────────────────────────────────────────────────
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

	# ── Escape toggles cursor capture ─────────────────────────────────────────
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	# ── Poo: quick double-tap LMB/RMB anywhere ──────────────────────────────────
	# First tap: opens a 0.35 s window (push/grab fires normally via _physics_process).
	# Second tap inside window + hand FREE: spawn poo in that hand.
	# Any tap while HOLDING_POO: throw it.
	if event.is_action_pressed("push_left"):
		if left_hand_state == HandState.HOLDING_POO:
			_throw_poo()
		elif _left_dtap_timer > 0.0 and left_hand_state == HandState.FREE:
			_try_create_poo(true)
			_left_dtap_timer = 0.0
		else:
			_left_dtap_timer = DTAP_WINDOW

	if event.is_action_pressed("push_right"):
		if right_hand_state == HandState.HOLDING_POO:
			_throw_poo()
		elif _right_dtap_timer > 0.0 and right_hand_state == HandState.FREE:
			_try_create_poo(false)
			_right_dtap_timer = 0.0
		else:
			_right_dtap_timer = DTAP_WINDOW


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# ── 1. Release check ──────────────────────────────────────────────────────
	if Input.is_action_just_released("push_left") and left_hand_state == HandState.GRABBING:
		_release_hand(true)
	if Input.is_action_just_released("push_right") and right_hand_state == HandState.GRABBING:
		_release_hand(false)

	# ── 2. Vine grab (runs even while swinging one hand – Tarzan-style lunge) ──
	_check_vine_grab()

	# ── 3. Cooldowns tick always so push is ready the instant you land ─────────
	_tick_cooldowns(delta)

	# ── 4. Gravity (applies in both swing and free-flight) ─────────────────────
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# ── 5. Swinging branch ────────────────────────────────────────────────────
	if _is_grabbing():
		_combo_hold_timer += delta

		# Notify each grabbed vine of the player's current world position so
		# the chain bends toward the player while swinging.
		# update_grab_target only updates the attraction point — the grabbed
		# node index was locked at grab time and must NOT change each frame or
		# the chain will flap between nodes, fighting the constraint solver.
		if _left_vine:
			_left_vine.update_grab_target(global_position)
		if _right_vine:
			_right_vine.update_grab_target(global_position)

		# ── Stage 1 · Pre-move velocity projection ────────────────────────────
		# Remove the outward-radial velocity component BEFORE move_and_slide.
		# This is the kinematic equivalent of rope-tension force: gravity's
		# radial pull is cancelled each frame, leaving only the tangential
		# component that accelerates the player along the pendulum arc.
		# Without this step the player moves through the sphere then snaps
		# back — the source of all visible jitter.
		# 3 Gauss-Seidel passes converge both hand constraints simultaneously.
		for _iter in 3:
			if left_hand_state == HandState.GRABBING:
				_project_swing_velocity(_left_pivot, _left_rope_len)
			if right_hand_state == HandState.GRABBING:
				_project_swing_velocity(_right_pivot, _right_rope_len)

		# move_and_slide lets the player land on platforms while mid-swing.
		move_and_slide()

		# ── Stage 2 · Post-move drift correction ──────────────────────────────
		# Removes the tiny arc-vs-chord error that accumulates because
		# move_and_slide steps along a straight chord, not the curved arc.
		# Also catches any extra stretch introduced by surface collisions.
		for _iter in 3:
			if left_hand_state == HandState.GRABBING:
				_correct_rope_length(_left_pivot, _left_rope_len)
			if right_hand_state == HandState.GRABBING:
				_correct_rope_length(_right_pivot, _right_rope_len)
		return

	# ── 6. Free-flight / grounded branch ─────────────────────────────────────
	if is_on_floor():
		if _combo > 0:
			_combo = 0
			combo_changed.emit(_combo)
		velocity.x *= floor_friction
		velocity.z *= floor_friction
	else:
		velocity.x *= air_damping
		velocity.z *= air_damping

	_handle_push()
	move_and_slide()


func _process(delta: float) -> void:
	if is_dead:
		return
	_tick_hunger(delta)
	# Stream live countdown to HUD every frame while the timer is running.
	if is_starving and not hunger_death_timer.is_stopped():
		starvation_tick.emit(hunger_death_timer.time_left)
	# Tint crosshair yellow when a VineLink is within reach of the shape cast.
	var targeting := false
	if vine_ray.is_colliding():
		for i in vine_ray.get_collision_count():
			if vine_ray.get_collider(i) is VineLink:
				targeting = true
				break
	hud.set_vine_targeted(targeting)

	# ── Dynamic FOV ─────────────────────────────────────────────────────
	# Base: quadratic ramp from fov_base at rest to fov_max at fov_speed_full.
	# Pulse: flat spike added on a timed release, decays at 40°/s so it lasts
	#        ~0.45 s — just long enough to register as a camera flick.
	_fov_pulse = maxf(_fov_pulse - delta * 35.0, 0.0)
	var spd        := velocity.length()
	var t          := clampf(spd / fov_speed_full, 0.0, 1.0)
	var target_fov := fov_base + (fov_max - fov_base) * t * t + _fov_pulse
	camera.fov      = lerpf(camera.fov, target_fov, delta * 4.0)
	speed_changed.emit(spd)

	# Arm tracks the held visual (it's a child of the hand, moves automatically).
	if _held_poo_visual != null:
		var poo_hand := left_hand if _poo_hand_is_left else right_hand
		poo_hand.grab(_held_poo_visual.global_position)

	# Guide free hands to follow the look direction instead of flopping.
	var _look_fwd := -head.global_transform.basis.z
	if left_hand_state  == HandState.FREE:
		left_hand.guide_to(left_hand.global_position + _look_fwd * 0.8)
	if right_hand_state == HandState.FREE:
		right_hand.guide_to(right_hand.global_position + _look_fwd * 0.8)


# ── Push system ───────────────────────────────────────────────────────────────

func _tick_cooldowns(delta: float) -> void:
	_left_cooldown   = maxf(_left_cooldown  - delta, 0.0)
	_right_cooldown  = maxf(_right_cooldown - delta, 0.0)
	_left_dtap_timer = maxf(_left_dtap_timer - delta, 0.0)
	_right_dtap_timer = maxf(_right_dtap_timer - delta, 0.0)


## Vine-grab input – runs every physics frame, even while swinging one hand,
## so the player can lunge for a second vine Tarzan-style mid-swing.
## Grab takes absolute priority; if both LMB and RMB are pressed the same frame
## they both grab the same vine (two-hand hang).
func _check_vine_grab() -> void:
	if not vine_ray.is_colliding():
		return
	# ShapeCast3D may hit walls (layer 1) before the vine (layer 2).
	# Walk all hits and take the first VineLink found.
	var link      : VineLink = null
	var hit_point : Vector3  = Vector3.ZERO
	for i in vine_ray.get_collision_count():
		var c := vine_ray.get_collider(i) as VineLink
		if c:
			link      = c
			hit_point = vine_ray.get_collision_point(i)
			break
	if not link:
		return
	var vine   : Vine    = link.root_vine
	# Physics pivot = fixed top anchor (verlet node 0, never moves).
	# Visual hit    = exact surface point the shape struck on the chain.
	var anchor : Vector3 = vine.grab_point.global_position
	if Input.is_action_just_pressed("push_left") and left_hand_state == HandState.FREE:
		_grab_vine(vine, true, anchor, hit_point)
	if Input.is_action_just_pressed("push_right") and right_hand_state == HandState.FREE:
		_grab_vine(vine, false, anchor, hit_point)


## Push input – only reached when both hands are FREE (not grabbing a vine).
## Averages valid push directions and scales force by hand count (1 or 2 hands).
func _handle_push() -> void:
	# Cannot push with empty hunger – no energy.
	if hunger <= 0.0:
		return
	var push_dirs : Array[Vector3] = []

	if Input.is_action_just_pressed("push_left"):
		if left_hand_state == HandState.FREE and _left_cooldown <= 0.0 \
				and left_hand_ray.is_colliding() \
				and not left_hand_ray.get_collider() is Vine:
			push_dirs.append(_push_dir_from(left_hand_ray))
			_left_cooldown = push_cooldown

	if Input.is_action_just_pressed("push_right"):
		if right_hand_state == HandState.FREE and _right_cooldown <= 0.0 \
				and right_hand_ray.is_colliding() \
				and not right_hand_ray.get_collider() is Vine:
			push_dirs.append(_push_dir_from(right_hand_ray))
			_right_cooldown = push_cooldown

	if push_dirs.is_empty():
		return

	var combined := Vector3.ZERO
	for d in push_dirs:
		combined += d
	velocity += combined.normalized() * push_force * push_dirs.size()

	# Each hand push costs 5 % of max hunger (double push = 10 %).
	hunger = clampf(hunger - push_dirs.size() * 0.05 * max_hunger, 0.0, max_hunger)
	hunger_changed.emit(hunger, max_hunger)



## Attach a hand to the vine at the exact ray-hit point on its surface.
## anchor     = vine_ray.get_collision_point() – the touched surface point.
## rope_len   = current distance from player to anchor (natural hang length).
## Clamped to 0.5 m minimum so a zero-distance grab doesn't collapse the sim.
func _grab_vine(vine: Vine, is_left: bool, anchor: Vector3, hit_point: Vector3) -> void:
	var link_idx := vine.nearest_link(global_position)

	# ── Combo check ───────────────────────────────────────────────────────────
	# Rewards L→R→L alternation across DIFFERENT vines.
	# Breaking rules → reset to 0 (not 1) so you have to earn the first step.
	var this_hand_id := 0 if is_left else 1
	var other_vine   := _right_vine if is_left else _left_vine
	var same_vine_as_last := (_last_vine == vine)
	if same_vine_as_last:
		# Spamming the same vine – kill the streak entirely.
		_combo = 0
	elif other_vine != null and other_vine == vine:
		# Both hands on the same vine at once = hang, not a combo swing.
		pass   # don't touch _combo
	else:
		if _last_grab_hand == -1 or this_hand_id != _last_grab_hand:
			_combo += 1   # first grab or correct alternation
		else:
			_combo = 1    # same hand twice – restart at 1
	_last_grab_hand   = this_hand_id
	_last_vine        = vine
	_combo_hold_timer = 0.0
	combo_changed.emit(_combo)

	# ── Launch kick ─────────────────────────────────────────────────────────────
	# If the player grabs a vine while standing still (or moving slowly), the
	# pendulum has no initial velocity and just hangs.  Inject a horizontal
	# kick in the player's current look direction so the swing starts at once.
	# The kick is proportional to how much speed is missing up to launch_speed.
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed < swing_launch_speed:
		var fwd := -global_transform.basis.z   # player's horizontal forward
		fwd.y    = 0.0
		if fwd.length_squared() > 0.001:
			fwd = fwd.normalized()
			velocity += fwd * (swing_launch_speed - horiz_speed)

	if is_left:
		left_hand_state = HandState.GRABBING
		left_grab_point = vine.grab_point
		_left_pivot     = anchor
		_left_rope_len  = maxf((global_position - anchor).length(), 0.5)
		_left_vine      = vine
		vine.set_grab(link_idx, global_position)
		left_hand.grab(hit_point)   # arm points to where the ray hit the vine
	else:
		right_hand_state = HandState.GRABBING
		right_grab_point = vine.grab_point
		_right_pivot     = anchor
		_right_rope_len  = maxf((global_position - anchor).length(), 0.5)
		_right_vine      = vine
		vine.set_grab(link_idx, global_position)
		right_hand.grab(hit_point)  # arm points to where the ray hit the vine


## Detach a hand from its vine.
func _release_hand(is_left: bool) -> void:
	# ── Release boost ──────────────────────────────────────────────────────
	# Fires only when the LAST hand releases (the true launch moment).
	# Boost is applied strictly along the current horizontal travel direction
	# so it always feels like a clean push forward, never sideways.
	var other_grabbing := (right_hand_state == HandState.GRABBING) if is_left \
						else (left_hand_state  == HandState.GRABBING)
	if not other_grabbing:
		var h2d := Vector2(velocity.x, velocity.z)
		var hs  := h2d.length()
		if hs > 0.1:   # only boost if actually moving
			var dir2d       := h2d / hs
			# Combo scales the multiplier: +10 % per step on top of the base 1.5×.
			var total_boost := release_boost_mult + _combo * combo_speed_bonus
			var boosted     := hs * total_boost
			velocity.x       = dir2d.x * boosted
			velocity.z       = dir2d.y * boosted
			# Combo also inflates the FOV punch — high combos feel frantic.
			_fov_pulse       = clampf(boosted * 1.8 + _combo * 1.5, 12.0, 40.0)
		# Break the combo if the vine was clung to too long.
		if _combo_hold_timer > combo_hold_limit:
			_combo = 0
			combo_changed.emit(_combo)

	if is_left:
		left_hand_state = HandState.FREE
		left_grab_point = null
		if _left_vine:
			_left_vine.clear_grab()
			_left_vine = null
		left_hand.release()
	else:
		right_hand_state = HandState.FREE
		right_grab_point = null
		if _right_vine:
			_right_vine.clear_grab()
			_right_vine = null
		right_hand.release()


## True when at least one hand is holding a vine.
func _is_grabbing() -> bool:
	return left_hand_state == HandState.GRABBING or right_hand_state == HandState.GRABBING


## Stage 1 — Pre-move velocity projection.
## Removes the outward-radial velocity component while the rope is taut.
## Physically: rope tension is an impulsive constraint force that eliminates
## any velocity pulling the player away from the pivot.  Gravity's tangential
## component is preserved, accelerating the player along the pendulum arc.
## Slack rope (dist < rope_len) is left unconstrained — pure free-fall.
func _project_swing_velocity(pivot: Vector3, rope_len: float) -> void:
	var to_player := global_position - pivot
	var dist      := to_player.length()
	if dist < 0.001:
		return
	if dist < rope_len:                   # rope slack — no tension active
		return
	var radial_dir  := to_player / dist
	var outward_vel := velocity.dot(radial_dir)
	if outward_vel > 0.0:                 # only cancel the stretching part
		velocity -= radial_dir * outward_vel


## Stage 2 — Post-move positional drift correction.
## Corrects floating-point error that accumulates because move_and_slide
## integrates a straight chord rather than the curved arc.  After snapping
## position back to the rope sphere, any radial velocity that move_and_slide
## may have re-introduced (e.g. sliding against a surface mid-swing) is also
## removed, preventing a rebound impulse on the next frame.
func _correct_rope_length(pivot: Vector3, rope_len: float) -> void:
	var diff := global_position - pivot
	var dist := diff.length()
	if dist < 0.001 or dist <= rope_len:
		return
	var dir := diff / dist
	global_position  = pivot + dir * rope_len   # positional correction
	var away_vel := velocity.dot(dir)
	if away_vel > 0.0:
		velocity -= dir * away_vel              # velocity correction


## Returns the impulse direction: exact reverse of the ray's shoot direction.
## When looking straight down the ray shoots -Y so the push is +Y (straight up).
## Works correctly at any angle without any per-hand-position offset error.
func _push_dir_from(ray: RayCast3D) -> Vector3:
	# The ray fires along its local -Z. Its local +Z is the exact opposite.
	return ray.global_transform.basis.z.normalized()


# ── Poo creation / throw ─────────────────────────────────────────────────────

func _try_create_poo(use_left: bool) -> void:
	if hunger < poo_hunger_cost:
		return

	_poo_hand_is_left = use_left
	hunger = clampf(hunger - poo_hunger_cost, 0.0, max_hunger)
	hunger_changed.emit(hunger, max_hunger)

	# Build a lightweight visual sphere parented to the hand so it sticks perfectly.
	# No physics body here – a fresh Poo.tscn is spawned only when thrown.
	var poo_hand := left_hand if use_left else right_hand
	var visual   := MeshInstance3D.new()
	var sphere   := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.15, 0.04)
	visual.mesh = sphere
	visual.set_surface_override_material(0, mat)
	poo_hand.add_child(visual)
	visual.position = Vector3(0.0, 0.0, -0.7)  # arm tip in hand-local space
	_held_poo_visual = visual

	# Extend arm to the visual immediately.
	poo_hand.grab(_held_poo_visual.global_position)

	if use_left:
		left_hand_state = HandState.HOLDING_POO
	else:
		right_hand_state = HandState.HOLDING_POO


func _throw_poo() -> void:
	if _held_poo_visual == null:
		return

	var throw_pos := _held_poo_visual.global_position
	var throw_dir := -head.global_transform.basis.z

	# Remove the visual.
	_held_poo_visual.queue_free()
	_held_poo_visual = null

	# Spawn a fresh physics poo at the visual's world position and throw it.
	if poo_scene:
		var poo : Poo = poo_scene.instantiate() as Poo
		get_parent().add_child(poo)
		poo.global_position = throw_pos
		poo.setup(self)
		poo.throw(throw_dir, poo_throw_force)

	if _poo_hand_is_left:
		left_hand_state = HandState.FREE
		left_hand.release()
	else:
		right_hand_state = HandState.FREE
		right_hand.release()


# ── Hunger logic ──────────────────────────────────────────────────────────────

func _tick_hunger(delta: float) -> void:
	# High combo = less hunger drain (reward for skilful alternating swings).
	var drain_mult := maxf(1.0 - _combo * combo_hunger_reduction, min_hunger_drain_mult)
	hunger = clamp(hunger - hunger_drain_rate * drain_mult * delta, 0.0, max_hunger)
	hunger_changed.emit(hunger, max_hunger)

	if hunger <= 0.0:
		if not is_starving:
			is_starving = true
			hunger_death_timer.start()
	else:
		if is_starving:
			# Hunger recovered – cancel the death countdown.
			is_starving = false
			hunger_death_timer.stop()
			starvation_tick.emit(0.0)   # Signal 0 tells the HUD to hide the label.


## Public API – call this from banana pickups (implemented later).
func add_hunger(amount: float) -> void:
	hunger = clamp(hunger + amount, 0.0, max_hunger)
	hunger_changed.emit(hunger, max_hunger)


func _on_death_timer_timeout() -> void:
	die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	_combo          = 0
	_last_vine      = null
	_last_grab_hand = -1
	combo_changed.emit(_combo)
	if _held_poo_visual:
		_held_poo_visual.queue_free()
		_held_poo_visual = null
		if _poo_hand_is_left:
			left_hand_state = HandState.FREE
		else:
			right_hand_state = HandState.FREE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()
