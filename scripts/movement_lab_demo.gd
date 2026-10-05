extends Node

# MovementLab: measures surface friction, air control and the bunny hop.
#
# Runs scripted input inside the real level, because the snow simulation only
# exists there. Every test resets the player to the same spot so the numbers can
# be compared against each other.

const SPAWN_Z: float = 8.0
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
var _run_peak: float = 0.0

var v_walk: float = 0.0
var v_sprint: float = 0.0
var v_cold: float = 0.0
var cold_peak: float = 0.0
var pre_scrub: float = 0.0
var v_chain: float = 0.0
var chain_peak: float = 0.0
var chain_jumps: int = 0
var v_powder: float = 0.0
var v_packed_walk: float = 0.0
var walk_peak: float = 0.0
var sprint_peak: float = 0.0
var profile_virgin: String = ""
var profile_packed: String = ""

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
		[4.4, _s_sprint_stop],
		[4.8, _s_cold_start],
		[5.4, _s_cold_jump],
		[5.7, _s_cold_release],
		[6.05, _s_cold_pre_scrub],
		[6.2, _s_cold_measure],
		[6.5, _s_cold_stop],
		[6.8, _s_chain_start],
		[11.4, _s_chain_stop],
		# The chain leaves the simulated field, so the surface probes teleport back
		# and wait for a physics step before reading anything.
		[11.8, _s_go_probe],
		[12.3, _s_probe_virgin],
		[12.6, _s_pack_area],
		[13.1, _s_probe_packed],
		[13.4, _s_packed_walk_start],
		[14.8, _s_packed_walk_stop],
		[15.2, _s_powder_start],
		[16.8, _s_powder_stop],
		[17.2, _s_report],
	]

func _process(delta: float) -> void:
	_t += delta
	while _i < _steps.size() and _t >= float(_steps[_i][0]):
		var fn: Callable = _steps[_i][1]
		fn.call()
		_i += 1
	_pin_view()
	_update_camera()
	_sample(delta)

## Keeps the demo deterministic: a moved mouse would rotate the player and change
## the direction the tests measure.
func _pin_view() -> void:
	if player == null:
		return
	player.rotation.y = 0.0
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.rotation.x = deg_to_rad(-8.0)

func _sample(delta: float) -> void:
	if not _sampling or player == null:
		return
	_sample_t += delta
	if _sample_t < SAMPLE_INTERVAL:
		return
	_sample_t = 0.0
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	_samples.append(speed)
	_peak = maxf(_peak, speed)

func _speed() -> float:
	if player == null:
		return 0.0
	return Vector2(player.velocity.x, player.velocity.z).length()

func _mean() -> float:
	var total := 0.0
	for s in _samples:
		total += s
	return total / maxf(float(_samples.size()), 1.0)

func _check(label: String, ok: bool) -> void:
	print("[MOVE] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _prop(name: String, fallback: float) -> float:
	if player == null:
		return fallback
	return float(player.get(name))

func _reset_player() -> void:
	if player == null:
		return
	var height := 0.32
	if snow_field and snow_field.has_method("get_height_at"):
		height = maxf(snow_field.get_height_at(Vector3(0.0, 0.0, SPAWN_Z)), 0.0)
	player.global_position = Vector3(0.0, height, SPAWN_Z)
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", height)
	player.set("is_ground_initialized", true)
	player.set("is_jumping", false)
	player.set("jump_chain", 0)

func _stop_input() -> void:
	for action in ["move_forward", "sprint", "jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	_sampling = false

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
	v_walk = _mean()
	walk_peak = _peak
	print("[MOVE] walk: mean %.2f m/s, peak %.2f m/s" % [v_walk, walk_peak])
	_stop_input()

func _s_sprint_start() -> void:
	_reset_player()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_start_sampling()
	print("[MOVE] sprinting on untouched snow")

func _s_sprint_stop() -> void:
	v_sprint = _mean()
	sprint_peak = _peak
	print("[MOVE] sprint: mean %.2f m/s, peak %.2f m/s" % [v_sprint, sprint_peak])
	_stop_input()

## One isolated hop at full sprint, no chain: the landing must cost momentum.
func _s_cold_start() -> void:
	_reset_player()
	player.set("auto_bhop", false)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	_start_sampling()
	print("[MOVE] one cold hop at full sprint")

func _s_cold_jump() -> void:
	cold_peak = _speed()
	Input.action_press("jump")
	print("[MOVE] jumping at %.2f m/s" % cold_peak)

func _s_cold_release() -> void:
	Input.action_release("jump")

## The scrub fires a hop window after touchdown; sampling either side of it is the
## only way to see the mechanic itself rather than its aftermath.
func _s_cold_pre_scrub() -> void:
	pre_scrub = _speed()
	print("[MOVE] just before the landing scrub: %.2f m/s (surface %s)" % [
		pre_scrub, String(player.get("surface_name"))])

func _s_cold_measure() -> void:
	v_cold = _speed()
	print("[MOVE] after landing without hopping again: %.2f m/s" % v_cold)

func _s_cold_stop() -> void:
	_stop_input()

## Held jump with auto_bhop: a perfect chain, the ceiling of the skill.
func _s_chain_start() -> void:
	_reset_player()
	player.set("auto_bhop", true)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("jump")
	_start_sampling()
	print("[MOVE] holding jump while sprinting: chained hops")

func _s_chain_stop() -> void:
	v_chain = _speed()
	chain_peak = _peak
	chain_jumps = int(_prop("jump_chain", 0.0))
	print("[MOVE] chain: %.2f m/s at the end, peak %.2f m/s, %d chained jumps" % [
		v_chain, chain_peak, chain_jumps])
	_stop_input()
	player.set("auto_bhop", false)

## Teleports to a known point inside the field. The surface is classified in the
## player's physics step, so nothing can be read until a step has run.
func _s_go_probe() -> void:
	_stop_input()
	_place_player(PROBE_Z)

func _place_player(z: float) -> void:
	var height := 0.32
	if snow_field and snow_field.has_method("get_support_snow_height"):
		height = maxf(snow_field.get_support_snow_height(Vector3(0.0, 0.0, z), 0.35), 0.0)
	player.global_position = Vector3(0.0, height, z)
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", height)
	player.set("is_ground_initialized", true)
	player.set("is_jumping", false)

func _s_probe_virgin() -> void:
	profile_virgin = String(player.get("surface_name"))
	print("[MOVE] surface on untouched snow: %s | raw h=%.3f cohesion=%.2f loose=%.2f" % [
		profile_virgin, _prop("surface_height", -1.0), _prop("surface_cohesion", -1.0),
		_prop("surface_loose", -1.0)])

func _s_pack_area() -> void:
	if snow_field == null or not snow_field.has_method("tamp"):
		return
	# Tamp a long strip through the probe point, the way a player who works the
	# ground would, then read the surface again.
	for i in range(10):
		snow_field.tamp(Vector3(0.0, 0.0, PROBE_Z + 1.5 - float(i) * 0.5), 0.5, 1.0)
	print("[MOVE] tamped a strip through the probe point")

func _s_probe_packed() -> void:
	profile_packed = String(player.get("surface_name"))
	print("[MOVE] surface on tamped snow: %s | raw h=%.3f cohesion=%.2f loose=%.2f" % [
		profile_packed, _prop("surface_height", -1.0), _prop("surface_cohesion", -1.0),
		_prop("surface_loose", -1.0)])

## Walking on ground the player has already packed: this is the contrast that
## gives surface friction its meaning.
func _s_packed_walk_start() -> void:
	_place_player(PROBE_Z + 1.5)
	Input.action_press("move_forward")
	_start_sampling()
	print("[MOVE] walking along the tamped strip")

func _s_packed_walk_stop() -> void:
	v_packed_walk = _peak
	print("[MOVE] packed walk: peak %.2f m/s (surface %s)" % [
		v_packed_walk, String(player.get("surface_name"))])
	_stop_input()

func _s_powder_start() -> void:
	if snow_field == null or not snow_field.has_method("dump_snow"):
		return
	# Dump across the probe strip: fresh shoveled snow is dry and unbonded.
	snow_field.dump_snow(Vector3(0.0, 0.0, PROBE_Z), 60.0, 1.4)
	_place_player(PROBE_Z + 2.0)
	Input.action_press("move_forward")
	_start_sampling()
	print("[MOVE] walking forward into freshly dumped snow")

func _s_powder_stop() -> void:
	v_powder = _mean()
	print("[MOVE] powder: mean %.2f m/s | surface %s raw h=%.3f cohesion=%.2f loose=%.2f" % [
		v_powder, String(player.get("surface_name")), _prop("surface_height", -1.0),
		_prop("surface_cohesion", -1.0), _prop("surface_loose", -1.0)])
	_stop_input()
	_shot("movement")

func _s_report() -> void:
	print("[MOVE] ---- summary ----")
	print("[MOVE] walk %.2f | sprint %.2f | packed walk %.2f | cold hop %.2f | chain %.2f | powder run %.2f" % [
		walk_peak, sprint_peak, v_packed_walk, v_cold, v_chain, v_powder])
	var walk := _prop("walk_speed", 4.2)
	var sprint := _prop("sprint_speed", 6.8)
	var cap := sprint * _prop("bhop_cap_factor", 1.6)

	_check("walking moves the player", walk_peak > walk * 0.5)
	_check("sprinting beats walking", sprint_peak > walk_peak + 0.8)
	_check("packed ground is faster than virgin powder", v_packed_walk > walk_peak + 0.8)
	_check("a hop chain builds speed past sprint", chain_peak > sprint_peak + 0.5)
	_check("the hop respects its ceiling", chain_peak <= cap + 0.05)
	_check("chaining pays: it ends faster than a cold hop", v_chain > v_cold + 0.8)
	_check("landing without hopping scrubs momentum", v_cold < pre_scrub - 0.3)
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
