extends Node

# MovementLab: measures the Quake-style movement model.
#
# Normal movement must be crisp and capped; hopping in a straight line must gain
# nothing; air strafing must gain. Runs inside the real level because the snow
# simulation only exists there.

const SPAWN_Z: float = 8.0
const HOP_Z: float = 2.0
const PROBE_Z: float = 6.0
const SAMPLE_INTERVAL: float = 0.1

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D

var _t: float = 0.0
var _i: int = 0
var _steps: Array = []
var _ok: int = 0
var _fail: int = 0
var _cam: Camera3D

var _sampling: bool = false
var _sample_t: float = 0.0
var _samples: Array[float] = []
var _peak: float = 0.0

## Yaw the lab drives, so the view can be turned deliberately and deterministically.
var _yaw: float = 0.0
## Ideal air strafe: aims the wish direction perpendicular to the velocity.
var _strafe_bot: bool = false
var _stop_watching: bool = false
var _stop_start: float = 0.0
var _stop_time: float = -1.0
var _stop_speed_at_release: float = 0.0

var walk_peak: float = 0.0
var sprint_peak: float = 0.0
var straight_hop_peak: float = 0.0
var strafe_hop_peak: float = 0.0
## Run-up speed reached on the ground just before each hop test.
var straight_run_peak: float = 0.0
var strafe_run_peak: float = 0.0
var packed_walk_peak: float = 0.0
var chain_count: int = 0
var profile_virgin: String = ""
var profile_packed: String = ""
## Surface speed multipliers, which is what the surface model actually promises.
var powder_scale: float = 0.0
var packed_scale: float = 0.0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, _props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	print("[MOVE] ==== MOVEMENT LAB ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_camera()
	_reset_player()
	_steps = [
		[0.6, _reset_player],
		[0.8, _s_walk_start],
		[2.4, _s_walk_stop],
		[2.8, _s_sprint_start],
		[3.8, _s_sprint_stop],
		[4.2, _s_stop_start],
		[5.4, _s_stop_release],
		[6.2, _s_stop_check],
		# Straight hopping: run up to speed on the ground first, then hop without
		# strafing. This is what a normal player does and it must not gain speed.
		[6.6, _s_straight_hop_start],
		[7.6, _s_straight_hop_engage],
		[10.6, _s_straight_hop_stop],
		# Ideal air strafe: same run-up, then strafe. This is the tryhard path and
		# it must pay.
		[11.0, _s_strafe_hop_start],
		[12.0, _s_strafe_hop_engage],
		[17.0, _s_strafe_hop_stop],
		[17.4, _s_go_probe],
		[17.8, _s_probe_virgin],
		[18.1, _s_pack_area],
		[18.6, _s_probe_packed],
		[18.9, _s_packed_walk_start],
		[20.3, _s_packed_walk_stop],
		[20.7, _s_report],
	]

func _process(delta: float) -> void:
	_t += delta
	while _i < _steps.size() and _t >= float(_steps[_i][0]):
		var fn: Callable = _steps[_i][1]
		fn.call()
		_i += 1
	_strafe_bot_step()
	_pin_view()
	_update_camera()
	_sample(delta)
	_watch_stop()

## Keeps the demo deterministic: the yaw is driven by the lab, never by the mouse.
func _pin_view() -> void:
	if player == null:
		return
	player.rotation.y = _yaw
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.rotation.x = deg_to_rad(-8.0)

## The ideal air strafe: the wish direction is kept perpendicular to the velocity,
## which is the geometry the clamped air acceleration rewards most.
func _strafe_bot_step() -> void:
	if not _strafe_bot or player == null:
		return
	var flat := Vector2(player.velocity.x, player.velocity.z)
	if flat.length() < 0.5:
		return
	var perp := Vector2(-flat.y, flat.x).normalized()
	# With only "move_right" held the wish direction is the body's right vector
	# (cos yaw, -sin yaw), so this yaw points it exactly at `perp`.
	_yaw = atan2(-perp.y, perp.x)

func _sample(delta: float) -> void:
	if not _sampling or player == null:
		return
	_sample_t += delta
	if _sample_t < SAMPLE_INTERVAL:
		return
	_sample_t = 0.0
	var speed := _speed()
	_samples.append(speed)
	_peak = maxf(_peak, speed)

func _watch_stop() -> void:
	if not _stop_watching or player == null:
		return
	if _speed() <= 0.15:
		_stop_watching = false
		_stop_time = _t - _stop_start

func _speed() -> float:
	if player == null:
		return 0.0
	return Vector2(player.velocity.x, player.velocity.z).length()

func _mean() -> float:
	var total := 0.0
	for s in _samples:
		total += s
	return total / maxf(float(_samples.size()), 1.0)

func _prop(name: String, fallback: float) -> float:
	if player == null:
		return fallback
	return float(player.get(name))

func _check(label: String, ok: bool) -> void:
	print("[MOVE] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _place_player(z: float) -> void:
	var height := 0.32
	if snow_field and snow_field.has_method("get_support_snow_height"):
		height = maxf(snow_field.get_support_snow_height(Vector3(0.0, 0.0, z), 0.35), 0.0)
	player.global_position = Vector3(0.0, height, z)
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", height)
	player.set("is_ground_initialized", true)
	player.set("is_jumping", false)
	player.set("jump_chain", 0)

func _reset_player() -> void:
	if player == null:
		return
	_yaw = 0.0
	_place_player(SPAWN_Z)

func _stop_input() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "sprint", "jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	_sampling = false
	_strafe_bot = false

func _start_sampling() -> void:
	_samples.clear()
	_peak = 0.0
	_sample_t = SAMPLE_INTERVAL
	_sampling = true

# Steps

func _s_walk_start() -> void:
	_reset_player()
	Input.action_press("move_forward")
	_start_sampling()
	print("[MOVE] walking on untouched snow")

func _s_walk_stop() -> void:
	walk_peak = _peak
	print("[MOVE] walk: mean %.2f m/s, peak %.2f m/s" % [_mean(), walk_peak])
	_stop_input()

func _s_sprint_start() -> void:
	_reset_player()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_start_sampling()
	print("[MOVE] sprinting on untouched snow")

func _s_sprint_stop() -> void:
	sprint_peak = _peak
	print("[MOVE] sprint: mean %.2f m/s, peak %.2f m/s" % [_mean(), sprint_peak])
	_stop_input()

## Releasing the input must stop the player quickly: this is the check that
## normal movement does not feel like walking on ice.
func _s_stop_start() -> void:
	_reset_player()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	print("[MOVE] sprinting up to speed, then letting go")

func _s_stop_release() -> void:
	_stop_speed_at_release = _speed()
	_stop_start = _t
	_stop_time = -1.0
	_stop_watching = true
	_stop_input()
	print("[MOVE] released at %.2f m/s" % _stop_speed_at_release)

func _s_stop_check() -> void:
	if _stop_watching:
		_stop_watching = false
	print("[MOVE] stop: %.2f s (from %.2f m/s, now %.2f m/s)" % [
		_stop_time, _stop_speed_at_release, _speed()])

## Holding forward and hopping: no strafe, so the model must not hand out speed.
func _s_straight_hop_start() -> void:
	_place_player(HOP_Z)
	player.set("auto_bhop", false)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_start_sampling()
	print("[MOVE] running up to speed before hopping straight")

func _s_straight_hop_engage() -> void:
	# Baseline for this exact stretch of ground: the surface is not uniform, so
	# comparing against a run measured elsewhere would be meaningless.
	straight_run_peak = _peak
	_start_sampling()
	player.set("auto_bhop", true)
	Input.action_press("jump")
	print("[MOVE] hopping in a straight line from %.2f m/s" % straight_run_peak)

func _s_straight_hop_stop() -> void:
	straight_hop_peak = _peak
	print("[MOVE] straight hop: peak %.2f m/s" % straight_hop_peak)
	_stop_input()
	player.set("auto_bhop", false)

## Ideal air strafe, hopping: the velocity should climb well past the ground cap.
func _s_strafe_hop_start() -> void:
	_place_player(HOP_Z)
	player.set("auto_bhop", false)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_start_sampling()
	print("[MOVE] running up to speed before the strafe chain")

func _s_strafe_hop_engage() -> void:
	strafe_run_peak = _peak
	_start_sampling()
	player.set("auto_bhop", true)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_press("move_right")
	Input.action_press("jump")
	_strafe_bot = true
	print("[MOVE] hopping with an ideal air strafe from %.2f m/s" % strafe_run_peak)

func _s_strafe_hop_stop() -> void:
	strafe_hop_peak = _peak
	chain_count = int(_prop("jump_chain", 0.0))
	print("[MOVE] strafe hop: peak %.2f m/s, %d chained jumps" % [strafe_hop_peak, chain_count])
	_stop_input()
	player.set("auto_bhop", false)

func _s_go_probe() -> void:
	_place_player(PROBE_Z)

func _s_probe_virgin() -> void:
	profile_virgin = String(player.get("surface_name"))
	powder_scale = _prop("surface_speed_scale", 1.0)
	print("[MOVE] surface on untouched snow: %s | h=%.3f cohesion=%.2f friction=x%.2f" % [
		profile_virgin, _prop("surface_height", -1.0), _prop("surface_cohesion", -1.0),
		_prop("surface_friction", -1.0)])

func _s_pack_area() -> void:
	if snow_field == null or not snow_field.has_method("tamp"):
		return
	for i in range(10):
		snow_field.tamp(Vector3(0.0, 0.0, PROBE_Z + 1.5 - float(i) * 0.5), 0.5, 1.0)
	print("[MOVE] tamped a strip through the probe point")

func _s_probe_packed() -> void:
	profile_packed = String(player.get("surface_name"))
	packed_scale = _prop("surface_speed_scale", 1.0)
	print("[MOVE] surface on tamped snow: %s | h=%.3f cohesion=%.2f friction=x%.2f" % [
		profile_packed, _prop("surface_height", -1.0), _prop("surface_cohesion", -1.0),
		_prop("surface_friction", -1.0)])

func _s_packed_walk_start() -> void:
	_place_player(PROBE_Z + 1.5)
	Input.action_press("move_forward")
	_start_sampling()
	print("[MOVE] walking along the tamped strip")

func _s_packed_walk_stop() -> void:
	packed_walk_peak = _peak
	print("[MOVE] packed walk: peak %.2f m/s" % packed_walk_peak)
	_stop_input()
	_shot("movement")

func _s_report() -> void:
	print("[MOVE] ---- summary ----")
	print("[MOVE] walk %.2f | sprint %.2f | straight hop %.2f | strafe hop %.2f | packed walk %.2f" % [
		walk_peak, sprint_peak, straight_hop_peak, strafe_hop_peak, packed_walk_peak])
	var walk := _prop("walk_speed", 4.2)
	var sprint := _prop("sprint_speed", 6.8)
	var cap := sprint * _prop("bhop_cap_factor", 2.0)

	_check("walking reaches a sensible speed", walk_peak > walk * 0.7 and walk_peak <= walk * 1.15)
	_check("sprinting beats walking", sprint_peak > walk_peak + 0.8)
	_check("letting go stops the player in under half a second", _stop_time > 0.0 and _stop_time < 0.45)
	_check("hopping in a straight line gains nothing", straight_hop_peak <= straight_run_peak + 0.3)
	_check("an air strafe does gain speed", strafe_hop_peak > strafe_run_peak + 1.5)
	_check("the hop respects its ceiling", strafe_hop_peak <= cap + 0.05)
	_check("chained jumps are counted", chain_count > 3)
	# The surfaces are compared by what the model gives them, not by two walks over
	# different stretches of ground: the field is not uniform, so the second one
	# would be measuring the terrain rather than the rule.
	_check("packed ground is a faster surface than powder", packed_scale > powder_scale + 0.15)
	_check("walking on packed snow reaches at least the base speed", packed_walk_peak > walk * 0.98)
	_check("virgin dry snow reads as powder", profile_virgin == "powder")
	_check("tamped snow reads as packed", profile_packed == "packed")

	print("[MOVE] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[MOVE] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var v_tex := get_viewport().get_texture()
	if v_tex == null:
		return
	var img := v_tex.get_image()
	if img == null:
		return
	var err := img.save_png("res://move_%s.png" % label)
	print("[MOVE] screenshot move_%s.png (err=%d)" % [label, err])

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 60.0
	_cam.make_current()

func _update_camera() -> void:
	if _cam == null or player == null:
		return
	_cam.global_position = player.global_position + Vector3(2.8, 1.2, 3.6)
	_cam.look_at(player.global_position + Vector3(0.0, 0.7, -1.5), Vector3.UP)
