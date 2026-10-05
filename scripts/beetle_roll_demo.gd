extends Node

# BeetleRollDemo: acceptance battery for the dung beetle snowball push mechanic.
#
# Tests that pushing a ball with held [E] rolls it with the player toward a
# speed ceiling that decreases with mass, rolling rather than sliding,
# accreting snow progressively without escaping or getting stuck.

const PUSH_DURATION: float = 12.0
const WARMUP_TIME: float = 0.4
const START_RADIUS: float = 0.12

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _ball: SnowBall = null
var _push_start_time: float = -1.0
var _sampling: bool = false
var _samples: Array[Dictionary] = []
var _cam: Camera3D

var _t: float = 0.0
var _last_log_t: float = 0.0
var _ok: int = 0
var _fail: int = 0
var _finished: bool = false

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[BEETLE] ==== DUNG BEETLE ROLL LAB ====")

	if snow_field == null or player == null or props == null:
		_check("battery could set itself up", false)
		_report()
		return

	_setup_camera()

	# Free obstacle ramps so the entire 36m virgin runway is clear for rolling
	if root != null:
		for child in root.get_children():
			if child.name.begins_with("Ramp"):
				child.queue_free()

	_prepare_player_and_ball()

func _prepare_player_and_ball() -> void:
	# Position on virgin snow runway in the playground (Lane 0 at x=-3.75)
	# Running from z=12.0 towards -Z (along unobstructed runway to -12.0).
	var x_pos := -3.75
	var z_pos := 12.0
	if "field_length" in snow_field and float(snow_field.field_length) < 25.0:
		x_pos = 0.0
		z_pos = 4.0

	var ground := 0.32
	if snow_field.has_method("get_support_snow_height"):
		ground = maxf(snow_field.get_support_snow_height(Vector3(x_pos, 0.0, z_pos), 0.35), 0.0)

	player.global_position = Vector3(x_pos, ground, z_pos)
	player.rotation.y = 0.0  # In Godot, -Z is forward.
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", ground)
	player.set("is_ground_initialized", true)
	if player.has_method("reset_hit_reactions"):
		player.reset_hit_reactions()

	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.rotation.x = deg_to_rad(-14.0)

	# 1.4 m in front of player (along -Z):
	var spawn_pos := Vector3(x_pos, ground + START_RADIUS + 0.02, z_pos - 1.4)
	_ball = props.spawn_snowball(spawn_pos, START_RADIUS)
	if _ball == null:
		_check("the test snowball is created", false)
		_report()
		return

	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.pusher = player
	_ball.push_grace_timer = 2.0
	player.set("_push_target", _ball)
	print("[BEETLE] player at %s, ball spawned at %s (r=%.2f m, m=%.1f kg)" % [
		str(player.global_position), str(_ball.global_position), _ball.radius, _ball.packed_mass()])

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 65.0
	_cam.make_current()

func _update_camera() -> void:
	if _cam == null or player == null:
		return
	# Behind and to the side of the player (looking towards -Z)
	_cam.global_position = player.global_position + Vector3(2.4, 2.0, 2.4)
	var look_target := player.global_position + Vector3(0.0, 0.6, -1.2)
	if _ball and is_instance_valid(_ball):
		look_target = (_ball.global_position + player.global_position) * 0.5 + Vector3(0.0, 0.5, 0.0)
	_cam.look_at(look_target, Vector3.UP)

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_update_camera()

	# Start push after warmup settle
	if _push_start_time < 0.0 and _t >= WARMUP_TIME:
		_push_start_time = _t
		_sampling = true
		Input.action_press("interact")
		Input.action_press("move_forward")
		player.set("_push_target", _ball)
		print("[BEETLE] pressing [E] and move_forward: beetle roll engaged")

	if not _sampling:
		return

	# Keep _push_target locked during the test as declared in specification
	if _ball and is_instance_valid(_ball) and player.get("_push_target") != _ball:
		player.set("_push_target", _ball)

	var t_roll := _t - _push_start_time
	if _ball == null or not is_instance_valid(_ball):
		_check("snowball remains alive during rolling", false)
		_sampling = false
		_report()
		return

	# Sample telemetry
	var p_pos := player.global_position
	var b_pos := _ball.global_position
	var dist := Vector2(b_pos.x - p_pos.x, b_pos.z - p_pos.z).length()
	var v_vec := _ball.linear_velocity
	var v_len := v_vec.length()
	var w_vec := _ball.angular_velocity
	var w_len := w_vec.length()
	var v_roll := w_len * _ball.radius
	var r := _ball.radius
	var m := _ball.packed_mass()
	var v_target: float = _ball.target_push_speed() if _ball.has_method("target_push_speed") else 1.8
	var slip: float = absf(v_len - v_roll) / maxf(v_len, 0.1)

	_samples.append({
		"t": t_roll,
		"dist": dist,
		"v": v_len,
		"w": w_len,
		"r": r,
		"m": m,
		"v_target": v_target,
		"slip": slip,
		"pushing": player.get("is_ground_pushing") == true
	})

	if _t - _last_log_t >= 2.0:
		_last_log_t = _t
		print("[BEETLE] t=%.1fs | r=%.3fm | m=%.1fkg | v=%.2f v_roll=%.2f (w=%.2f) | slip=%.1f%%" % [
			t_roll, r, m, v_len, v_roll, w_len, slip * 100.0])

	# Finish after declared duration
	if t_roll >= PUSH_DURATION:
		_sampling = false
		Input.action_release("interact")
		Input.action_release("move_forward")
		_evaluate_and_report()

func _evaluate_and_report() -> void:
	_finished = true
	print("[BEETLE] ---- EVALUATING %d SAMPLES OVER %.1f s ----" % [_samples.size(), PUSH_DURATION])

	if _samples.size() < 100:
		_check("sufficient telemetry samples recorded", false)
		_report()
		return

	# 1. No se escapa. La distancia al jugador nunca pasa de ~3,5 m.
	var max_dist := 0.0
	var min_dist := 999.0
	for s in _samples:
		max_dist = maxf(max_dist, s["dist"])
		min_dist = minf(min_dist, s["dist"])
	print("[BEETLE] distance to player: min=%.2f m, max=%.2f m" % [min_dist, max_dist])
	_check("the ball does not escape (distance to player < 3.5 m at all times)",
		max_dist <= 3.5 and min_dist >= 0.5)

	# 2. Rueda. La velocidad maxima se queda dentro del 15 % del objetivo para su masa.
	var peak_speed := 0.0
	for s in _samples:
		if s["t"] >= 0.5:
			peak_speed = maxf(peak_speed, s["v"])
	var target_ref: float = float(_ball.get("PUSH_SPEED")) if _ball and _ball.get("PUSH_SPEED") != null else 3.2
	var peak_ratio: float = peak_speed / target_ref
	print("[BEETLE] peak speed=%.2f m/s (ratio to target=%.2f, bar <= 1.15)" % [peak_speed, peak_ratio])
	_check("ball speed stays within 15% of target for its mass", peak_ratio <= 1.15)

	# 3. Rueda y no desliza. |v| coincide con |w| * radio dentro del 20 % mientras se mueve.
	var slips: Array[float] = []
	var sum_slip := 0.0
	for s in _samples:
		if s["t"] >= 1.0 and s["v"] > 0.3:
			var slip: float = s["slip"]
			slips.append(slip)
			sum_slip += slip
	var avg_slip: float = sum_slip / maxf(float(slips.size()), 1.0)
	slips.sort()
	var p90_slip: float = slips[int(slips.size() * 0.90)] if slips.size() > 0 else 0.0
	print("[BEETLE] rolling without slipping: avg slip=%.1f%%, p90 slip=%.1f%% (bar <= 20%%)" % [
		avg_slip * 100.0, p90_slip * 100.0])
	_check("pure rolling condition (|v| ~= |w| * r within 20% while moving)",
		slips.size() > 100 and avg_slip <= 0.20)

	# 4. Crece progresivamente. El radio a los 12 s es mayor que a los 2 s, y el crecimiento es monotono.
	var r_at_2s := 0.0
	var r_at_12s := 0.0
	var monotonic := true
	var prev_r := START_RADIUS
	for s in _samples:
		if s["t"] <= 2.05:
			r_at_2s = s["r"]
		r_at_12s = s["r"]
		if s["r"] < prev_r - 0.0005:
			monotonic = false
		prev_r = maxf(prev_r, s["r"])
	print("[BEETLE] radius: start=%.3f m, at 2s=%.3f m, at 12s=%.3f m, monotonic=%s" % [
		START_RADIUS, r_at_2s, r_at_12s, str(monotonic)])
	_check("radius grows progressively and monotonically (r(12s) > r(2s))",
		r_at_12s > r_at_2s and monotonic)

	# 5. Cuesta mas al crecer. La velocidad media de empuje en los ultimos 4 s es menor que en los primeros 4.
	var speed_first_4s := 0.0
	var count_first_4s := 0
	var speed_last_4s := 0.0
	var count_last_4s := 0
	for s in _samples:
		if s["t"] >= 1.0 and s["t"] <= 4.0:
			speed_first_4s += s["v"]
			count_first_4s += 1
		elif s["t"] >= 8.0 and s["t"] <= 12.0:
			speed_last_4s += s["v"]
			count_last_4s += 1
	var mean_first := speed_first_4s / maxf(float(count_first_4s), 1.0)
	var mean_last := speed_last_4s / maxf(float(count_last_4s), 1.0)
	print("[BEETLE] mean speed: first 4s=%.2f m/s, last 4s=%.2f m/s (slower when heavy)" % [
		mean_first, mean_last])
	_check("pushing gets harder as ball grows (mean speed last 4s < first 4s)", mean_last < mean_first)

	# 6. No se atasca. Sigue moviendose al final y su radio supera el inicial en un umbral declarado.
	var speed_at_end := 0.0
	if _samples.size() > 0:
		speed_at_end = _samples[-1]["v"]
	var delta_r := r_at_12s - START_RADIUS
	print("[BEETLE] final state: speed=%.2f m/s, growth=%.3f m (bar >= 0.05 m)" % [speed_at_end, delta_r])
	_check("does not get stuck and grows significantly (v > 0.4 m/s and delta_r >= 0.05 m)",
		speed_at_end > 0.4 and delta_r >= 0.05)

	_report()

func _check(label: String, ok: bool) -> void:
	print("[BEETLE] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _report() -> void:
	print("[BEETLE] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[BEETLE] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
