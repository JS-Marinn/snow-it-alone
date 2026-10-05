extends Node

# ContactBurstDemo: dual regression test for large snowball contact and thrown impact.
#
# Covers both directions:
# 1. Walking into a resting large ball (r = 0.45) on snow must NOT burst and must NOT knock down.
# 2. Throwing a large ball (r = 0.45, 5 m/s) at the player MUST burst and MUST knock down.

const BALL_RADIUS: float = 0.45
const PLAYER_Z: float = 4.0
const P1_BALL_Z: float = 2.5

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _p1_ball: SnowBall = null
var _p2_ball: SnowBall = null
var _cam: Camera3D
var _t: float = 0.0

var _p1_started: bool = false
var _p1_stopped: bool = false
var _p1_burst: bool = false
var _p1_evaluated: bool = false

var _p2_thrown: bool = false
var _p2_burst: bool = false
var _p2_evaluated: bool = false

var _ok: int = 0
var _fail: int = 0
var _finished: bool = false

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[CONTACT] ==== CONTACT BURST DUAL REGRESSION TEST ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_camera()
	_prepare_phase1()

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 65.0
	_cam.make_current()

func _update_camera() -> void:
	if _cam == null or player == null:
		return
	_cam.global_position = player.global_position + Vector3(2.5, 1.8, 2.5)
	_cam.look_at(player.global_position + Vector3(0.0, 0.9, -1.0), Vector3.UP)

func _ground_y(z: float) -> float:
	var g := 0.32
	if snow_field and snow_field.has_method("get_support_snow_height"):
		g = maxf(snow_field.get_support_snow_height(Vector3(0.0, 0.0, z), 0.35), 0.0)
	return g

func _prepare_phase1() -> void:
	if player == null or snow_field == null or props == null:
		_check("battery setup succeeded", false)
		_report()
		return

	var ground := _ground_y(PLAYER_Z)
	player.global_position = Vector3(0.0, ground, PLAYER_Z)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", ground)
	player.set("is_ground_initialized", true)
	if player.has_method("reset_hit_reactions"):
		player.reset_hit_reactions()

	var ball_ground := _ground_y(P1_BALL_Z)
	var spawn_pos := Vector3(0.0, ball_ground + BALL_RADIUS + 0.02, P1_BALL_Z)
	_p1_ball = props.spawn_snowball(spawn_pos, BALL_RADIUS)
	if _p1_ball == null:
		_check("phase 1 test snowball created", false)
		_report()
		return

	_p1_ball.linear_velocity = Vector3.ZERO
	_p1_ball.angular_velocity = Vector3.ZERO
	print("[CONTACT] Phase 1: player at %s, resting ball at %s" % [
		str(player.global_position), str(_p1_ball.global_position)])

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_update_camera()

	if player:
		player.rotation.y = 0.0

	# Track Phase 1 ball condition
	if _p1_ball != null and is_instance_valid(_p1_ball):
		if _p1_ball.get("_shattered"):
			_p1_burst = true
	elif not _p1_evaluated:
		_p1_burst = true

	# Track Phase 2 ball condition
	if _p2_thrown:
		if _p2_ball != null and is_instance_valid(_p2_ball):
			if _p2_ball.get("_shattered"):
				_p2_burst = true
		else:
			_p2_burst = true

	# --- Phase 1: walk into resting ball ---
	if _t >= 0.5 and not _p1_started:
		_p1_started = true
		Input.action_press("move_forward")
		print("[CONTACT] Phase 1 walk started at t=%.2f" % _t)

	if _t >= 2.5 and _p1_started and not _p1_stopped:
		_p1_stopped = true
		Input.action_release("move_forward")
		print("[CONTACT] Phase 1 walk stopped at t=%.2f" % _t)
		_evaluate_phase1()

	# --- Phase 2: throw ball at player ---
	if _t >= 2.8 and not _p2_thrown:
		_prepare_phase2()

	if _t >= 3.6 and _p2_thrown and not _p2_evaluated:
		_evaluate_phase2()

func _evaluate_phase1() -> void:
	_p1_evaluated = true
	var ply_state: int = int(player.get("hit_state")) if player != null else 0
	print("[CONTACT] Phase 1 evaluation: ball_burst=%s ply_hit_state=%d" % [
		str(_p1_burst), ply_state])
	_check("large resting ball does not burst when walked into", not _p1_burst)
	_check("player is not knocked down when walking into resting ball", ply_state != 2)

	# Clean up Phase 1 ball
	if _p1_ball != null and is_instance_valid(_p1_ball):
		_p1_ball.queue_free()
	_p1_ball = null

func _prepare_phase2() -> void:
	_p2_thrown = true
	var ground := _ground_y(PLAYER_Z)
	player.global_position = Vector3(0.0, ground, PLAYER_Z)
	player.velocity = Vector3.ZERO
	if player.has_method("reset_hit_reactions"):
		player.reset_hit_reactions()

	# Spawn 1.2 m in front of player, at torso height (0.95m above feet)
	var spawn_pos := Vector3(0.0, ground + 0.95, PLAYER_Z - 1.2)
	_p2_ball = props.spawn_snowball(spawn_pos, BALL_RADIUS)
	if _p2_ball == null:
		_check("phase 2 test snowball created", false)
		_report()
		return

	# Launch towards player (+Z) at 5.5 m/s
	_p2_ball.linear_velocity = Vector3(0.0, 0.0, 5.5)
	print("[CONTACT] Phase 2: thrown large ball spawned at %s, v=(0, 0, 5.5)" % str(spawn_pos))

func _evaluate_phase2() -> void:
	_p2_evaluated = true
	var ply_state: int = int(player.get("hit_state")) if player != null else 0
	print("[CONTACT] Phase 2 evaluation: ball_burst=%s ply_hit_state=%d (2=knocked down)" % [
		str(_p2_burst), ply_state])
	_check("thrown large ball bursts on impact with player", _p2_burst)
	_check("thrown large ball knocks the player down", ply_state == 2)
	_report()

func _check(label: String, ok: bool) -> void:
	print("[CONTACT] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[CONTACT] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[CONTACT] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
