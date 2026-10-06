extends Node

# CurveFlightDemo: Diagnostic test for Bug 2 (thrown ball curving in flight).
# Tests:
# 1. Spawn a ball, interact with it, throw it straight forward.
# 2. Player keeps [E] held (interact) and input forward during flight.
# 3. Track lateral deviation (x), height above support, linear/angular velocity,
#    player's _push_target and is_ground_pushing, and collision contacts.

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _ball: RigidBody3D = null
var _flight_frames: int = 0
var _launch_pos: Vector3 = Vector3.ZERO
var _launch_dir: Vector3 = Vector3.ZERO
var _max_lateral_dev_in_air: float = 0.0
var _forces_in_air_count: int = 0
var _finished: bool = false

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[CURVE-DIAG] ==== THROWN BALL FLIGHT DIAGNOSTIC ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

var _initial_dir_2d: Vector2 = Vector2.ZERO
var _had_first_frame: bool = false
var _first_contact_frame: int = -1

func _change_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_state_time += delta

	match _state:
		0:
			# State 0: Wait for simulation and position player facing straight forward (-Z)
			if _state_time >= 0.5 and snow_field != null and snow_field.has_method("is_coarse_ready") and snow_field.is_coarse_ready():
				player.global_position = Vector3(0.0, 0.1, 4.0)
				player.rotation = Vector3.ZERO
				if player.camera:
					player.camera.rotation = Vector3.ZERO
				# Spawn a standard ball at feet
				if props and props.has_method("spawn_snowball"):
					_ball = props.spawn_snowball(Vector3(0.0, 0.4, 3.2), 0.25)
				_change_state(1)

		1:
			# State 1: Let ball settle on ground and pick it up
			if _state_time >= 0.5 and _ball != null and is_instance_valid(_ball):
				# Player interacts with ball
				player._push_target = _ball
				player._begin_carry(_ball)
				print("[CURVE-DIAG] Ball picked up. Carried=%s _push_target=%s" % [str(player.carried), str(player._push_target)])
				_change_state(2)

		2:
			# State 2: Hold carried ball for a brief moment, then throw forward
			if _state_time >= 0.3:
				_launch_pos = _ball.global_position
				_launch_dir = -player.camera.global_transform.basis.z if player.camera else Vector3.FORWARD
				_launch_dir.y = 0.0
				_launch_dir = _launch_dir.normalized()
				print("[CURVE-DIAG] THROWING BALL at frame 0: pos=%s forward=%s _push_target=%s is_ground_pushing=%s" % [
					str(_launch_pos), str(_launch_dir), str(player._push_target), str(player.is_ground_pushing)])
				# Throw the ball forward
				player._throw_carried()
				_flight_frames = 0
				_max_lateral_dev_in_air = 0.0
				_had_first_frame = false
				_first_contact_frame = -1
				_change_state(3)

		3:
			# State 3: Flight observation over 45 physics frames while holding [E] and forward input
			_flight_frames += 1
			# Simulate holding [E] (interact) and moving forward (W)
			Input.action_press("interact")
			Input.action_press("move_forward")

			if _ball != null and is_instance_valid(_ball):
				var pos: Vector3 = _ball.global_position
				var vel: Vector3 = _ball.linear_velocity
				var ang_vel: Vector3 = _ball.angular_velocity
				var h_support: float = _ball.height_above_support() if _ball.has_method("height_above_support") else pos.y - 0.25
				var ball_r: float = float(_ball.get("radius")) if _ball.get("radius") != null else 0.25
				var is_in_air: bool = h_support > ball_r + 0.1

				if not _had_first_frame:
					_had_first_frame = true
					_launch_pos = pos
					var v2 := Vector2(vel.x, vel.z)
					_initial_dir_2d = v2.normalized() if v2.length_squared() > 1e-4 else Vector2(0, -1)

				# Lateral deviation relative to initial ballistic trajectory line
				var delta_xz := Vector2(pos.x - _launch_pos.x, pos.z - _launch_pos.z)
				var along := delta_xz.dot(_initial_dir_2d)
				var perp := (delta_xz - _initial_dir_2d * along).length()

				if is_in_air and _first_contact_frame < 0:
					_max_lateral_dev_in_air = maxf(_max_lateral_dev_in_air, perp)
				elif not is_in_air and _first_contact_frame < 0:
					_first_contact_frame = _flight_frames

				var push_tgt = player._push_target
				var is_push = player.is_ground_pushing

				print("[CURVE-DIAG +%02d] in_air=%s h=%.3f pos=(%.2f, %.2f, %.2f) perp_dev=%.4f vel=(%.2f, %.2f, %.2f) ang=(%.2f, %.2f, %.2f) push_tgt=%s is_pushing=%s" % [
					_flight_frames, str(is_in_air), h_support, pos.x, pos.y, pos.z, perp,
					vel.x, vel.y, vel.z, ang_vel.x, ang_vel.y, ang_vel.z,
					("valid" if push_tgt != null else "null"), str(is_push)])

			if _flight_frames >= 45:
				Input.action_release("interact")
				Input.action_release("move_forward")
				_report()

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[CURVE-DIAG] ==== FLIGHT REPORT ====")
	print("[CURVE-DIAG] Max lateral deviation from straight trajectory while IN THE AIR: %.5f m" % _max_lateral_dev_in_air)
	print("[CURVE-DIAG] First ground contact occurred at frame: %d" % _first_contact_frame)
	print("[CURVE-DIAG] Status: %s" % ("OK (negligible deviation < 0.01m)" if _max_lateral_dev_in_air < 0.01 else "FAIL"))
	print("[CURVE-DIAG] ==== END ====")
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
