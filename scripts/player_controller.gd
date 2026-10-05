extends CharacterBody3D

const SnowChunkScript = preload("res://scripts/snow_chunk.gd")
const SoundEffectsScript = preload("res://scripts/sound_effects.gd")
const SnowBallScript = preload("res://scripts/snowball.gd")
const PinPropScript = preload("res://scripts/pin_prop.gd")

@export var mouse_sensitivity: float = 0.0025
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 6.8
@export var acceleration: float = 14.0

# Movement with inertia and bunny hop.
## Steering authority in the air, as a fraction of a dedicated air acceleration.
@export var air_control: float = 0.35
## Horizontal acceleration while airborne (m/s^2). Feeds the air strafe.
@export var air_acceleration: float = 9.0
## Hard ceiling of the bunny hop, relative to the sprint speed.
@export var bhop_cap_factor: float = 1.6
## Launch boost per chained jump. Chaining is what makes the hop pay off.
@export var bhop_gain: float = 1.06
## How long after landing a jump still counts as chained (s).
@export var bhop_window: float = 0.12
## Ground scrub applied on landing, by surface type, before any hop bonus.
@export var landing_scrub_packed: float = 0.97
@export var landing_scrub_snow: float = 0.85
@export var landing_scrub_loose: float = 0.55
## Landing compacts the snow it hits, which is how hopping packs a trail.
@export var landing_pack_strength: float = 0.18
@export var landing_pack_radius: float = 0.38
## Holding jump hops again on landing. Off by default: the rhythm is the skill.
@export var auto_bhop: bool = false
@export var jump_velocity: float = 5.2
@export var gravity: float = 18.0

# Shovel: bidirectional physical tool.
## Maximum mass the shovel cavity can hold (kg).
@export var shovel_capacity_max: float = 25.0
## Cut resistance per meter of blade and meter of snow (N).
@export var cut_resistance_per_m: float = 52.0
## Resistance (N) at which the shovel jams. Deliberately high: only a
## genuinely massive pile should stop the player.
@export var stuck_resistance: float = 140.0
## Snow height in front of the blade (m) that jams the shovel (pile taller than the blade).
@export var stuck_height_m: float = 0.58
## Speed factor applied while the shovel is jammed.
@export_range(0.1, 1.0) var stuck_speed_factor: float = 0.32
## Drag per meter of snow in front of the blade (fraction of speed lost).
@export var plow_drag_per_m: float = 1.0
## Drag per kilogram loaded in the shovel.
@export var load_drag_per_kg: float = 0.018
## Load weight in the physical resistance reading (for the HUD).
@export var load_resistance_factor: float = 0.18
## Pour rate of the tilted shovel (kg/s).
@export var dump_rate: float = 9.0
## Maximum fill rate while scooping (kg/s): the shovel does not fill in one hit.
@export var fill_rate: float = 34.0
@export var tamp_radius: float = 0.36
## Minimum snow mass for hand-packing a ball (kg).
@export var pack_min_kg: float = 0.4
@export var carry_distance: float = 1.15
## Throw: reference speed for the reference light ball. Speed falls with mass
## along a SOFTENED exponent (`throw_mass_exponent`), not constant energy: an
## exponent of 0.5 would punish large balls too hard and make them unplayable.
@export var throw_ref_speed: float = 9.0
@export var throw_ref_mass: float = 1.7
@export_range(0.15, 0.5) var throw_mass_exponent: float = 0.30
## Extra force when throwing two-handed above the head.
@export var two_hands_throw_boost: float = 1.8
## Mass (kg) at which the ball is carried with BOTH hands above the head.
@export var two_hands_mass: float = 35.0
## Mass (kg) at which stagger reaches its maximum.
@export var stagger_full_mass: float = 150.0
## Reference mass for the walking load penalty. Deliberately high: staggering
## must cost CONTROL (drift, grip), not turn walking into crawling.
@export var carry_weight_ref: float = 300.0
## Speed floor while carrying: weight never costs more than this.
@export_range(0.3, 1.0) var carry_speed_floor: float = 0.75
## Grip drain per second while carrying a ball two-handed.
@export var grip_drain_base: float = 0.05
@export var grip_drain_stagger: float = 0.22
## Holding [E] this long pushes the ball along the ground instead of lifting it.
@export var interact_hold_time: float = 0.25
@export var ground_push_strength: float = 1.0
@export var interact_distance: float = 2.9

## Short tap of the right button = parabolic toss.
const TOSS_TAP_TIME: float = 0.22
## Density of hand-packed snow (kg/m3).
const PACKED_DENSITY: float = 300.0
## Body push against balls and props (m/s2).
const PUSH_ACCEL: float = 9.0

@onready var camera: Camera3D = $Camera3D
@onready var hand_root: Node3D = $Camera3D/HandRoot
@onready var shovel_node: Node3D = $Camera3D/HandRoot/Shovel
@onready var blower_node: Node3D = $Camera3D/HandRoot/SnowBlower
@onready var salt_node: Node3D = $Camera3D/HandRoot/SaltShaker

var snow_field: Node3D
var props_system: Node3D

enum ToolType { SHOVEL = 0, BLOWER = 1, SALT = 2 }
var current_tool: ToolType = ToolType.SHOVEL

# Shovel state
var shovel_current_load: float = 0.0  # kg
var is_pushing: bool = false
var is_tossing: bool = false
var toss_timer: float = 0.0
var is_dumping: bool = false
var is_tamping: bool = false
var tamp_timer: float = 0.0
var snow_resistance: float = 0.0
## Normalized advance drag (0 = free). Drives the shoveling speed.
var push_drag: float = 0.0
## Snow height in front of the blade (m): readout for HUD and diagnostics.
var blade_snow_height: float = 0.0
var is_stuck: bool = false
var bite_factor: float = 0.0
var prev_scoop_pos: Vector3 = Vector3.INF
var is_grounded: bool = true
var is_jumping: bool = false
var current_ground_y: float = 0.0
var is_ground_initialized: bool = false

# Movement with inertia: surface friction, air control and bunny hop.
## Surface the player is standing on, refreshed every physics step.
var surface_name: String = "snow"
## Speed multiplier of the current surface (powder crawls, packed is fast).
var surface_speed_scale: float = 1.0
## How fast the player coasts to a stop when not pushing (higher = stops sooner).
var surface_coast: float = 1.2
## Speed kept when landing on this surface without hopping again.
var surface_scrub: float = 0.85
## Raw readings behind the surface decision, for the HUD and diagnostics.
var surface_height: float = 0.0
var surface_cohesion: float = 0.0
var surface_loose: float = 0.0
## Chained jumps landed inside the window: 0 when the chain is broken.
var jump_chain: int = 0
## Current bunny hop speed, horizontal (m/s).
var horizontal_speed: float = 0.0
var _time: float = 0.0
var _landing_time: float = -99.0
var _jump_buffer: float = 0.0
## Momentum is only scrubbed once the hop window closes; that is the whole skill.
var _pending_scrub: bool = false
const BASE_CAMERA_Y: float = 1.65
const DEADBAND_THRESHOLD: float = 0.08
const VERTICAL_TRANSITION_SPEED: float = 2.6

# Prop interaction
var carried: RigidBody3D = null
var carried_velocity: Vector3 = Vector3.ZERO
var _carried_prev_pos: Vector3 = Vector3.ZERO
## Carry physics: real weight, two-handed stance, stagger and grip.
var carried_mass: float = 0.0
var carry_two_hands: bool = false
var stagger: float = 0.0
var grip_left: float = 1.0
var _stagger_phase: float = 0.0
## Push with held [E]: the ball rolls along the ground.
var is_ground_pushing: bool = false
var _interact_hold: float = 0.0
var _interact_was_pressed: bool = false
var _pushed_during_hold: bool = false
var _push_target: RigidBody3D = null
var _right_hold: float = 0.0
var _thrown_this_press: bool = false
var _player_owner: int = 0
var _pending_pack: bool = false
var status_message: String = ""
## Diagnostic traces for the shovel cycle.
var debug_shovel: bool = false
var _pour_ops: int = 0

var blower_audio: AudioStreamPlayer3D
var scrape_audio: AudioStreamPlayer3D
var step_audio: AudioStreamPlayer3D
var wind_player: AudioStreamPlayer

var hand_base_pos: Vector3 = Vector3(0.0, -0.20, -0.18)
var mouse_input: Vector2 = Vector2.ZERO
var step_distance: float = 0.0
var step_interval: float = 1.85

var shovel_snow_mesh: MeshInstance3D
var shovel_spray_particles: CPUParticles3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.0
	_player_owner = int(get_instance_id())

	_setup_audio()
	_build_tools_visuals()
	_update_active_tool()

func _setup_audio() -> void:
	scrape_audio = AudioStreamPlayer3D.new()
	scrape_audio.volume_db = -2.0
	add_child(scrape_audio)

	step_audio = AudioStreamPlayer3D.new()
	step_audio.volume_db = -4.0
	add_child(step_audio)

	blower_audio = AudioStreamPlayer3D.new()
	blower_audio.stream = SoundEffectsScript.get_sound("snowblower")
	blower_audio.volume_db = -6.0
	add_child(blower_audio)

	wind_player = AudioStreamPlayer.new()
	wind_player.stream = SoundEffectsScript.get_sound("wind")
	wind_player.volume_db = -12.0
	add_child(wind_player)
	wind_player.play()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_switch_tool(wrapi(current_tool - 1, 0, 3) as ToolType)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_switch_tool(wrapi(current_tool + 1, 0, 3) as ToolType)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input = event.relative
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-75.0), deg_to_rad(80.0))

	if event.is_action_pressed("toggle_cursor"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("tool_1"):
		_switch_tool(ToolType.SHOVEL)
	elif event.is_action_pressed("tool_2"):
		_switch_tool(ToolType.BLOWER)
	elif event.is_action_pressed("tool_3"):
		_switch_tool(ToolType.SALT)

func _switch_tool(new_tool: ToolType) -> void:
	if current_tool == new_tool:
		return
	current_tool = new_tool
	_update_active_tool()

func _update_active_tool() -> void:
	_update_carry_visuals()

	if current_tool != ToolType.SHOVEL and shovel_spray_particles:
		shovel_spray_particles.emitting = false

	if blower_audio and blower_audio.playing:
		blower_audio.stop()

## Tools are stowed while the hands are busy: otherwise the shovel would clip
## through the ball being carried.
func _update_carry_visuals() -> void:
	var busy := carried != null
	if shovel_node:
		shovel_node.visible = (current_tool == ToolType.SHOVEL) and not busy
	if blower_node:
		blower_node.visible = (current_tool == ToolType.BLOWER) and not busy
	if salt_node:
		salt_node.visible = (current_tool == ToolType.SALT) and not busy

func _physics_process(delta: float) -> void:
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input_dir.y -= 1.0
	if Input.is_action_pressed("move_backward"): input_dir.y += 1.0
	if Input.is_action_pressed("move_left"): input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): input_dir.x += 1.0
	input_dir = input_dir.normalized()

	_update_carry_state(delta)

	var is_sprinting = Input.is_action_pressed("sprint")
	var target_speed = sprint_speed if is_sprinting else walk_speed

	# Real snow resistance against the blade.
	#   F = mu*N + cut_k*width*snow_h + M*a   -> the player brakes on his own,
	#   but gently: speed is lost, not the ability to advance.
	if current_tool == ToolType.SHOVEL and is_pushing and not is_carrying():
		var ratio := 1.0 / (1.0 + push_drag)
		if is_stuck:
			ratio = stuck_speed_factor
		target_speed *= ratio

	# Weight carried in the arms is felt, but with a floor: staggering costs
	# control, not speed (it must not feel slow).
	if is_carrying():
		var weight_factor := 1.0 / (1.0 + carried_mass / maxf(carry_weight_ref, 1.0))
		target_speed *= maxf(weight_factor, carry_speed_floor)

	var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var wants_move := input_dir.length_squared() > 0.01

	# Stagger from an oversized ball: lateral drift and less control.
	if stagger > 0.01:
		wish_dir += transform.basis.x * sin(_stagger_phase * 2.2) * 0.5 * stagger
		if wish_dir.length() > 0.01:
			wish_dir = wish_dir.normalized()

	_time += delta
	_refresh_surface()
	var move_speed: float = target_speed * surface_speed_scale
	# While the blade is actually working, the drag model already accounts for the
	# effort of moving snow. Piling the walking-surface penalty on top of it turns
	# shovelling into a crawl, so the surface only governs free movement.
	if current_tool == ToolType.SHOVEL and is_pushing:
		move_speed = target_speed
	_move_horizontal(wish_dir, move_speed, delta, wants_move)

	# Camera sway while staggering
	if camera:
		var wobble := sin(_stagger_phase * 2.6) * 0.11 * stagger
		camera.rotation.z = lerpf(camera.rotation.z, wobble, delta * 6.0)

	# Physical support height at the player position
	var target_snow_h = 0.0
	if snow_field:
		if snow_field.has_method("get_support_snow_height"):
			target_snow_h = snow_field.get_support_snow_height(global_position, 0.35)
		elif snow_field.has_method("get_snow_height"):
			target_snow_h = snow_field.get_snow_height(global_position)

	var sink_depth = 0.035 if target_snow_h > 0.08 else 0.0
	var raw_ground_y = maxf(target_snow_h - sink_depth, 0.0)

	if not is_ground_initialized:
		current_ground_y = raw_ground_y
		global_position.y = current_ground_y
		is_ground_initialized = true

	var dist_from_ground = global_position.y - current_ground_y
	# Jump input is buffered for a few frames so the hop rhythm is forgiving.
	if Input.is_action_just_pressed("jump") or (auto_bhop and Input.is_action_pressed("jump")):
		_jump_buffer = 0.12
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if not is_jumping and (absf(dist_from_ground) <= 0.12 or is_on_floor()):
		if _jump_buffer > 0.0:
			_start_jump()

	if is_jumping:
		velocity.y -= gravity * delta
		move_and_slide()
		if velocity.y <= 0.0 and global_position.y <= raw_ground_y:
			current_ground_y = raw_ground_y
			global_position.y = current_ground_y
			velocity.y = 0.0
			is_jumping = false
			is_grounded = true
			_on_land()
	else:
		velocity.y = 0.0
		move_and_slide()

		# DEADBAND FILTER: bumps under 8 cm do not change the player height;
		# real piles do (snowpack support).
		var elev_diff = raw_ground_y - current_ground_y
		if absf(elev_diff) > DEADBAND_THRESHOLD:
			current_ground_y = move_toward(current_ground_y, raw_ground_y, VERTICAL_TRANSITION_SPEED * delta)

		global_position.y = current_ground_y
		is_grounded = true

	camera.position.y = BASE_CAMERA_Y

	var horiz_speed = Vector2(velocity.x, velocity.z).length()
	if (is_on_floor() or is_grounded) and horiz_speed > 0.5:
		step_distance += horiz_speed * delta
		if step_distance >= step_interval:
			step_distance = 0.0
			_play_footstep()

	# Physical push on balls and props when colliding with them
	_push_touched_bodies(horiz_speed)

	match current_tool:
		ToolType.SHOVEL:
			_process_shovel(delta, horiz_speed)
		ToolType.BLOWER:
			_process_blower(delta)
		ToolType.SALT:
			_process_salt(delta)

	_process_interaction(delta)
	_update_carried(delta)
	_process_hand_sway(delta, horiz_speed)

## Reads the snow under the player and turns it into movement feel. Powder drags,
## packed snow and cleared ground let you keep the momentum.
func _refresh_surface() -> void:
	var surface := "snow"
	var speed_scale := 0.92
	var coast := 1.2
	var scrub := landing_scrub_snow
	var height := 0.0
	var cohesion := 0.5
	if snow_field:
		# Support height, not raw height: outside the simulated field the world
		# still has snow, and get_height_at reports -1 out there.
		if snow_field.has_method("get_support_snow_height"):
			height = maxf(snow_field.get_support_snow_height(global_position, 0.35), 0.0)
		elif snow_field.has_method("get_height_at"):
			height = maxf(snow_field.get_height_at(global_position), 0.0)
		if snow_field.has_method("get_cohesion_at"):
			cohesion = snow_field.get_cohesion_at(global_position)
		surface_height = height
		surface_cohesion = cohesion
		if snow_field.has_method("get_loose_fraction_at"):
			surface_loose = snow_field.get_loose_fraction_at(global_position)

		# Cohesion decides the surface, because it is the channel that working the
		# ground actually moves. Measured in the level: untouched dry snow sits
		# near 0.20 and a tamped strip near 0.57.
		if height < 0.03:
			surface = "cleared"
			speed_scale = 1.0
			coast = 0.35
			scrub = landing_scrub_packed
		elif cohesion >= 0.45:
			surface = "packed"
			speed_scale = 1.05
			coast = 0.25
			scrub = landing_scrub_packed
		elif cohesion >= 0.35:
			surface = "snow"
			speed_scale = 0.92
			coast = 1.2
			scrub = landing_scrub_snow
		else:
			# Dry unbonded snow: it cannot hold a wall and it swallows momentum.
			# Deliberately not harsher than this: virgin snow is the starting
			# state of every level and walking must never feel like a chore.
			surface = "powder"
			speed_scale = 0.75
			coast = 3.0
			scrub = landing_scrub_loose
	surface_name = surface
	surface_speed_scale = speed_scale
	surface_coast = coast
	surface_scrub = scrub

## Horizontal motion.
##
## On the ground the player accelerates toward the surface speed but is never
## braked down to it: above it, only the direction is steered and the momentum
## bleeds off with the surface coast. In the air nothing brakes at all, so air
## acceleration can build speed. That difference is what makes hopping work.
func _move_horizontal(wish_dir: Vector3, target_speed: float, delta: float, wants_move: bool) -> void:
	var control := 1.0 - 0.45 * stagger
	var speed_now := Vector2(velocity.x, velocity.z).length()
	var cap := sprint_speed * bhop_cap_factor

	if is_jumping:
		var air_accel := air_acceleration * air_control * control
		velocity.x += wish_dir.x * air_accel * delta
		velocity.z += wish_dir.z * air_accel * delta
	else:
		# The momentum is only scrubbed once the hop window has closed.
		if _pending_scrub and (_time - _landing_time) > bhop_window:
			_pending_scrub = false
			jump_chain = 0
			velocity.x *= surface_scrub
			velocity.z *= surface_scrub
			speed_now = Vector2(velocity.x, velocity.z).length()

		var approach := clampf(acceleration * control * delta, 0.0, 1.0)
		var want := Vector3(wish_dir.x, 0.0, wish_dir.z) * target_speed
		if not wants_move:
			var decay := exp(-surface_coast * delta)
			velocity.x *= decay
			velocity.z *= decay
		elif speed_now <= target_speed + 0.05:
			velocity.x = lerpf(velocity.x, want.x, approach)
			velocity.z = lerpf(velocity.z, want.z, approach)
		else:
			# Over the surface speed: keep the magnitude, steer the direction.
			var dir_now := Vector2(velocity.x, velocity.z).normalized()
			var dir_want := Vector2(want.x, want.z).normalized()
			var steered := dir_now.lerp(dir_want, clampf(approach * 0.6, 0.0, 1.0))
			if steered.length_squared() > 0.0001:
				steered = steered.normalized()
				velocity.x = steered.x * speed_now
				velocity.z = steered.y * speed_now
			var bleed := exp(-surface_coast * 0.3 * delta)
			velocity.x *= bleed
			velocity.z *= bleed

	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > cap:
		flat = flat.normalized() * cap
		velocity.x = flat.x
		velocity.z = flat.y
	horizontal_speed = flat.length()

## Launches the player. Landing and jumping again inside the hop window keeps (and
## slightly compounds) the momentum; a cold jump from standstill gets nothing.
func _start_jump() -> void:
	_jump_buffer = 0.0
	var chained := (_time - _landing_time) <= bhop_window
	var flat := Vector2(velocity.x, velocity.z)
	if chained:
		jump_chain += 1
		flat *= bhop_gain
	var cap := sprint_speed * bhop_cap_factor
	if flat.length() > cap:
		flat = flat.normalized() * cap
	velocity.x = flat.x
	velocity.z = flat.y
	velocity.y = jump_velocity
	is_jumping = true
	is_grounded = false
	_pending_scrub = false

	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_step()
	sfx.volume_db = -2.0
	sfx.pitch_scale = 0.88
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

## Touchdown: the clock starts for the hop window and the snow under the feet gets
## packed, which is why hopping in a line traces a usable path.
func _on_land() -> void:
	_landing_time = _time
	_pending_scrub = true
	if snow_field and snow_field.has_method("tamp"):
		snow_field.tamp(global_position, landing_pack_radius, landing_pack_strength)

func _play_footstep() -> void:
	var local_depth = 0.0
	if snow_field:
		if snow_field.has_method("get_snow_depth_at"):
			local_depth = snow_field.get_snow_depth_at(global_position)
		elif snow_field.has_method("get_snow_height"):
			local_depth = snow_field.get_snow_height(global_position)

	if local_depth > 0.05:
		step_audio.stream = SoundEffectsScript.get_snow_step()
		if snow_field and snow_field.has_method("stamp_footprint"):
			snow_field.stamp_footprint(global_position, 0.22, 0.06)
	else:
		step_audio.stream = SoundEffectsScript.get_concrete_step()

	step_audio.pitch_scale = randf_range(0.92, 1.08)
	step_audio.play()

func _get_target_ground_pos() -> Vector3:
	var cam_pos = camera.global_position
	var cam_dir = -camera.global_transform.basis.z

	if cam_dir.y < -0.05:
		var t = -cam_pos.y / cam_dir.y
		if t > 0.4 and t < 6.5:
			return cam_pos + cam_dir * t

	var forward_flat = Vector3(cam_dir.x, 0, cam_dir.z).normalized()
	return global_position + forward_flat * 1.4

func _forward_flat() -> Vector3:
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

# Shovel cycle: cut, load, resist, pour, tamp.
func _update_shovel_buttons(delta: float) -> void:
	var right_down := Input.is_action_pressed("shovel_toss") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if right_down:
		_right_hold += delta
		if is_carrying():
			# Throw the carried prop or ball
			if not _thrown_this_press:
				_thrown_this_press = true
				_throw_carried()
		elif _right_hold > TOSS_TAP_TIME and shovel_current_load > 0.05:
			is_dumping = true
	else:
		if _right_hold > 0.0 and _right_hold <= TOSS_TAP_TIME and shovel_current_load > 0.5 and not is_carrying():
			_perform_shovel_toss()   # short tap = parabolic toss
		_right_hold = 0.0
		is_dumping = false
		_thrown_this_press = false

func _process_shovel(delta: float, _horiz_speed: float) -> void:
	_update_shovel_buttons(delta)

	if is_tossing:
		toss_timer -= delta
		if toss_timer <= 0.0:
			is_tossing = false
		return
	if is_tamping:
		tamp_timer -= delta
		if tamp_timer <= 0.0:
			is_tamping = false
		return
	if is_dumping:
		is_pushing = false
		prev_scoop_pos = Vector3.INF
		_pour_shovel_load(delta)
		return

	var push_pressed = Input.is_action_pressed("shovel_push") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if is_carrying():
		push_pressed = false
	is_pushing = push_pressed and not is_tamping

	if is_pushing and snow_field:
		var forward_flat := _forward_flat()

		# Attack angle: aimed at the ground the blade bites the whole layer; held
		# flat it works like a chisel and lifts thin sheets (free sculpting).
		var pitch := -camera.rotation.x
		bite_factor = clampf((pitch - 0.10) / 0.85, 0.0, 1.0)
		var max_cut: float = 0.0
		if bite_factor < 0.55:
			max_cut = 0.02 + 0.06 * (bite_factor / 0.55)

		var scoop_pt = global_position + forward_flat * 1.05
		scoop_pt.y = 0.0

		# Frontal resistance (physical readout for the HUD and the jam decision)
		blade_snow_height = 0.0
		if snow_field.has_method("get_height_at"):
			blade_snow_height = maxf(snow_field.get_height_at(scoop_pt + forward_flat * 0.25), 0.0)
		var bite := 0.35 + 0.65 * bite_factor
		snow_resistance = cut_resistance_per_m * 0.76 * blade_snow_height * bite \
			+ 9.81 * shovel_current_load * load_resistance_factor
		# Advance penalty: SOFT and bounded by design. Resistance must be felt
		# (snow is heavy) but never turn walking into crawling:
		#   empty shovel in fresh snow -> ~80% of speed
		#   full shovel (25 kg)        -> ~60%
		# Only a pile taller than the blade really jams the shovel.
		push_drag = plow_drag_per_m * blade_snow_height * bite + load_drag_per_kg * shovel_current_load
		is_stuck = blade_snow_height > stuck_height_m or snow_resistance > stuck_resistance

		var kg_cut = 0.0
		if prev_scoop_pos != Vector3.INF and prev_scoop_pos.distance_squared_to(scoop_pt) > 0.005:
			var dist_travel = prev_scoop_pos.distance_to(scoop_pt)
			var steps = clampi(int(dist_travel / 0.08) + 1, 1, 4)
			for step_i in range(steps):
				var lerp_pt = prev_scoop_pos.lerp(scoop_pt, float(step_i + 1) / float(steps))
				kg_cut += snow_field.carve_shovel(lerp_pt, forward_flat, 0.76, 0.30, max_cut)
		else:
			kg_cut = snow_field.carve_shovel(scoop_pt, forward_flat, 0.76, 0.30, max_cut)

		prev_scoop_pos = scoop_pt

		if kg_cut > 0.0:
			if shovel_spray_particles and not shovel_spray_particles.emitting:
				shovel_spray_particles.emitting = true
			if shovel_current_load < shovel_capacity_max:
				# Fill rate limited: the shovel does not fill in one hit
				var added := minf(kg_cut * 0.4, fill_rate * delta + 0.35)
				shovel_current_load = minf(shovel_current_load + added, shovel_capacity_max)
				_update_shovel_snow_visual()

			if randf() < 0.28:
				var clump = SnowChunkScript.new()
				clump.kg_weight = randf_range(0.6, 1.8)
				clump.snow_field = snow_field
				clump.is_toss = false
				get_parent().add_child(clump)
				var side_mult = -1.0 if randf() < 0.5 else 1.0
				var right_dir = camera.global_transform.basis.x
				var scoop_edge_origin = scoop_pt + right_dir * (side_mult * 0.38) + Vector3(0, 0.15, 0)
				clump.global_position = scoop_edge_origin
				var roll_vel = (right_dir * (side_mult * 0.8) + forward_flat * 0.35 + Vector3(0, 0.45, 0)).normalized()
				clump.linear_velocity = roll_vel * randf_range(2.0, 3.5)

			if not scrape_audio.playing:
				scrape_audio.stream = SoundEffectsScript.get_shovel_scrape()
				scrape_audio.pitch_scale = randf_range(0.95, 1.05)
				scrape_audio.play()
		else:
			if shovel_spray_particles and shovel_spray_particles.emitting:
				shovel_spray_particles.emitting = false
			if scrape_audio.playing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				scrape_audio.stop()
	else:
		prev_scoop_pos = Vector3.INF
		snow_resistance = 0.0
		is_stuck = false
		if shovel_spray_particles and shovel_spray_particles.emitting:
			shovel_spray_particles.emitting = false
		if scrape_audio.playing:
			scrape_audio.stop()

	# Tamping / flattening with the flat face
	if Input.is_action_just_pressed("shovel_tamp") and not is_carrying():
		_perform_tamp()

## Gradual pour: the shovel tilts and snow falls in a continuous stream under
## the blade, transferring its mass to the terrain in real time.
func _pour_shovel_load(delta: float) -> void:
	if shovel_current_load <= 0.05:
		is_dumping = false
		return
	if snow_field == null or not snow_field.has_method("dump_snow"):
		return
	var kg := minf(dump_rate * delta, shovel_current_load)
	var forward_flat := _forward_flat()
	var pour_pt := global_position + forward_flat * 0.62
	if snow_field.has_method("get_height_at"):
		pour_pt.y = maxf(snow_field.get_height_at(pour_pt), 0.0)
	snow_field.dump_snow(pour_pt, kg, 0.26)
	shovel_current_load = maxf(shovel_current_load - kg, 0.0)
	_pour_ops += 1
	if debug_shovel and _pour_ops <= 6:
		print("[SHOVEL] pour #%d  kg=%.3f  point=%s  height=%.3f" % [
			_pour_ops, kg, str(pour_pt), snow_field.get_height_at(pour_pt)])
	_update_shovel_snow_visual()
	if shovel_spray_particles and not shovel_spray_particles.emitting:
		shovel_spray_particles.emitting = true

func _perform_shovel_toss() -> void:
	is_tossing = true
	toss_timer = 0.45

	var sfx = AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_swish()
	sfx.volume_db = -1.0
	sfx.pitch_scale = randf_range(0.9, 1.1)
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	var launch_count = clampi(int(shovel_current_load * 0.25) + 2, 2, 5)
	var kg_per_chunk = shovel_current_load / float(launch_count)

	for i in range(launch_count):
		var chunk = SnowChunkScript.new()
		chunk.kg_weight = kg_per_chunk
		chunk.snow_field = snow_field
		chunk.is_toss = true
		get_parent().add_child(chunk)

		var spawn_pos = camera.global_position + (-camera.global_transform.basis.z * 0.8) + (camera.global_transform.basis.x * randf_range(-0.2, 0.2))
		chunk.global_position = spawn_pos

		var launch_dir = (-camera.global_transform.basis.z + Vector3(0, 0.45, 0)).normalized()
		launch_dir += Vector3(randf_range(-0.15, 0.15), randf_range(-0.05, 0.1), randf_range(-0.15, 0.15))
		chunk.linear_velocity = launch_dir * randf_range(8.5, 12.0)

	shovel_current_load = 0.0
	_update_shovel_snow_visual()

## Tamp: hit the snow with the flat face to flatten and pack it.
func _perform_tamp() -> void:
	is_tamping = true
	tamp_timer = 0.32
	is_dumping = false
	var target := _get_target_ground_pos()
	if snow_field and snow_field.has_method("tamp"):
		snow_field.tamp(target, tamp_radius, 1.0)
	var sfx = AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_thud()
	sfx.volume_db = -3.0
	sfx.pitch_scale = randf_range(0.75, 0.9)
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

# Blower tool.
func _process_blower(_delta: float) -> void:
	var active = Input.is_action_pressed("shovel_push") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if active and snow_field and not is_carrying():
		if not blower_audio.playing:
			blower_audio.play()

		var target_pt = _get_target_ground_pos()
		var forward_flat = _forward_flat()

		var kg_blown = snow_field.carve(target_pt, 1.05, 0.40, forward_flat)

		if kg_blown > 0.0 and randf() < 0.3:
			var chunk = SnowChunkScript.new()
			chunk.kg_weight = kg_blown * 0.3
			chunk.snow_field = snow_field
			get_parent().add_child(chunk)

			var chute_dir = (camera.global_transform.basis.x * 0.8 + Vector3(0, 0.55, 0) - camera.global_transform.basis.z * 0.3).normalized()
			chunk.global_position = camera.global_position + chute_dir * 0.7
			chunk.linear_velocity = chute_dir * randf_range(9.0, 13.0)
	else:
		if blower_audio.playing:
			blower_audio.stop()

# Salt tool.
func _process_salt(_delta: float) -> void:
	var salt_pressed = Input.is_action_just_pressed("shovel_push") or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_pushing)
	is_pushing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_carrying()

	if salt_pressed and snow_field and not is_carrying():
		var sfx = AudioStreamPlayer3D.new()
		sfx.stream = SoundEffectsScript.get_sound("salt_shake")
		sfx.pitch_scale = randf_range(0.9, 1.1)
		add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)

		var target_pt = _get_target_ground_pos()
		# Salt breaks cohesion: treated snow flows like dry sand
		snow_field.carve(target_pt, 1.6, 0.50, Vector3.ZERO, true)

# Ball packing, prop pickup, stacking and pinning.
func is_carrying() -> bool:
	return carried != null

func _process_interaction(delta: float) -> void:
	if snow_field and snow_field.has_signal("op_volume_ready") and not snow_field.op_volume_ready.is_connected(_on_op_volume_ready):
		snow_field.op_volume_ready.connect(_on_op_volume_ready)

	# [E] has three behaviors depending on how it is used:
	#   short tap on something -> pick it up / extract it
	#   tap on snow            -> pack a ball by hand
	#   HOLD on a ball         -> push it along the ground (it is not lifted)
	var pressed := Input.is_action_pressed("interact")
	if pressed:
		if not _interact_was_pressed:
			_interact_was_pressed = true
			_interact_hold = 0.0
			_pushed_during_hold = false
			if is_carrying():
				_release_carried(Vector3.ZERO)
			elif not _has_interactable_ahead():
				_try_pickup_or_pack()
		_interact_hold += delta
		if _interact_hold >= interact_hold_time and not is_carrying():
			_pushed_during_hold = _ground_push() or _pushed_during_hold
		return

	if _interact_was_pressed:
		_interact_was_pressed = false
		# Short tap in front of a ball or prop: pick it up
		if not is_carrying() and not _pushed_during_hold and _interact_hold < interact_hold_time:
			_try_pickup_or_pack()
	_interact_hold = 0.0
	_pushed_during_hold = false
	_push_target = null
	is_ground_pushing = false

## Is there a pickable ball or prop right in front?
func _has_interactable_ahead() -> bool:
	var hit := _raycast_interactable()
	if hit.is_empty():
		return false
	var col = hit.get("collider")
	return col != null and (col is SnowBall or col is PinProp) and col.has_method("begin_carry")

## Continuous push with held [E]: the ball rolls on the ground in front of the
## player and is never lifted (it stays a dynamic body resting on the
## snowpack). Bounded force: the heavier it is, the harder it is to move.
func _ground_push() -> bool:
	if _push_target == null or not is_instance_valid(_push_target):
		var hit := _raycast_interactable()
		var col = hit.get("collider") if not hit.is_empty() else null
		if col != null and (col is SnowBall or col is PinProp) and col.has_method("push"):
			_push_target = col
		else:
			_push_target = null
			is_ground_pushing = false
			return false
	_push_target.push(global_position, ground_push_strength)
	is_ground_pushing = true
	return true

func _try_pickup_or_pack() -> void:
	var hit := _raycast_interactable()
	if not hit.is_empty():
		var col = hit.get("collider")
		if col is PinProp and col.is_pinned:
			col.try_extract()
			if col.has_method("begin_carry"):
				_begin_carry(col)
			return
		if col != null and col.has_method("begin_carry"):
			_begin_carry(col)
			return
	# With nothing to pick up, snow is packed by hand
	_pack_snowball()

func _raycast_interactable() -> Dictionary:
	if camera == null:
		return {}
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * interact_distance
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	return space.intersect_ray(q)

func _begin_carry(body: RigidBody3D) -> void:
	if carried != null and is_instance_valid(carried) and carried != body:
		# Never leave a prop frozen in mid-air when switching loads
		_release_carried(Vector3.ZERO)
	carried = body
	_carried_prev_pos = body.global_position
	carried_velocity = Vector3.ZERO
	body.begin_carry()
	_update_carry_visuals()

func _release_carried(impulse: Vector3) -> void:
	if carried == null:
		return
	var body := carried
	carried = null
	body.end_carry(impulse)
	carried_mass = 0.0
	carry_two_hands = false
	stagger = 0.0
	_update_carry_visuals()

## Weight carried in the hands and what it implies: past a certain size the
## ball is held with BOTH hands above the head and the player starts to
## stagger until it slips out.
func _update_carry_state(delta: float) -> void:
	carried_mass = 0.0
	if carried != null and is_instance_valid(carried):
		carried_mass = _carried_mass(carried)
	var wants_two_hands := carried_mass >= two_hands_mass and carried != null
	if wants_two_hands != carry_two_hands:
		carry_two_hands = wants_two_hands
		_update_carry_visuals()
	_stagger_phase += delta
	if carry_two_hands:
		var span := maxf(stagger_full_mass - two_hands_mass, 1.0)
		stagger = clampf((carried_mass - two_hands_mass) / span, 0.0, 1.0)
		grip_left = maxf(grip_left - delta * (grip_drain_base + grip_drain_stagger * stagger), 0.0)
		if grip_left <= 0.0:
			status_message = "The ball slipped out of your hands!"
			_release_carried(Vector3.ZERO)
			grip_left = 0.30   # room to try again
			stagger = 0.0
	else:
		stagger = 0.0
		grip_left = minf(grip_left + delta * 0.35, 1.0)

func _carried_mass(body: RigidBody3D) -> float:
	if body is SnowBall:
		return (body as SnowBall).packed_mass()
	return maxf(body.mass, 1.0)

func _throw_carried() -> void:
	if carried == null:
		return
	var speed := _throw_speed_for(carried_mass, carry_two_hands)
	var dir := -camera.global_transform.basis.z
	# One-handed the throw is flat; two-handed it is a heave with more arc, which
	# is what lets a large ball be passed to another person.
	var lift := 0.65 if carry_two_hands else 0.45
	var impulse := dir * speed + Vector3.UP * (speed * lift)
	# The impulse inherits the hand motion so the throw feels natural
	impulse += carried_velocity * 0.35
	_release_carried(impulse)
	grip_left = maxf(grip_left, 0.35)

## Launch speed of a throw. Falls with mass in a SOFTENED way (exponent 0.30
## instead of the 0.5 of constant energy) so large balls remain throwable with
## force, and two-handed throws get a bonus. It never exceeds the light-ball
## speed: weight always costs.
func _throw_speed_for(mass_kg: float, two_hands: bool) -> float:
	var m := maxf(mass_kg, 0.2)
	var v := throw_ref_speed * pow(throw_ref_mass / m, throw_mass_exponent)
	if two_hands:
		v *= two_hands_throw_boost
	return minf(v, throw_ref_speed)

func _update_carried(delta: float) -> void:
	if carried == null:
		return
	if not is_instance_valid(carried):
		carried = null
		return
	var anchor := _carry_anchor(_carried_radius())
	carried.carry_to(anchor, delta)
	# Hand velocity, clamped and smoothed: while picking something up the lerp
	# spikes hard and, inherited by the throw, would launch the ball.
	var instant := (carried.global_position - _carried_prev_pos) / maxf(delta, 0.001)
	instant = instant.limit_length(walk_speed * 1.4)
	carried_velocity = carried_velocity.lerp(instant, clampf(delta * 12.0, 0.0, 1.0))
	_carried_prev_pos = carried.global_position

## Packs snow by hand: the mass comes from the snowpack and forms a real ball
## whose radius depends on the exact volume removed.
func _pack_snowball() -> void:
	if _pending_pack or snow_field == null or not snow_field.has_method("request_harvest"):
		return
	var pt := _get_target_ground_pos()
	var h := 0.0
	if snow_field.has_method("get_height_at"):
		h = snow_field.get_height_at(pt)
	if h < 0.05:
		status_message = "Not enough snow to pack"
		return
	_pending_pack = true
	var depth := minf(0.10, maxf(h * 0.45, 0.03))
	snow_field.request_harvest(_player_owner, pt, pt + Vector3(0.03, 0.0, 0.03), 0.20, depth)
	status_message = "Packing snow..."

func _on_op_volume_ready(role: String, owner: int, kg: float) -> void:
	if role != "harvest" or owner != _player_owner:
		return
	if not _pending_pack:
		return
	_pending_pack = false
	if kg < pack_min_kg:
		status_message = "Not enough snow to pack"
		return
	var r := pow(maxf(3.0 * kg / (4.0 * PI * PACKED_DENSITY), 1e-6), 1.0 / 3.0)
	r = clampf(r, 0.08, 0.22)
	if props_system == null or not props_system.has_method("spawn_snowball"):
		return
	# The packed snow is born ALREADY IN THE HANDS: it is instanced at the grip
	# point and put in carry mode instead of being dropped on the ground.
	var anchor := _carry_anchor(r)
	var ball = props_system.spawn_snowball(anchor, r)
	if ball == null:
		return
	if is_carrying():
		# Already carrying something (rare case): the ball drops at your feet instead of being lost
		ball.global_position = global_position + _forward_flat() * 0.7 + Vector3.UP * (r + 0.05)
		status_message = "Snowball on the ground: %.1f kg" % ball.packed_mass()
	else:
		_begin_carry(ball)
		status_message = "Snowball in hands: %.1f kg" % ball.packed_mass()
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_thud()
	sfx.volume_db = -6.0
	sfx.pitch_scale = 1.2
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

## Grip point in front of the camera.
## - One hand: follows the VIEW (held in front and follows pitch, like an object
##   in the hand: farther out the bigger the ball is).
## - Two hands: anchored to the BODY (player yaw and world up), because a ball
##   above the head must not sink into the ground when looking down.
func _carry_anchor(object_radius: float = -1.0) -> Vector3:
	var r: float = object_radius if object_radius > 0.0 else 0.12
	if carry_two_hands:
		var body_fwd := -transform.basis.z
		body_fwd.y = 0.0
		if body_fwd.length_squared() < 0.01:
			body_fwd = Vector3.FORWARD
		body_fwd = body_fwd.normalized()
		var lift := 0.16 + r * 1.15
		var push := 0.22 + r * 0.45
		return camera.global_position + body_fwd * push + Vector3.UP * lift
	var fwd := -camera.global_transform.basis.z
	var dist := carry_distance
	var drop := 0.25
	var side := 0.0
	if object_radius > 0.0:
		dist = carry_distance * 0.5 + object_radius * 1.4
		drop = 0.16 + object_radius * 0.5
		side = clampf(0.26 - object_radius * 0.25, 0.08, 0.26)
	return camera.global_position + fwd * dist \
		- Vector3.UP * drop + camera.global_transform.basis.x * side

## Approximate radius of the carried object (to place it in the hand).
func _carried_radius() -> float:
	if carried == null:
		return -1.0
	if carried is SnowBall:
		return (carried as SnowBall).radius
	return 0.12

## Physical push when the body collides with balls and props (rolling, dragging).
func _push_touched_bodies(horiz_speed: float) -> void:
	var strength := PUSH_ACCEL * clampf(horiz_speed / walk_speed, 0.0, 1.6)
	if strength <= 0.01:
		return
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		var other = c.get_collider()
		if other == null or other == self:
			continue
		if (other is SnowBall or other is PinProp) and other.has_method("push"):
			other.push(global_position, strength)

# Hand sway and position.
func _process_hand_sway(delta: float, horiz_speed: float) -> void:
	var target_pos = hand_base_pos
	var target_rot = Vector3.ZERO

	if current_tool == ToolType.SHOVEL:
		if is_tossing:
			var toss_factor = sin((0.45 - toss_timer) / 0.45 * PI)
			target_pos += Vector3(0.05, 0.28 * toss_factor, 0.15)
			target_rot.x += deg_to_rad(35.0 * toss_factor)
		elif is_tamping:
			var slam = sin((0.32 - tamp_timer) / 0.32 * PI)
			target_pos += Vector3(0.02, -0.22 * slam, -0.12 * slam)
			target_rot.x -= deg_to_rad(38.0 * slam)
		elif is_dumping:
			# The blade tilts down to pour
			target_pos += Vector3(0.02, -0.05, -0.05)
			target_rot.x += deg_to_rad(52.0)
		elif is_pushing:
			target_pos += Vector3(-0.04, -0.14, -0.06)
			target_rot.x -= deg_to_rad(14.0)

	# With a large ball in the arms the hands rise above the head
	if is_carrying():
		var lift := 0.55 if carry_two_hands else 0.22
		target_pos += Vector3(0.0, lift, 0.10)
		target_rot.x -= deg_to_rad(18.0)
		if stagger > 0.01:
			# The arms swing with the stagger
			target_pos.x += sin(_stagger_phase * 2.6) * 0.05 * stagger
			target_pos.y += cos(_stagger_phase * 3.1) * 0.03 * stagger

	if is_on_floor() and horiz_speed > 0.2:
		var bob_t = Time.get_ticks_msec() * 0.008 * (horiz_speed / walk_speed)
		target_pos.y += sin(bob_t) * 0.02
		target_pos.x += cos(bob_t * 0.5) * 0.015

	target_pos.x -= mouse_input.x * 0.0003
	target_pos.y += mouse_input.y * 0.0003
	mouse_input = Vector2.ZERO

	hand_root.position = hand_root.position.lerp(target_pos, delta * 14.0)
	hand_root.rotation.x = lerp_angle(hand_root.rotation.x, target_rot.x, delta * 15.0)

# 3D model loading.
func _build_tools_visuals() -> void:
	_load_shovel_model()
	_build_blower_mesh()
	_build_salt_mesh()
	# No viewmodel part casts a shadow (avoids spikes and blotches)
	_disable_viewmodel_shadows(hand_root)

## The first-person model must NOT cast a shadow: its plates are very thin and
## with a low sun the shadow stretches into a blue needle over the snow (a very
## visible artifact while picking up). Standard practice for viewmodels.
func _disable_viewmodel_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_viewmodel_shadows(child)

func _load_shovel_model() -> void:
	var shovel_scene = load("res://assets/models/first_person_shovel.glb")
	if shovel_scene:
		var model = shovel_scene.instantiate()
		model.position = Vector3(0.22, -0.18, -0.22)
		model.rotation = Vector3(deg_to_rad(2.0), deg_to_rad(-8.0), deg_to_rad(4.0))
		shovel_node.add_child(model)

	shovel_snow_mesh = MeshInstance3D.new()
	var snow_sphere = SphereMesh.new()
	snow_sphere.radius = 0.20
	snow_sphere.height = 0.12
	snow_sphere.radial_segments = 12
	snow_sphere.rings = 8
	shovel_snow_mesh.mesh = snow_sphere
	shovel_snow_mesh.position = Vector3(0.12, -0.46, -1.02)
	shovel_snow_mesh.rotation = Vector3(deg_to_rad(2.0), deg_to_rad(-8.0), deg_to_rad(4.0))
	shovel_snow_mesh.scale = Vector3(1.1, 0.55, 0.95)

	var snow_mat = StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.93, 0.96, 1.0)
	snow_mat.roughness = 0.55
	snow_mat.rim_enabled = true
	snow_mat.rim = 0.60
	snow_mat.rim_tint = 0.35
	shovel_snow_mesh.material_override = snow_mat
	shovel_snow_mesh.visible = false
	shovel_node.add_child(shovel_snow_mesh)

	shovel_spray_particles = CPUParticles3D.new()
	shovel_spray_particles.emitting = false
	shovel_spray_particles.amount = 45
	shovel_spray_particles.lifetime = 0.45
	shovel_spray_particles.position = Vector3(0.10, -0.48, -1.10)
	shovel_spray_particles.direction = Vector3(-0.10, 0.45, -0.95)
	shovel_spray_particles.spread = 38.0
	shovel_spray_particles.initial_velocity_min = 2.2
	shovel_spray_particles.initial_velocity_max = 3.8
	shovel_spray_particles.gravity = Vector3(0.0, -7.0, 0.0)

	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	p_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.95)
	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(0.045, 0.045, 0.045)
	p_mesh.material = p_mat
	shovel_spray_particles.mesh = p_mesh
	shovel_node.add_child(shovel_spray_particles)

func _update_shovel_snow_visual() -> void:
	if shovel_snow_mesh:
		var pct = shovel_current_load / shovel_capacity_max
		if pct > 0.05:
			shovel_snow_mesh.visible = true
			shovel_snow_mesh.scale = Vector3(1.2 * clampf(pct * 1.2, 0.3, 1.2), clampf(pct * 1.4, 0.2, 1.4), clampf(pct * 1.2, 0.3, 1.3))
		else:
			shovel_snow_mesh.visible = false

func _build_blower_mesh() -> void:
	var body = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.55, 0.38, 0.48)
	body.mesh = box
	body.position = Vector3(0, -0.3, -0.6)
	var yellow_mat = StandardMaterial3D.new()
	yellow_mat.albedo_color = Color(0.92, 0.72, 0.15)
	yellow_mat.roughness = 0.5
	body.material_override = yellow_mat
	blower_node.add_child(body)

	var chute = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 0.42
	chute.mesh = cyl
	chute.position = Vector3(0.18, -0.04, -0.6)
	chute.rotation.z = deg_to_rad(-35.0)
	var dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.2, 0.2, 0.2)
	chute.material_override = dark_mat
	blower_node.add_child(chute)

func _build_salt_mesh() -> void:
	var shaker = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.14
	cyl.height = 0.42
	shaker.mesh = cyl
	shaker.position = Vector3(0, -0.22, -0.5)
	shaker.rotation.x = deg_to_rad(20.0)
	var blue_mat = StandardMaterial3D.new()
	blue_mat.albedo_color = Color(0.18, 0.55, 0.88)
	shaker.material_override = blue_mat
	salt_node.add_child(shaker)
