extends CharacterBody3D

const SessionModeScript = preload("res://scripts/session_mode.gd")
const SettingsSystemScript = preload("res://scripts/settings_system.gd")
## Controller look: speed at full deflection, and how far the stick must move first.
const STICK_LOOK_SPEED: float = 2.4
const STICK_DEADZONE: float = 0.18
const SnowChunkScript = preload("res://scripts/snow_chunk.gd")
const SoundEffectsScript = preload("res://scripts/sound_effects.gd")
const SnowBallScript = preload("res://scripts/snowball.gd")
const PinPropScript = preload("res://scripts/pin_prop.gd")

@export var mouse_sensitivity: float = 0.0025
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 6.8
# Movement: Quake-style ground friction and air acceleration.
#
# The model is the one every proven implementation uses (Quake III bg_pmove.c,
# QuakeWorld, Source):
#   ground  friction is applied every frame, then the player accelerates toward
#           the wish speed. Ground movement is therefore crisp and capped.
#   air     no friction at all, and the wish speed is clamped small, so the only
#           way to gain speed is to point the wish direction sideways and let the
#           acceleration rotate the velocity vector.
#   jump    vertical only. The reward for hopping is skipping ground friction,
#           not a speed bonus, so a player who walks and hops gains nothing.
# Net effect: normal walking is normal, and chaining hops is a skill.
## Ground acceleration, in Quake's form: accel * wishspeed * delta.
@export var ground_accelerate: float = 12.0
## Air acceleration. Quake's vanilla 1.0 is sluggish; this is a clan-arena value
## that makes a good strafe actually pay.
@export var air_accelerate: float = 12.0
## Clamp on the air wish speed (m/s). This small number is the whole trick: it
## caps how much speed the air can add along the wish direction.
@export var air_wish_speed: float = 1.0
## Ground friction. Higher stops the player faster. Tuned against the ground
## acceleration: friction must never overpower acceleration at walking speed.
@export var ground_friction: float = 5.0
## Friction treats any speed below this as this value, so the player stops
## cleanly instead of sliding for ever.
@export var ground_stop_speed: float = 1.5
## Safety rail on the hop, relative to the sprint speed. With the clamped air
## model, holding forward can never reach it.
@export var bhop_cap_factor: float = 2.0
## Landing compacts the snow it hits, which is how hopping packs a trail.
@export var landing_pack_strength: float = 0.18
@export var landing_pack_radius: float = 0.38
## Holding jump hops again on landing. Off by default: timing is the skill, and
## this is the accessibility assist for players who do not want to learn it.
@export var auto_bhop: bool = false
## Auto-hop only engages above this speed, so holding jump from a standstill
## cannot trap the player in a crawl (in the air the model only grants ~1 m/s).
@export var auto_bhop_min_speed: float = 2.0
@export var jump_velocity: float = 5.2
@export var gravity: float = 18.0
## A jump after landing inside this window counts as a chain, for stats only.
@export var chain_window: float = 0.25

# Being hit by snowballs. Reactions are on by default; the "work" session mode
# is meant to turn them off for players who just want to clear snow.
enum HitState { NORMAL = 0, STAGGERED = 1, KNOCKED_DOWN = 2 }
@export var hit_reactions_enabled: bool = true
## Face snow clears itself. Off is the "realistic" setting: you must wipe it off.
@export var snow_face_auto_clear: bool = true
@export var face_snow_time: float = 3.5
## Holding interact wipes the face this fast. Always available: wiping is quicker
## than waiting, in both settings.
@export var face_wipe_time: float = 0.6
@export var stagger_time: float = 1.0
@export var knockdown_time: float = 2.0
## Grace period after a reaction ends, so hits can never be chained into a lock.
@export var hit_immunity_time: float = 1.5
## Radius of the head sphere: a hit inside it counts as a hit to the face.
## Covers the player's 0.40 m capsule radius with enough lead margin to catch incoming balls in flight.
@export var head_hit_radius: float = 0.55

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
const PACK_MIN_KG: float = 0.435
const PACK_REACH_STRICT: float = 1.3
const PACK_REACH_EXTENDED: float = 2.4
const PACK_HARVEST_RADIUS: float = 0.22
const PACK_HARVEST_DEPTH: float = 0.10
@export var pack_min_kg: float = PACK_MIN_KG
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
@export_range(0.3, 1.0) var carry_speed_floor: float = 0.80
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

var snow_field: Node3D:
	set(value):
		snow_field = value
		_connect_snow_field()
var props_system: Node3D

enum ToolType { SHOVEL = 0, BLOWER = 1, SALT = 2, HANDS = 3 }
var current_tool: ToolType = ToolType.HANDS

## Reticle states: OFF (no snow / out of reach), CAN_PACK (snow packable by hand), CAN_CARVE (snow carveable with tool).
enum ReticleState {
	OFF = 0,
	CAN_PACK = 1,
	CAN_CARVE = 2,
}
var reticle_state: ReticleState = ReticleState.OFF
var reticle_aim_pt: Vector3 = Vector3.INF
var reticle_has_hit: bool = false
var reticle_reach: float = 2.4

var _owned_tools: Array[String] = ["hands"]

signal coins_changed(new_coins: int)

var coins: int:
	get:
		if SaveSystem.current_slot >= 0:
			return int(SaveSystem.data.get("coins", 0))
		return _coins
	set(value):
		_coins = value
		if SaveSystem.current_slot >= 0:
			SaveSystem.data["coins"] = value
			SaveSystem.save_current()
		coins_changed.emit(_coins)

var _coins: int = 0

func add_coins(amount: int) -> void:
	coins = coins + amount

func is_tool_owned(tool) -> bool:
	var tname := SaveSystem.normalize_tool_name(tool)
	if tname == "hands":
		return true
	if SaveSystem.current_slot >= 0:
		return SaveSystem.is_tool_owned(tool)
	return _owned_tools.has(tname)

func grant_tool(tool) -> void:
	var tname := SaveSystem.normalize_tool_name(tool)
	if not _owned_tools.has(tname):
		_owned_tools.append(tname)
	if SaveSystem.current_slot >= 0:
		SaveSystem.grant_tool(tool)

func grant_all_tools() -> void:
	grant_tool(ToolType.HANDS)
	grant_tool(ToolType.SHOVEL)
	grant_tool(ToolType.BLOWER)
	grant_tool(ToolType.SALT)

func can_afford(tool) -> bool:
	return SaveSystem.can_afford(tool)

func price(tool) -> int:
	return SaveSystem.price(tool)

func purchase(tool) -> bool:
	var tname := SaveSystem.normalize_tool_name(tool)
	if is_tool_owned(tname):
		return true
	var ok := SaveSystem.purchase(tool)
	if ok:
		if not _owned_tools.has(tname):
			_owned_tools.append(tname)
	return ok

func equip_tool(tool) -> bool:
	var t: ToolType = ToolType.HANDS
	if tool is int:
		t = tool as ToolType
	else:
		match str(tool).to_lower().strip_edges():
			"shovel": t = ToolType.SHOVEL
			"blower": t = ToolType.BLOWER
			"salt": t = ToolType.SALT
			"hands": t = ToolType.HANDS
	if not is_tool_owned(t):
		return false
	_switch_tool(t)
	return true

const TOOL_CYCLE_ORDER: Array[ToolType] = [
	ToolType.HANDS,
	ToolType.SHOVEL,
	ToolType.BLOWER,
	ToolType.SALT,
]

func get_owned_tools() -> Array[ToolType]:
	var owned: Array[ToolType] = []
	for t in TOOL_CYCLE_ORDER:
		if is_tool_owned(t):
			owned.append(t)
	return owned

func cycle_tool_next() -> void:
	var owned := get_owned_tools()
	if owned.is_empty():
		_switch_tool(ToolType.HANDS)
		return
	var idx := owned.find(current_tool)
	if idx < 0:
		_switch_tool(owned[0])
	else:
		var next_idx := (idx + 1) % owned.size()
		_switch_tool(owned[next_idx])

func cycle_tool_prev() -> void:
	var owned := get_owned_tools()
	if owned.is_empty():
		_switch_tool(ToolType.HANDS)
		return
	var idx := owned.find(current_tool)
	if idx < 0:
		_switch_tool(owned[0])
	else:
		var prev_idx := (idx - 1 + owned.size()) % owned.size()
		_switch_tool(owned[prev_idx])

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

# Movement state: surface profile, hop chain and jump buffering.
## Surface the player is standing on, refreshed every physics step.
var surface_name: String = "snow"
## Speed multiplier of the current surface (powder is slow, packed is fast).
var surface_speed_scale: float = 1.0
## Friction multiplier of the current surface: how hard it holds the player.
var surface_friction: float = 1.0
## Raw readings behind the surface decision, for the HUD and diagnostics.
var surface_height: float = 0.0
var surface_cohesion: float = 0.0
var surface_loose: float = 0.0
## Consecutive hops, reset when the chain window closes.
var jump_chain: int = 0
## Current horizontal speed (m/s).
var horizontal_speed: float = 0.0
var _time: float = 0.0
var _landing_time: float = -99.0
var _jump_buffer: float = 0.0
# Hit reactions: state, face snow and the counters the diagnostic battery reads.
var hit_state: int = HitState.NORMAL
var hit_state_timer: float = 0.0
var hit_immunity: float = 0.0
## 0..1 snow across the face. Drives the HUD overlay.
var face_snow_amount: float = 0.0
var face_snow_timer: float = 0.0
var hits_taken: int = 0
var last_hit_tier: int = -1
var last_hit_was_head: bool = false
var _wipe_progress: float = 0.0
var _hit_shake: float = 0.0
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
var pushed_mass: float = 0.0
var _interact_hold: float = 0.0
var _interact_was_pressed: bool = false
var _pushed_during_hold: bool = false
var _push_target: RigidBody3D = null
var _right_hold: float = 0.0
var _thrown_this_press: bool = false
var _player_owner: int = 0
var _pending_pack: bool = false
var _pending_pack_time: float = 0.0
var _pack_harvest_pt: Vector3 = Vector3.ZERO
var last_pack_harvest_kg: float = 0.0
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
	if pack_min_kg < SnowBall.min_pack_mass():
		pack_min_kg = SnowBall.min_pack_mass()
	add_to_group(SnowBall.IMPACT_GROUP)
	# Preferences are read here rather than left to whatever the script defaults are, so
	# the settings screen actually changes the game and not just a file.
	SettingsSystemScript.ensure_loaded()
	snow_face_auto_clear = SettingsSystemScript.face_snow_auto_clear

	_setup_audio()
	_build_tools_visuals()
	_update_active_tool()
	_connect_snow_field()

func set_snow_field(sf: Node3D) -> void:
	snow_field = sf
	_connect_snow_field()

func _connect_snow_field() -> void:
	if snow_field and snow_field.has_signal("snow_tossed_in_bank"):
		if not snow_field.snow_tossed_in_bank.is_connected(_on_snow_bank_hit):
			snow_field.snow_tossed_in_bank.connect(_on_snow_bank_hit)

func _on_snow_bank_hit(bonus: int, _world_pos: Vector3) -> void:
	add_coins(bonus)

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
			cycle_tool_prev()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_tool_next()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input = event.relative
		var sens := mouse_sensitivity * SettingsSystemScript.mouse_sensitivity
		var pitch_sign := 1.0 if SettingsSystemScript.invert_look else -1.0
		rotate_y(-event.relative.x * sens)
		camera.rotate_x(pitch_sign * event.relative.y * sens)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-75.0), deg_to_rad(80.0))

	if event.is_action_pressed("toggle_cursor"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("tool_1"):
		if is_tool_owned(ToolType.SHOVEL):
			_switch_tool(ToolType.SHOVEL)
	elif event.is_action_pressed("tool_2"):
		if is_tool_owned(ToolType.BLOWER):
			_switch_tool(ToolType.BLOWER)
	elif event.is_action_pressed("tool_3"):
		if is_tool_owned(ToolType.SALT):
			_switch_tool(ToolType.SALT)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_4 or event.keycode == KEY_0:
			_switch_tool(ToolType.HANDS)

func _switch_tool(new_tool: ToolType) -> void:
	if not is_tool_owned(new_tool):
		return
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

## Spheres a thrown ball sweeps against: a head and a torso. Two spheres are
## enough for a person and they keep the test analytic and cheap.
func impact_spheres() -> Array:
	var eye: Vector3 = camera.global_position if camera else global_position + Vector3(0.0, BASE_CAMERA_Y, 0.0)
	return [
		{"center": eye, "radius": head_hit_radius, "head": true},
		{"center": global_position + Vector3(0.0, 0.95, 0.0), "radius": 0.55, "head": false},
	]

## Called by a ball that connects. Returns true when the ball should break on the
## player, which is whenever the hit lands on someone who can take it.
func receive_ball_hit(tier: int, _speed: float, head_hit: bool, _point: Vector3, _dir: Vector3) -> bool:
	# The session decides whether thrown snow is a prank or just snow: in Work mode a
	# ball to the face is nothing at all.
	if not hit_reactions_enabled or not SessionModeScript.reactions_enabled():
		return false
	# Blocked while a reaction is running and for a grace period after it ends, so
	# a stream of balls can never lock a player down.
	if hit_immunity > 0.0 or hit_state != HitState.NORMAL:
		return false
	hits_taken += 1
	last_hit_tier = tier
	last_hit_was_head = head_hit
	match tier:
		SnowBall.BallTier.SMALL:
			# A small ball only matters if it catches you in the face.
			if head_hit:
				_apply_face_snow()
		SnowBall.BallTier.MEDIUM:
			_enter_hit_state(HitState.STAGGERED, stagger_time)
			if head_hit:
				_apply_face_snow()
		SnowBall.BallTier.LARGE:
			_enter_hit_state(HitState.KNOCKED_DOWN, knockdown_time)
			if head_hit:
				_apply_face_snow()
	return true

func _apply_face_snow() -> void:
	face_snow_timer = face_snow_time
	_wipe_progress = 0.0
	face_snow_amount = 1.0

func _enter_hit_state(state: int, duration: float) -> void:
	hit_state = state
	hit_state_timer = duration
	_hit_shake = 1.0
	is_pushing = false
	if state == HitState.KNOCKED_DOWN and is_carrying():
		# Losing your footing means losing what you were carrying.
		_release_carried(Vector3.ZERO)

## Timers for the hit reactions, the face snow and the immunity that stops any
## player being locked down by repeated hits.
func _update_hit_state(delta: float) -> void:
	hit_immunity = maxf(hit_immunity - delta, 0.0)
	_hit_shake = maxf(_hit_shake - delta * 1.5, 0.0)

	if hit_state != HitState.NORMAL:
		hit_state_timer = maxf(hit_state_timer - delta, 0.0)
		if hit_state_timer <= 0.0:
			hit_state = HitState.NORMAL
			hit_immunity = hit_immunity_time

	if face_snow_timer > 0.0:
		if _wipe_progress >= 1.0:
			face_snow_timer = 0.0
			_wipe_progress = 0.0
		elif SettingsSystemScript.face_snow_auto_clear and snow_face_auto_clear:
			face_snow_timer = maxf(face_snow_timer - delta, 0.0)
	face_snow_amount = clampf(face_snow_timer / 0.4, 0.0, 1.0) if face_snow_timer > 0.0 else 0.0

## Wiping is progress over time while the interact action is held.
func _update_wipe(delta: float) -> void:
	if face_snow_timer <= 0.0:
		return
	if Input.is_action_pressed("interact"):
		_wipe_progress = minf(_wipe_progress + delta / maxf(face_wipe_time, 0.05), 1.0)
	else:
		_wipe_progress = 0.0

## Clears every reaction. Used on respawn and by the diagnostic battery.
func reset_hit_reactions() -> void:
	hit_state = HitState.NORMAL
	hit_state_timer = 0.0
	hit_immunity = 0.0
	face_snow_timer = 0.0
	face_snow_amount = 0.0
	_wipe_progress = 0.0
	_hit_shake = 0.0
	hits_taken = 0
	last_hit_tier = -1
	last_hit_was_head = false

func _physics_process(delta: float) -> void:
	_update_hit_state(delta)
	_update_wipe(delta)

	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input_dir.y -= 1.0
	if Input.is_action_pressed("move_backward"): input_dir.y += 1.0
	if Input.is_action_pressed("move_left"): input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): input_dir.x += 1.0
	# Knocked down: the body keeps its momentum but takes no orders.
	if hit_state == HitState.KNOCKED_DOWN:
		input_dir = Vector2.ZERO
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

	# Rolling a snowball on the ground: the player moves at the ball's rolling speed
	var rolling_target: Node3D = _push_target as Node3D
	var target_is_grounded := false
	if rolling_target and is_instance_valid(rolling_target):
		if rolling_target.has_method("height_above_support"):
			var br: float = float(rolling_target.get("radius")) if rolling_target.get("radius") != null else 0.2
			target_is_grounded = rolling_target.height_above_support() <= br + 0.15
		elif rolling_target.has_method("is_grounded"):
			target_is_grounded = rolling_target.is_grounded()
		else:
			target_is_grounded = true

	if target_is_grounded and (is_ground_pushing or (Input.is_action_pressed("interact") and _push_target != null)) and rolling_target and is_instance_valid(rolling_target):
		var is_sprint := Input.is_action_pressed("sprint")
		var ball_target_speed: float = rolling_target.target_push_speed(is_sprint) if rolling_target.has_method("target_push_speed") else 3.2
		var offset: Vector3 = rolling_target.global_position - global_position
		var dist: float = Vector2(offset.x, offset.z).length()
		var dist_error: float = dist - 1.5
		target_speed = ball_target_speed * clampf(1.0 + dist_error * 0.6, 0.5, 1.4)

	var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var wants_move := input_dir.length_squared() > 0.01

	# When actively pushing a ball forward on the ground, guide player's forward movement directly behind the ball
	if is_ground_pushing and target_is_grounded and rolling_target and is_instance_valid(rolling_target) and input_dir.y < -0.5:
		var to_ball := rolling_target.global_position - global_position
		to_ball.y = 0.0
		if to_ball.length_squared() > 0.01:
			if absf(input_dir.x) > 0.1:
				wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			else:
				wish_dir = to_ball.normalized()

	# Stagger from an oversized ball: lateral drift and less control.
	if stagger > 0.01:
		wish_dir += transform.basis.x * sin(_stagger_phase * 2.2) * 0.5 * stagger
		if wish_dir.length() > 0.01:
			wish_dir = wish_dir.normalized()

	# Staggered by a hit: the same kind of drift, shorter and sharper.
	if hit_state == HitState.STAGGERED:
		wish_dir += transform.basis.x * sin(_time * 9.0) * 0.6
		if wish_dir.length() > 0.01:
			wish_dir = wish_dir.normalized()

	_time += delta
	if _pending_pack:
		_pending_pack_time += delta
		if _pending_pack_time > 1.0:
			_pending_pack = false
			_pending_pack_time = 0.0
	_refresh_surface()

	# Jump input is read BEFORE the movement, exactly like Quake's PM_WalkMove
	# (PM_CheckJump runs before PM_Friction). Jumping on the landing frame skips
	# that frame's friction, and that is the entire reward for chaining hops: the
	# hop hands out no speed of its own.
	#
	# Auto-hop waits until the player is actually moving: in the air this model
	# grants only about 1 m/s, so hopping from a standstill would trap them.
	if Input.is_action_just_pressed("jump") \
			or (auto_bhop and Input.is_action_pressed("jump") and horizontal_speed > auto_bhop_min_speed):
		_jump_buffer = 0.12
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if is_grounded and not is_jumping and _jump_buffer > 0.0:
		_start_jump()

	var move_speed: float = target_speed * surface_speed_scale
	# While the blade is actually working, the drag model already accounts for the
	# effort of moving snow. Piling the walking-surface penalty on top of it turns
	# shovelling into a crawl, so the surface only governs free movement.
	if (current_tool == ToolType.SHOVEL and is_pushing) or is_ground_pushing:
		move_speed = target_speed
	_move_horizontal(wish_dir, move_speed, delta, wants_move)

	# Looking around with a controller. The right stick is read straight from the pad
	# rather than through input actions, so it works on any controller without a single
	# line added to the input map. Without this the camera needs a mouse, which is the
	# reason the game was not playable on a Steam Deck.
	_apply_stick_look(delta)

	# Camera sway while staggering, plus the knock of a hit.
	if camera:
		var wobble := sin(_stagger_phase * 2.6) * 0.11 * stagger
		wobble += sin(_time * 31.0) * 0.06 * _hit_shake * SettingsSystemScript.screen_shake
		camera.rotation.z = lerpf(camera.rotation.z, wobble, delta * 6.0)
	else:
		# The roll is a smoothed value, so it has to be driven even when nothing is swaying.
		# Inside the condition it kept whatever it held when the hit or the carry ended, and the
		# player walked around permanently tilted after being hit once.
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, delta * 6.0)

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
	# Fallback for a jump the ground flag missed (walking off a lip onto snow).
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

	# Knocked down: the view drops towards the snow and climbs back up.
	var cam_y := BASE_CAMERA_Y
	if hit_state == HitState.KNOCKED_DOWN:
		var fall := clampf(hit_state_timer / maxf(knockdown_time, 0.01), 0.0, 1.0)
		cam_y = lerpf(BASE_CAMERA_Y, 0.60, sin(fall * PI))
	camera.position.y = cam_y

	var horiz_speed = Vector2(velocity.x, velocity.z).length()
	if (is_on_floor() or is_grounded) and horiz_speed > 0.5:
		step_distance += horiz_speed * delta
		if step_distance >= step_interval:
			step_distance = 0.0
			_play_footstep()

	# Physical push on balls and props when colliding with them
	_push_touched_bodies(horiz_speed)

	# Refresh reticle aim and state for active tool and interaction
	_update_reticle_aim()

	# Staggered and knocked down players cannot work their tools.
	if hit_state == HitState.NORMAL:
		match current_tool:
			ToolType.SHOVEL:
				_process_shovel(delta, horiz_speed)
			ToolType.BLOWER:
				_process_blower(delta)
			ToolType.SALT:
				_process_salt(delta)
			ToolType.HANDS:
				pass

	_process_interaction(delta)
	_update_carried(delta)
	_process_hand_sway(delta, horiz_speed)

## Reads the snow under the player and turns it into movement feel.
##
## Cohesion decides the surface, because it is the channel that working the ground
## actually moves. Measured in the level: untouched dry snow sits near 0.20 and a
## tamped strip near 0.68.
func _refresh_surface() -> void:
	var surface := "snow"
	var speed_scale := 1.0
	var friction := 1.0
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

		if height < 0.03:
			surface = "cleared"
			speed_scale = 1.05
			friction = 0.7
		elif cohesion >= 0.45:
			surface = "packed"
			speed_scale = 1.05
			friction = 0.8
		elif cohesion >= 0.35:
			surface = "snow"
			speed_scale = 1.0
			friction = 1.0
		else:
			# Dry unbonded snow: you sink into it, so it is slower and it holds you
			# harder. Deliberately not harsher than this: it is the starting state
			# of every level and walking must never feel like a chore.
			surface = "powder"
			speed_scale = 0.85
			friction = 1.2
	surface_name = surface
	surface_speed_scale = speed_scale
	surface_friction = friction

## Quake's PM_Friction: a proportional speed loss, with a floor on the control
## term so the player comes to a clean stop instead of sliding for ever.
## Right-stick look, with a dead zone so a drifting stick does not creep the view.
func _apply_stick_look(delta: float) -> void:
	if camera == null:
		return
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() < STICK_DEADZONE:
		return
	var speed := STICK_LOOK_SPEED * SettingsSystemScript.mouse_sensitivity * delta
	var pitch_sign := 1.0 if SettingsSystemScript.invert_look else -1.0
	rotate_y(-stick.x * speed)
	camera.rotate_x(pitch_sign * -stick.y * speed)
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-75.0), deg_to_rad(80.0))

func _apply_ground_friction(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	var speed := flat.length()
	if speed < 0.1:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control := maxf(speed, ground_stop_speed)
	var drop := control * ground_friction * surface_friction * delta
	var newspeed := maxf(speed - drop, 0.0) / speed
	velocity.x *= newspeed
	velocity.z *= newspeed

## Quake's PM_Accelerate. The speed added is capped by how far the wish speed is
## ahead of the velocity *along the wish direction*, which is what lets sideways
## input rotate the velocity and grow it instead of just adding to it.
##
## `speed_for_accel` overrides the speed the term is scaled by, which is how
## QuakeWorld keeps a fast strafe from losing its bite.
func _accelerate(wish_dir: Vector3, wishspeed: float, accel: float, delta: float, speed_for_accel: float = -1.0) -> void:
	var current := velocity.x * wish_dir.x + velocity.z * wish_dir.z
	var add := wishspeed - current
	if add <= 0.0:
		return
	var scale_speed := speed_for_accel if speed_for_accel > 0.0 else wishspeed
	var accelspeed := minf(accel * delta * scale_speed, add)
	velocity.x += accelspeed * wish_dir.x
	velocity.z += accelspeed * wish_dir.z

## Horizontal motion.
##
## On the ground the player accelerates toward the surface speed but is never
## braked down to it: above it, only the direction is steered and the momentum
## bleeds off with the surface coast. In the air nothing brakes at all, so air
## acceleration can build speed. That difference is what makes hopping work.
func _move_horizontal(wish_dir: Vector3, target_speed: float, delta: float, wants_move: bool) -> void:
	var control := 1.0 - 0.45 * stagger
	if hit_state == HitState.STAGGERED:
		control *= 0.5
	var cap := sprint_speed * bhop_cap_factor

	if is_jumping:
		# No friction in the air, and the wish speed is clamped small, so only a
		# strafe aimed sideways can add anything.
		var air_speed := minf(target_speed, air_wish_speed)
		_accelerate(wish_dir, air_speed, air_accelerate * control, delta, target_speed)
	else:
		if (_time - _landing_time) > chain_window and jump_chain > 0:
			jump_chain = 0
		_apply_ground_friction(delta)
		_accelerate(wish_dir, target_speed, ground_accelerate * control, delta)

	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > cap:
		flat = flat.normalized() * cap
		velocity.x = flat.x
		velocity.z = flat.y
	horizontal_speed = flat.length()

## Launches the player. Vertical only: the reward for hopping is skipping the
## ground friction on the frames it is airborne, so there is no speed bonus here.
func _start_jump() -> void:
	if is_jumping:
		return
	_jump_buffer = 0.0
	if (_time - _landing_time) <= chain_window:
		jump_chain += 1
	velocity.y = jump_velocity
	is_jumping = true
	is_grounded = false

	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_step()
	sfx.volume_db = -2.0
	sfx.pitch_scale = 0.88
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

## Touchdown: the snow under the feet gets packed, which is why hopping in a line
## traces a usable path. Ground friction handles the rest on its own.
func _on_land() -> void:
	_landing_time = _time
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

func get_snow_surface_y(pos: Vector3) -> float:
	var base_y := 0.0
	if snow_field:
		base_y = snow_field.global_position.y
		if snow_field.has_method("get_height_at"):
			var h: float = snow_field.get_height_at(pos)
			if h >= 0.0:
				return base_y + h
		if snow_field.has_method("get_support_snow_height"):
			return base_y + maxf(snow_field.get_support_snow_height(pos, 0.35), 0.0)
	return base_y

func get_reticle_state() -> ReticleState:
	return reticle_state

func get_reticle_aim_point() -> Vector3:
	return reticle_aim_pt

func _update_reticle_aim() -> void:
	if camera == null:
		reticle_state = ReticleState.OFF
		reticle_aim_pt = Vector3.INF
		reticle_has_hit = false
		return

	var max_reach := 2.4
	match current_tool:
		ToolType.HANDS:
			max_reach = PACK_REACH_EXTENDED
		ToolType.SHOVEL:
			max_reach = 2.2
		ToolType.BLOWER:
			max_reach = 4.0
		ToolType.SALT:
			max_reach = 3.0
	reticle_reach = max_reach

	var cam_pos := camera.global_position
	var cam_dir := -camera.global_transform.basis.z.normalized()
	var forward_flat := _forward_flat()

	var hit_found := false
	var hit_pos := Vector3.INF

	# 1. Downward raycast towards the snowpack/ground (pitch down)
	if cam_dir.y < -0.02:
		var step_size := 0.08
		var cur_d := 0.20
		var limit_d := max_reach + 2.5
		var prev_d := cur_d

		var p0 := cam_pos + cam_dir * cur_d
		if p0.y <= get_snow_surface_y(p0):
			hit_found = true
			hit_pos = p0
			hit_pos.y = get_snow_surface_y(hit_pos)
		else:
			while cur_d <= limit_d:
				cur_d += step_size
				var p := cam_pos + cam_dir * cur_d
				if p.y <= get_snow_surface_y(p):
					hit_found = true
					break
				prev_d = cur_d

			if hit_found:
				var d_min := prev_d
				var d_max := cur_d
				for i in range(5):
					var d_mid := (d_min + d_max) * 0.5
					var pm := cam_pos + cam_dir * d_mid
					if pm.y <= get_snow_surface_y(pm):
						d_max = d_mid
					else:
						d_min = d_mid
				var final_d := (d_min + d_max) * 0.5
				hit_pos = cam_pos + cam_dir * final_d
				hit_pos.y = get_snow_surface_y(hit_pos)

	# 2. Horizontal or straight-ahead look (not aimed high in the sky)
	if not hit_found and cam_dir.y >= -0.02 and cam_dir.y < 0.25:
		# Check if ray intersects an elevated mound in front
		var cur_d := 0.3
		var limit_d := max_reach + 0.5
		var prev_d := cur_d
		var mound_hit := false
		while cur_d <= limit_d:
			cur_d += 0.10
			var p := cam_pos + cam_dir * cur_d
			if p.y <= get_snow_surface_y(p):
				mound_hit = true
				break
			prev_d = cur_d
		if mound_hit:
			var d_min := prev_d
			var d_max := cur_d
			for i in range(5):
				var d_mid := (d_min + d_max) * 0.5
				var pm := cam_pos + cam_dir * d_mid
				if pm.y <= get_snow_surface_y(pm):
					d_max = d_mid
				else:
					d_min = d_mid
			hit_pos = cam_pos + cam_dir * ((d_min + d_max) * 0.5)
			hit_pos.y = get_snow_surface_y(hit_pos)
			hit_found = true
		else:
			# Forward reach along line of sight (forward-only, no backward search)
			if current_tool == ToolType.HANDS:
				var forward_radii: Array[float] = [PACK_REACH_STRICT, 0.9, 1.7, 2.0, PACK_REACH_EXTENDED]
				for r in forward_radii:
					var cand_ext := global_position + forward_flat * r
					cand_ext.y = get_snow_surface_y(cand_ext)
					if _estimate_available_snow_kg(cand_ext) >= pack_min_kg:
						hit_pos = cand_ext
						hit_found = true
						break
				if not hit_found:
					var cand := global_position + forward_flat * PACK_REACH_STRICT
					cand.y = get_snow_surface_y(cand)
					hit_pos = cand
					hit_found = true
			else:
				var cand := global_position + forward_flat * minf(1.4, max_reach)
				cand.y = get_snow_surface_y(cand)
				hit_pos = cand
				hit_found = true

	if not hit_found:
		reticle_state = ReticleState.OFF
		reticle_aim_pt = Vector3.INF
		reticle_has_hit = false
		return

	# Target must be in front of the player and within tool reach
	var offset := hit_pos - global_position
	var forward_dot := offset.dot(forward_flat)
	var horiz_dist := Vector2(offset.x, offset.z).length()

	if forward_dot <= 0.05 or horiz_dist > max_reach:
		reticle_state = ReticleState.OFF
		reticle_aim_pt = Vector3.INF
		reticle_has_hit = false
		return

	reticle_aim_pt = hit_pos
	reticle_has_hit = true

	# Evaluate reticle state
	if is_carrying():
		reticle_state = ReticleState.OFF
	elif current_tool == ToolType.HANDS:
		var avail_kg := _estimate_available_snow_kg(reticle_aim_pt)
		if avail_kg >= pack_min_kg:
			reticle_state = ReticleState.CAN_PACK
		else:
			reticle_state = ReticleState.OFF
	else:
		var depth := 0.0
		if snow_field and snow_field.has_method("get_height_at"):
			depth = snow_field.get_height_at(reticle_aim_pt)
		if depth > 0.015:
			reticle_state = ReticleState.CAN_CARVE
		else:
			reticle_state = ReticleState.OFF

func _get_target_ground_pos() -> Vector3:
	if reticle_aim_pt != Vector3.INF:
		return reticle_aim_pt
	var fwd := _forward_flat()
	var fallback := global_position + fwd * 1.4
	fallback.y = get_snow_surface_y(fallback)
	return fallback

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

		var scoop_pt := _get_target_ground_pos()
		var scoop_offset := scoop_pt - global_position
		var scoop_dist := Vector2(scoop_offset.x, scoop_offset.z).length()
		if scoop_dist > 1.4:
			scoop_pt = global_position + forward_flat * 1.10
			scoop_pt.y = get_snow_surface_y(scoop_pt)
		elif scoop_dist < 0.6:
			scoop_pt = global_position + forward_flat * 0.8
			scoop_pt.y = get_snow_surface_y(scoop_pt)

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
	var pour_pt := _get_target_ground_pos()
	var pour_offset := pour_pt - global_position
	var pour_dist := Vector2(pour_offset.x, pour_offset.z).length()
	if pour_dist > 2.2 or pour_dist < 0.4:
		pour_pt = global_position + forward_flat * clampf(pour_dist, 0.6, 2.2)
	pour_pt.y = get_snow_surface_y(pour_pt)
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

	# With a face full of snow, [E] wipes it off instead of doing anything else.
	if face_snow_timer > 0.0:
		_push_target = null
		is_ground_pushing = false
		pushed_mass = 0.0
		_interact_hold = 0.0
		_interact_was_pressed = false
		return

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
			elif not _has_interactable_ahead() and _push_target == null:
				_try_pickup_or_pack()
		_interact_hold += delta
		if (_interact_hold >= interact_hold_time or _push_target != null) and not is_carrying():
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
	pushed_mass = 0.0

## Finds an interactable ball or prop ahead of the player via raycast or feet area.
func _find_interactable_ahead() -> CollisionObject3D:
	var hit := _raycast_interactable()
	if not hit.is_empty():
		var col = hit.get("collider")
		if col != null and (col is SnowBall or col is PinProp) and (col.has_method("begin_carry") or col.has_method("push")):
			return col
	# Fallback for anything close in front of the player (at the feet or in front of the body)
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.collide_with_areas = false
	params.collision_mask = 4 | 8
	params.exclude = [get_rid()]
	var fwd_flat := _forward_flat()
	params.transform = Transform3D(Basis(), global_position + fwd_flat * 1.0 + Vector3.UP * 0.3)
	for result in get_world_3d().direct_space_state.intersect_shape(params, 8):
		var body = result.get("collider")
		if body != null and (body is SnowBall or body is PinProp) and (body.has_method("begin_carry") or body.has_method("push")):
			return body
	return null

## Is there a pickable ball or prop right in front?
func _has_interactable_ahead() -> bool:
	return _find_interactable_ahead() != null

## Continuous push with held [E]: the ball rolls on the ground in front of the
## player and is never lifted (it stays a dynamic body resting on the
## snowpack). Bounded force: the heavier it is, the harder it is to move.
func _ground_push() -> bool:
	if _push_target == null or not is_instance_valid(_push_target):
		var target := _find_interactable_ahead()
		if target != null and target.has_method("push"):
			if target.has_method("height_above_support"):
				var br: float = float(target.get("radius")) if target.get("radius") != null else 0.2
				if target.height_above_support() > br + 0.15:
					return false
			_push_target = target
		else:
			_push_target = null
			is_ground_pushing = false
			pushed_mass = 0.0
			return false

	# Ground push requires contact with the snowpack/ground: a ball in flight cannot be pushed
	if _push_target.has_method("height_above_support"):
		var br: float = float(_push_target.get("radius")) if _push_target.get("radius") != null else 0.2
		if _push_target.height_above_support() > br + 0.15:
			is_ground_pushing = false
			pushed_mass = 0.0
			return false

	var offset: Vector3 = _push_target.global_position - global_position
	var dist := Vector2(offset.x, offset.z).length()
	var min_reach: float = float(_push_target.get("PUSH_REACH_MIN")) if _push_target.get("PUSH_REACH_MIN") != null else 0.8
	var max_reach: float = float(_push_target.get("PUSH_REACH_MAX")) if _push_target.get("PUSH_REACH_MAX") != null else 3.0

	# Keep the ball in front: if too close, or player is standing on top of it, stop pushing
	var ball_r: float = float(_push_target.get("radius")) if _push_target.get("radius") != null else 0.2
	if dist < min_reach or (dist < ball_r + 0.4 and global_position.y > _push_target.global_position.y + ball_r * 0.4):
		is_ground_pushing = false
		pushed_mass = 0.0
		return false

	# If the ball rolls too far ahead (> 3 m), stop pushing so the player must walk behind it
	if dist > max_reach:
		is_ground_pushing = false
		pushed_mass = 0.0
		if dist > max_reach + 1.5:
			_push_target = null
		return false

	_push_target.push(global_position, ground_push_strength, self)
	is_ground_pushing = true
	pushed_mass = float(_push_target.get("mass")) if _push_target.get("mass") != null else 0.0
	return true

func _try_pickup_or_pack() -> void:
	var obj := _find_interactable_ahead()
	if obj != null:
		if obj is PinProp and obj.is_pinned:
			obj.try_extract()
			if obj.has_method("begin_carry"):
				_begin_carry(obj)
			return
		if obj.has_method("begin_carry"):
			_begin_carry(obj)
			return
	# With nothing to pick up, snow is packed by hand
	_pack_snowball()

func _raycast_interactable() -> Dictionary:
	if camera == null:
		return {}
	var space := get_world_3d().direct_space_state
	# Sample a small cross rather than a single line. A bare ray misses a ball the
	# player is clearly looking at whenever it sits a few centimetres off centre,
	# which reads as the interaction being broken.
	var offsets := [
		Vector2.ZERO,
		Vector2(0.16, 0.0), Vector2(-0.16, 0.0),
		Vector2(0.0, 0.16), Vector2(0.0, -0.16),
	]
	var best: Dictionary = {}
	var best_distance := INF
	for offset in offsets:
		var from: Vector3 = camera.global_position
		var dir: Vector3 = -camera.global_transform.basis.z
		from += camera.global_transform.basis.x * offset.x + camera.global_transform.basis.y * offset.y
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * interact_distance)
		q.collide_with_areas = false
		q.collision_mask = 4 | 8  # Snowballs (4) and pin props (8); ignore terrain and world geometry
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col = hit.get("collider")
		if col == null or not ((col is SnowBall or col is PinProp) or col.has_method("begin_carry") or col.has_method("push")):
			continue
		var distance: float = from.distance_to(hit["position"])
		if distance < best_distance:
			best_distance = distance
			best = hit
	return best

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
	body.end_carry(impulse, self)
	carried_mass = 0.0
	carry_two_hands = false
	stagger = 0.0
	_push_target = null
	is_ground_pushing = false
	pushed_mass = 0.0
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
			status_message = tr("STATUS_BALL_SLIPPED")
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
	# Aimed FROM THE BALL at the point the crosshair is on: the ball rests at the hand, off
	# to one side and below the eye, so a direction merely parallel to the view flies past the
	# target instead of at it.
	var forward := -camera.global_transform.basis.z
	var dir := ((camera.global_position + forward * 12.0) - carried.global_position).normalized()
	# One-handed the throw is flat; two-handed it is a heave with more arc, which
	# is what lets a large ball be passed to another person.
	# No lift. The upward term used to add 3.4 m/s of climb to a 7.5 m/s throw, about 25
	# degrees over the crosshair, and inheriting the hand's motion pushed it sideways. The arc
	# is gravity's job: to throw far, aim up.
	var impulse := dir * speed
	var off := rad_to_deg(dir.angle_to(forward))
	print("[THROWDBG] %.2f kg at %.2f m/s, %.1f deg off the crosshair" % [carried_mass, speed, off])
	# The impulse inherits the hand motion so the throw feels natural

	_release_carried(impulse)
	_push_target = null
	is_ground_pushing = false
	pushed_mass = 0.0
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

## Estimates available snow mass (kg) at a world position using the GPU coarse mirror.
func _estimate_available_snow_kg(pos: Vector3, harvest_radius: float = PACK_HARVEST_RADIUS) -> float:
	if snow_field == null or not snow_field.has_method("get_height_at"):
		return 0.0
	var h0: float = snow_field.get_height_at(pos)
	if h0 <= 0.045:
		return 0.0
	var r_sample := harvest_radius * 0.6
	var h1: float = snow_field.get_height_at(pos + Vector3(r_sample, 0.0, 0.0))
	var h2: float = snow_field.get_height_at(pos - Vector3(r_sample, 0.0, 0.0))
	var h3: float = snow_field.get_height_at(pos + Vector3(0.0, 0.0, r_sample))
	var h4: float = snow_field.get_height_at(pos - Vector3(0.0, 0.0, r_sample))
	var h_min: float = minf(h0, minf(minf(h1, h2), minf(h3, h4)))
	if h_min <= 0.015:
		return 0.0
	var cut_avg: float = (minf(h0, PACK_HARVEST_DEPTH) * 2.0 + minf(h1, PACK_HARVEST_DEPTH) + minf(h2, PACK_HARVEST_DEPTH) + minf(h3, PACK_HARVEST_DEPTH) + minf(h4, PACK_HARVEST_DEPTH)) / 6.0
	var max_depth := minf(PACK_HARVEST_DEPTH, h0 * 0.8)
	var effective_cut := minf(cut_avg, max_depth)
	# Harvest mode in snow_sim.glsl has smoothstep falloff with effective area ~1.5 * R^2
	var eff_area: float = 1.50 * harvest_radius * harvest_radius
	var density: float = float(snow_field.get("snow_density")) if snow_field.get("snow_density") != null else 150.0
	return effective_cut * eff_area * density

## Finds the ground position to pack a snowball, strictly at the reticle aim point.
## Forward-only, never searching behind player or under feet on bare ground.
func _find_pack_target() -> Vector3:
	_update_reticle_aim()
	if reticle_aim_pt != Vector3.INF and _estimate_available_snow_kg(reticle_aim_pt) >= pack_min_kg:
		return reticle_aim_pt
	return Vector3.INF

## Packs snow by hand: the mass comes from the snowpack and forms a real ball
## whose radius depends on the exact volume removed.
func _pack_snowball() -> void:
	if _pending_pack or snow_field == null or not snow_field.has_method("request_harvest"):
		return
	var pt := _find_pack_target()
	if pt == Vector3.INF:
		status_message = tr("STATUS_NOT_ENOUGH_SNOW")
		return
	_pack_harvest_pt = pt
	_pending_pack = true
	_pending_pack_time = 0.0
	var h: float = snow_field.get_height_at(pt) if snow_field.has_method("get_height_at") else 0.10
	var depth := minf(PACK_HARVEST_DEPTH, maxf(h * 0.8, 0.04))
	snow_field.request_harvest(_player_owner, pt, pt + Vector3(0.02, 0.0, 0.02), PACK_HARVEST_RADIUS, depth)
	status_message = tr("STATUS_PACKING_SNOW")

func _on_op_volume_ready(role: String, owner: int, kg: float) -> void:
	if role != "harvest" or owner != _player_owner:
		return
	if not _pending_pack:
		return
	_pending_pack = false
	last_pack_harvest_kg = kg
	if kg <= 0.001:
		status_message = tr("STATUS_NOT_ENOUGH_SNOW")
		return
	var r := SnowBall.radius_for_packed_mass(kg)
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
		status_message = tr("STATUS_BALL_ON_GROUND") % ball.packed_mass()
	else:
		_begin_carry(ball)
		status_message = tr("STATUS_BALL_IN_HANDS") % ball.packed_mass()
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
		if other == _push_target and is_ground_pushing:
			continue
		if other is SnowBall:
			other.push(global_position, strength, self)
		elif other is PinProp and other.has_method("push"):
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