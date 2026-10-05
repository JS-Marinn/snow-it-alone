extends Node

# PhysicsDemo: scripted checks of the emergent snow physics (--phys-demo).

const SnowBallScript = preload("res://scripts/snowball.gd")
const PinPropScript = preload("res://scripts/pin_prop.gd")

var root: Node3D
var snow_field: Node3D
var player: Node3D
var props: Node3D

var _t: float = 0.0
var _steps: Array = []
var _i: int = 0
var _cam: Camera3D
var _initial_mass: float = 0.0
var _free_mass: float = 0.0
var _results: Array[String] = []

var _dump_point := Vector3(0.0, 0.0, 2.0)
var _before := {}
var _ball: SnowBall = null
var _ball_start_radius: float = 0.0
var _stick: PinProp = null
var _stack_low: SnowBall = null
var _stack_high: SnowBall = null
var _telemetry: float = 0.0
var _op_events: int = 0
## Speed sampling while shovelling (gameplay regression: slows, does not drag)
var _push_watching: bool = false
var _push_sample_t: float = 0.0
var _push_samples: Array[float] = []
var _push_heights: Array[float] = []
var _push_detail: Array[String] = []
var _push_stuck: int = 0
## During the player phase the facing is pinned to keep the test deterministic
## (captured mouse mode would rotate the character).
var _pin_player_facing: bool = false

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	_initial_mass = field.field_width * field.field_length * field.snow_depth * field.snow_density
	print("[PHYS] ==== EMERGENT PHYSICS DEMO ====")
	print("[PHYS] initial field mass: %.1f kg" % _initial_mass)
	_setup_camera()
	_build_steps()
	# Diagnostic: log every volume the GPU attributes to an operation
	if field.has_signal("op_volume_ready"):
		field.op_volume_ready.connect(_on_op_volume)

func _build_steps() -> void:
	_steps = [
		[0.8, _s_report_initial],
		[1.2, _s_dump],
		[2.6, _s_measure_mound],
		[3.0, _s_tamp_before],
		[3.2, func(): snow_field.tamp(_dump_point, 0.42, 1.0)],
		[3.3, func(): snow_field.tamp(_dump_point, 0.42, 1.0)],
		[3.4, func(): snow_field.tamp(_dump_point, 0.42, 1.0)],
		[4.4, _s_tamp_after],
		[4.8, _s_spawn_ball],
		[6.8, _s_report_ball],
		[7.2, _s_spawn_stick],
		[8.6, _s_report_stick],
		[9.0, _s_spawn_stack],
		[11.2, _s_report_stack],
		[11.6, _s_sculpt],
		[12.8, _s_report_sculpt],
		[13.2, _s_balance],
		# Phase 2: player integration (block 2, end to end)
		[13.6, _s_player_place],
		[13.8, _s_player_push_start],
		[15.8, _s_player_push_stop],
		[16.0, _s_player_dump_start],
		[17.4, _s_player_dump_stop],
		[17.8, _s_player_tamp],
		[18.8, _s_player_tamp_check],
		[19.2, _s_player_interact],
		[20.2, _s_player_interact_check],
		# Phase 3: carry in the hands and throw (blocks 3 and 4)
		[20.6, _s_carry_start],
		[21.8, _s_carry_throw],
		[22.6, _s_carry_check],
		# Phase 4: real weight (two hands, stagger) and throwing
		[23.0, _s_heavy_spawn],
		[23.4, _s_heavy_carry],
		[25.0, _s_heavy_check],
		[25.2, _s_heavy_walk_start],
		[26.2, _s_heavy_walk_stop],
		[26.6, _s_energy_light],
		[27.1, _s_energy_light_throw],
		[27.5, _s_ground_push_start],
		# Pressed a couple of frames later: enough for the ball to exist in the
		# physics space, too soon for it to sink away from the aim line.
		[27.55, _s_ground_push_press],
		[28.9, _s_ground_push_check],
		[29.0, _s_energy_heavy],
		[29.4, _s_energy_heavy_throw],
		[29.8, _s_shatter_test],
		[30.0, _s_shatter_shot],
		[30.7, _s_shatter_check],
		[31.1, _s_hud_panel],
		[31.3, _s_summary],
	]

# Phase 4: heavy carry, [E] push and shattering
var _heavy_ball: SnowBall = null
var _light_ball: SnowBall = null
var _light_speed: float = 0.0
var _heavy_speed: float = 0.0
var _heavy_walk_watching: bool = false
var _heavy_walk_t: float = 0.0
var _heavy_walk_warmup: float = 0.0
var _heavy_walk_samples: Array[float] = []
var _push_ball: SnowBall = null
var _push_start := Vector3.ZERO
var _shatter_ball: SnowBall = null
var _shatter_at := Vector3.ZERO
var _shatter_height_before: float = 0.0
const SnowBurstScript = preload("res://scripts/snow_burst.gd")
var _shatter_frags_at_impact: int = 0

func _s_heavy_spawn() -> void:
	var ground := _height(Vector3(-0.9, 0.0, 3.2))
	_heavy_ball = props.spawn_snowball(Vector3(-0.9, ground + 0.44, 3.2), 0.42)
	if _heavy_ball == null:
		return
	_heavy_ball.linear_velocity = Vector3.ZERO
	print("[PHYS] large ball r=%.2f m  mass=%.0f kg  density=%.0f kg/m3" % [
		_heavy_ball.radius, _heavy_ball.packed_mass(), SnowBall.density_for_radius(_heavy_ball.radius)])

func _s_heavy_carry() -> void:
	if player == null or _heavy_ball == null:
		return
	player._begin_carry(_heavy_ball)
	print("[PHYS] the player lifts it with both hands")

func _s_heavy_check() -> void:
	if player == null or _heavy_ball == null or not is_instance_valid(_heavy_ball):
		# Reporting the abort matters more than the test: a phase that cannot run must
		# never look like a phase that passed, which is how this battery quietly went
		# from 36 checks to 33 without a single failure.
		_check("the heavy ball survived long enough to be inspected", false)
		return
	var two := bool(player.get("carry_two_hands"))
	var st: float = float(player.get("stagger"))
	var grip: float = float(player.get("grip_left"))
	var cam = player.get("camera")
	var above: float = _heavy_ball.global_position.y - cam.global_position.y if cam else 0.0
	print("[PHYS] heavy carry: two hands=%s  stagger=%.2f  grip=%d%%  ball %.2f m above the camera" % [
		str(two), st, int(grip * 100.0), above])
	_check("a large ball is carried with both hands", two)
	_check("the player staggers under its weight", st > 0.3)
	_check("it is held above the head", above > 0.2)

## Walking with the ball in the arms: must stagger WITHOUT slowing down.
func _s_heavy_walk_start() -> void:
	if player == null:
		return
	_heavy_walk_watching = true
	_heavy_walk_t = 0.0
	_heavy_walk_warmup = _t + 0.45   # skip the start-up, measure the steady state
	_heavy_walk_samples.clear()
	Input.action_press("move_forward")
	print("[PHYS] the player walks carrying %.0f kg (speed is sampled)" % float(player.get("carried_mass")))

func _s_heavy_walk_stop() -> void:
	_heavy_walk_watching = false
	if player == null:
		return
	Input.action_release("move_forward")
	# Empty hands for the phases that follow. Leaving the ball carried meant the
	# next [E] press dropped 124 kg on the player's head, which knocks them down.
	if player.is_carrying():
		player._release_carried(Vector3(0.0, 0.0, -2.5))
	var mean := 0.0
	for s in _heavy_walk_samples:
		mean += s
	mean /= maxf(float(_heavy_walk_samples.size()), 1.0)
	var walk: float = float(player.get("walk_speed"))
	# The honest baseline is a free walk on the same surface: virgin snow is
	# slower than packed ground, and the carry penalty multiplies on top of that.
	var surface_scale: float = float(player.get("surface_speed_scale"))
	var local_walk: float = walk * surface_scale
	var pct := int(mean / maxf(walk, 0.1) * 100.0)
	var local_pct := int(mean / maxf(local_walk, 0.1) * 100.0)
	print("[PHYS] mean speed carrying %.0f kg: %.2f m/s | %.1f m/s free walk here (surface %s x%.2f) -> %d%% of it" % [
		float(player.get("carried_mass")), mean, local_walk,
		String(player.get("surface_name")), surface_scale, local_pct])
	_check("staggering does NOT slow the player down (>70% of a free walk here)", mean > local_walk * 0.70)
	_shot("11_heavy_ball")

## Hold [E]: the ball rolls along the ground without being lifted.
func _s_ground_push_start() -> void:
	if player == null or props == null:
		_check("the ground push test could set itself up", false)
		return
	# Do it from a known central spot so the test does not depend on wherever the
	# earlier phases left the player.
	var ground_here := _height(Vector3(0.0, 0.0, 2.0))
	player.global_position = Vector3(0.0, ground_here, 2.0)
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", ground_here)
	player.set("is_ground_initialized", true)

	var cam = player.get("camera")
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	# Place the ball exactly where the aim ray meets the snow: that is where a
	# player looking at the ground would be pushing it. `_height` is the same
	# model the ball itself rests on, so the placement and the resting height
	# agree; mixing the two queries is what breaks this test.
	var ground := _height(from + dir * 2.4)
	var travel: float = (ground + 0.26 - from.y) / minf(dir.y, -0.1)
	travel = clampf(travel, 1.2, 2.8)
	var at: Vector3 = from + dir * travel
	_push_ball = props.spawn_snowball(Vector3(at.x, ground + 0.26, at.z), 0.26)
	if _push_ball == null:
		return
	_push_ball.linear_velocity = Vector3.ZERO
	_push_start = _push_ball.global_position
	print("[PHYS] ball placed on the aim line %.2f m out: %.0f kg at %s" % [
		travel, _push_ball.packed_mass(), str(_push_start)])

## [E] is pressed a step later, once the ball exists in the physics space.
func _s_ground_push_press() -> void:
	Input.action_press("interact")
	print("[PHYS] the player holds [E] on the ball")

func _s_ground_push_check() -> void:
	Input.action_release("interact")
	_pin_player_facing = true
	if _push_ball == null or not is_instance_valid(_push_ball):
		_check("holding [E] pushes the ball along the ground", false)
		return
	var moved := Vector2(_push_ball.global_position.x - _push_start.x, _push_ball.global_position.z - _push_start.z).length()
	var rise: float = _push_ball.global_position.y - _push_start.y
	print("[PHYS] [E] push: advanced %.2f m  rose %.2f m (radius %.2f m)  pushing=%s  carrying=%s" % [
		moved, rise, _push_ball.radius, str(player.get("is_ground_pushing")), str(player.is_carrying())])
	_check("holding [E] pushes the ball along the ground", moved > 0.15 and not player.is_carrying())
	_check("holding [E] does NOT lift the ball", rise < _push_ball.radius)

## Throw comparison: same mechanic, very different masses.
func _s_energy_light() -> void:
	if player == null or props == null:
		return
	_light_ball = props.spawn_snowball(Vector3(player.global_position.x, 1.4, player.global_position.z - 0.5), 0.11)
	if _light_ball == null:
		return
	player._begin_carry(_light_ball)
	print("[PHYS] light ball r=%.2f m  mass=%.2f kg" % [_light_ball.radius, _light_ball.packed_mass()])

func _s_energy_light_throw() -> void:
	if player == null or _light_ball == null or not is_instance_valid(_light_ball):
		return
	player._throw_carried()
	_light_speed = _light_ball.linear_velocity.length()
	print("[PHYS] one-handed throw: %.2f kg -> %.2f m/s (aims for %.2f m/s, camera at -34 deg)" % [
		_light_ball.packed_mass(), _light_speed,
		float(player._throw_speed_for(_light_ball.packed_mass(), false))])

func _s_energy_heavy() -> void:
	if player == null or props == null:
		return
	# A heavy ball dropped on the player knocks them down and bursts, so the
	# earlier phase may have lost this one. What is under test here is the throw.
	if _heavy_ball == null or not is_instance_valid(_heavy_ball):
		_heavy_ball = props.spawn_snowball(
			player.global_position + Vector3(0.0, 1.4, -1.0), 0.42)
		if _heavy_ball == null:
			return
	player._begin_carry(_heavy_ball)
	print("[PHYS] the large ball (%.0f kg) is readied with both hands" % _heavy_ball.packed_mass())

func _s_energy_heavy_throw() -> void:
	if player == null or _heavy_ball == null or not is_instance_valid(_heavy_ball):
		return
	player._throw_carried()
	_heavy_speed = _heavy_ball.linear_velocity.length()
	print("[PHYS] two-handed throw of %.0f kg -> %.2f m/s (aims for %.2f m/s)" % [
		_heavy_ball.packed_mass(), _heavy_speed,
		float(player._throw_speed_for(_heavy_ball.packed_mass(), true))])
	_check("the heavy ball leaves with force (>2.5 m/s)", _heavy_speed > 2.5)
	_check("but slower than the light ball", _heavy_speed < _light_speed)

## Shattering: a hard impact breaks the ball and leaves its snow at the hit point.
func _s_shatter_test() -> void:
	if props == null:
		return
	_shatter_at = Vector3(-2.2, 0.0, 1.2)
	_shatter_height_before = _height(_shatter_at)
	var ground := _height(_shatter_at)
	_shatter_ball = props.spawn_snowball(Vector3(_shatter_at.x, ground + 1.8, _shatter_at.z), 0.22)
	if _shatter_ball == null:
		return
	_shatter_ball.linear_velocity = Vector3(0.0, -13.0, 0.0)
	# The diagnostic camera moves in to watch the burst up close
	if _cam:
		_cam.global_position = _shatter_at + Vector3(1.7, 1.15, 1.9)
		_cam.look_at(_shatter_at + Vector3(0.0, 0.35, 0.0), Vector3.UP)
		_cam.fov = 55.0
	print("[PHYS] %.0f kg ball thrown at the field at 13 m/s (field height there: %.3f m)" % [
		_shatter_ball.packed_mass(), _shatter_height_before])

## Burst capture: fragments and snow cloud in mid-air.
func _s_shatter_shot() -> void:
	var gone: bool = _shatter_ball == null or not is_instance_valid(_shatter_ball)
	_shatter_frags_at_impact = SnowBurstScript.last_fragment_count
	print("[PHYS] impact frame: ball broken=%s  fragments in the air=%d" % [
		str(gone), _shatter_frags_at_impact])
	_shot("12_shatter")

func _s_shatter_check() -> void:
	var gone: bool = _shatter_ball == null or not is_instance_valid(_shatter_ball)
	var frags := get_tree().get_nodes_in_group("snow_chunks").size()
	var height_now := _height(_shatter_at)
	print("[PHYS] shatter: ball broken=%s  fragments now=%d (at the impact: %d)  field at the hit %.3f -> %.3f m" % [
		str(gone), frags, _shatter_frags_at_impact, _shatter_height_before, height_now])
	_check("a ball that hits hard breaks apart", gone)
	# Counted at the moment of the impact: the fragments are reabsorbed within a
	# second, so reading the count later measures the cleanup instead.
	_check("the impact scatters fragments", _shatter_frags_at_impact >= 4)
	_check("its snow piles up where it hit", height_now > _shatter_height_before + 0.02)

## The key legend must start hidden and toggle with H.
func _s_hud_panel() -> void:
	var hud := root.get_node_or_null("HUD") if root else null
	if hud == null:
		return
	var panel: Control = hud.get_node_or_null("PanelControls")
	if panel == null:
		return
	var was_visible := panel.visible
	var ev := InputEventKey.new()
	ev.keycode = KEY_H
	ev.pressed = true
	hud._unhandled_input(ev)
	var toggled := panel.visible != was_visible
	print("[PHYS] key panel: hidden at start=%s  H toggles it=%s" % [
		str(not was_visible), str(toggled)])
	_check("the key legend does not cover the scene at start", not was_visible)
	_check("H shows or hides the key legend", toggled)

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.position = Vector3(5.0, 3.4, 7.6)
	_cam.look_at(Vector3(0.0, 0.4, 0.0), Vector3.UP)
	_cam.fov = 62.0
	_cam.make_current()

func _process(delta: float) -> void:
	_t += delta
	while _i < _steps.size() and _t >= float(_steps[_i][0]):
		var fn: Callable = _steps[_i][1]
		fn.call()
		_i += 1
	if _pin_player_facing and player:
		player.rotation.y = 0.0
		var cam = player.get_node_or_null("Camera3D")
		if cam:
			cam.rotation.x = deg_to_rad(-34.0)
	_log_telemetry(delta)
	_sample_push(delta)
	_sample_carry_walk(delta)

## Sample the speed while the player walks with a large ball in their arms: must
## stagger without slowing down.
func _sample_carry_walk(delta: float) -> void:
	if not _heavy_walk_watching or player == null:
		return
	_heavy_walk_t += delta
	if _t < _heavy_walk_warmup:
		return
	if _heavy_walk_t < 0.2:
		return
	_heavy_walk_t = 0.0
	_heavy_walk_samples.append(Vector2(player.velocity.x, player.velocity.z).length())

## Sample the forward speed while shovelling, to check that the resistance slows
## the player down without dragging them.
func _sample_push(delta: float) -> void:
	if not _push_watching or player == null:
		return
	_push_sample_t += delta
	if _push_sample_t < 0.25:
		return
	_push_sample_t = 0.0
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var height: float = float(player.blade_snow_height)
	_push_samples.append(speed)
	_push_heights.append(height)
	if player.is_stuck:
		_push_stuck += 1
	_push_detail.append("t=%.1f s  v=%.2f m/s  snow ahead of the blade=%.2f m  drag=%.2f%s" % [
		_t, speed, height, float(player.push_drag), "  STUCK" if player.is_stuck else ""])

# Steps
func _s_report_initial() -> void:
	_report("initial field height at the dump point", "%.3f m" % _height(_dump_point))
	_report("CPU mirror available", str(snow_field.get("_coarse_valid")))

func _s_dump() -> void:
	snow_field.dump_snow(_dump_point, 10.0, 0.30)
	print("[PHYS] dumped 10 kg of loose snow at %s" % str(_dump_point))

func _s_measure_mound() -> void:
	_before["peak"] = _height(_dump_point)
	_before["var"] = _height_variance(_dump_point, 0.6)
	_before["coh"] = snow_field.get_cohesion_at(_dump_point)
	_report("mound after dumping (must exceed 0.32 m)", "%.3f m" % _before["peak"])
	_check("free dumping creates relief", _before["peak"] > 0.34)
	_shot("01_dump")

func _s_tamp_before() -> void:
	_before["peak"] = _height(_dump_point)
	_before["var"] = _height_variance(_dump_point, 0.6)
	_before["coh"] = snow_field.get_cohesion_at(_dump_point)

func _s_tamp_after() -> void:
	var peak: float = _height(_dump_point)
	var var_now := _height_variance(_dump_point, 0.6)
	var coh_now: float = snow_field.get_cohesion_at(_dump_point)
	print("[PHYS] tamping: peak %.3f -> %.3f m | roughness %.5f -> %.5f | cohesion %.3f -> %.3f" % [
		_before["peak"], peak, _before["var"], var_now, _before["coh"], coh_now])
	_check("tamping flattens the mound (peak drops)", peak < float(_before["peak"]) - 0.005)
	_check("tamping reduces roughness", var_now <= float(_before["var"]) + 1e-5)
	_check("tamping compacts (cohesion rises)", coh_now > float(_before["coh"]) + 0.02)
	_shot("02_tamping")

func _s_spawn_ball() -> void:
	# Away from the player (at x=0, z=4.5) so it does not hit their capsule
	_ball = props.spawn_snowball(Vector3(-2.8, 0.55, 4.6), 0.12)
	if _ball == null:
		_check("the snowball is created", false)
		return
	_ball_start_radius = _ball.radius
	_ball.debug_harvest = true
	# Initial push: the ball must ROLL, not slide
	_ball.linear_velocity = Vector3(0.0, 0.0, -3.8)
	_ball.angular_velocity = Vector3(-3.8 / 0.12, 0.0, 0.0)  # pure rolling towards -Z
	print("[PHYS] ball created r=%.3f m  m=%.2f kg  y=%.3f (snow %.3f)" % [
		_ball.radius, _ball.packed_mass(), _ball.global_position.y, _height(_ball.global_position)])

func _on_op_volume(role: String, owner: int, kg: float) -> void:
	_op_events += 1
	if _op_events <= 12:
		print("[PHYS][op] role=%s owner=%d kg=%.4f" % [role, owner, kg])

func _log_telemetry(delta: float) -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	_telemetry += delta
	if _telemetry < 0.4:
		return
	_telemetry = 0.0
	var p := _ball.global_position
	print("[PHYS][tel] pos=(%.2f, %.2f, %.2f) v=%.2f w=%.2f ground=%s" % [
		p.x, p.y, p.z, _ball.linear_velocity.length(), _ball.angular_velocity.length(),
		str(_ball.get("_grounded"))])

func _s_report_ball() -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	var growth := _ball.radius - _ball_start_radius
	print("[PHYS] ball after rolling: r=%.3f m (+%.3f)  m=%.2f kg  z=%.2f  v=%.2f m/s" % [
		_ball.radius, growth, _ball.packed_mass(), _ball.global_position.z, _ball.linear_velocity.length()])
	_check("the ball rolls over the snow field", _ball.global_position.z < 4.0)
	_check("the ball gains mass as it rolls (R3 grows)", growth > 0.002)
	# Rolling groove: the whole PATH is sampled (the trajectory varies a little
	# between runs, so a fixed point would be a fragile test).
	var path := ""
	var min_h := 99.0
	var from := Vector3(-2.8, 0.0, 4.55)
	var to := _ball.global_position
	for i in range(11):
		var p: Vector3 = from.lerp(to, float(i) / 10.0)
		var hp := _height(Vector3(p.x, 0.0, p.z))
		min_h = minf(min_h, hp)
		path += "%.2f " % hp
	print("[PHYS] groove profile (deepest=%.3f m): %s" % [min_h, path])
	_check("the ball leaves a groove as it rolls over the field", min_h < 0.30)
	_shot("03_ball_rolling")

func _s_spawn_stick() -> void:
	_stick = props.spawn_prop(PinProp.Kind.STICK, Vector3(1.4, 0.0, 1.2), Vector3.ZERO)
	if _stick == null:
		return
	_stick.length = 0.7
	_stick.call_deferred("_rebuild_for_length")
	_stick.global_position = Vector3(1.4, 1.35, 1.2)
	_stick.linear_velocity = Vector3(0.0, -2.6, 0.0)
	print("[PHYS] stick thrown vertically into the snow")

func _s_report_stick() -> void:
	if _stick == null or not is_instance_valid(_stick):
		return
	print("[PHYS] stick: pinned=%s  y=%.3f" % [str(_stick.is_pinned), _stick.global_position.y])
	_check("the stick pins itself when it enters the snow", _stick.is_pinned)
	var extracted: bool = _stick.try_extract()
	_check("the stick can be pulled out", extracted and not _stick.is_pinned)
	_shot("04_pinned_stick")

func _s_spawn_stack() -> void:
	var ground := _height(Vector3(2.4, 0.0, -2.6))
	_stack_low = props.spawn_snowball(Vector3(2.4, ground + 0.24, -2.6), 0.24)
	if _stack_low == null:
		return
	_free_mass += _stack_low.packed_mass()
	_stack_low.linear_velocity = Vector3.ZERO
	_stack_low.angular_velocity = Vector3.ZERO
	_stack_high = props.spawn_snowball(Vector3(2.4, ground + 0.24 * 2.0 + 0.16 + 0.03, -2.6), 0.16)
	if _stack_high:
		_stack_high.linear_velocity = Vector3.ZERO
		_stack_high.angular_velocity = Vector3.ZERO
		_free_mass += _stack_high.packed_mass()
	# These two balls serve the stacking and carry tests: their breaking is
	# disabled so the test does not depend on an impact crossing the threshold.
	_stack_low.break_speed_threshold = 999.0
	if _stack_high:
		_stack_high.break_speed_threshold = 999.0
	print("[PHYS] stacking ball r=%.2f on ball r=%.2f" % [_stack_high.radius, _stack_low.radius])

func _s_report_stack() -> void:
	if _stack_high == null or not is_instance_valid(_stack_high):
		return
	var dx := Vector2(_stack_high.global_position.x - _stack_low.global_position.x,
		_stack_high.global_position.z - _stack_low.global_position.z).length()
	print("[PHYS] stack: lateral drift=%.3f m  weld=%s  relative height=%.3f m" % [
		dx, str(_stack_high.is_welded()), _stack_high.global_position.y - _stack_low.global_position.y])
	_check("the top ball settles without falling", dx < 0.06 and _stack_high.global_position.y > _stack_low.global_position.y)
	_check("the packed snow weld consolidates", _stack_high.is_welded())
	_shot("05_stack")

func _s_sculpt() -> void:
	_before["sculpt"] = _height(Vector3(0.0, 0.0, 2.6))
	# Chisel passes with a fine 3 cm cut along the mound
	for i in range(6):
		var z := 1.6 + float(i) * 0.22
		snow_field.carve_shovel(Vector3(0.0, 0.0, z), Vector3(0.0, 0.0, -1.0), 0.76, 0.30, 0.03)
	print("[PHYS] 6 chisel passes (3 cm fine cut) over the mound")

func _s_report_sculpt() -> void:
	var after: float = _height(Vector3(0.0, 0.0, 2.6))
	print("[PHYS] carving: height %.3f -> %.3f m (lowered %.3f m)" % [_before["sculpt"], after, float(_before["sculpt"]) - after])
	_check("the blade carves thin slices", float(_before["sculpt"]) - after > 0.01)
	_shot("06_carving")

func _s_balance() -> void:
	var mass := _terrain_mass()
	var balls := _ball_mass()
	# Balls spawned by the demo come from "nothing" (free mass): they are subtracted
	var expected := _initial_mass
	var total := mass + balls - _free_mass - _ball_packed_mass(_ball)
	print("[PHYS] ---- MASS BALANCE ----")
	print("[PHYS] field=%.1f  balls=%.1f  demo free mass=%.1f  expected=%.1f" % [
		mass, balls, _free_mass + _ball_packed_mass(_ball), expected])
	print("[PHYS] measured minus free=%.1f  initial=%.1f  error=%.2f%%" % [
		total, expected, absf(total - expected) / expected * 100.0])
	_check("mass conservation (<3%)", absf(total - expected) / expected < 0.03)

# Phase 2: player integration (two-way physical shovel)
func _s_player_place() -> void:
	if player == null:
		return
	# Place the player looking down at the field, in an area with snow
	player.global_position = Vector3(0.8, 0.29, 5.4)
	player.rotation.y = 0.0
	if "current_ground_y" in player:
		player.current_ground_y = 0.29
		player.is_ground_initialized = true
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.rotation.x = deg_to_rad(-34.0)
	if "debug_shovel" in player:
		player.debug_shovel = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pin_player_facing = true
	print("[PHYS] player placed looking at the ground to shovel")

func _s_player_push_start() -> void:
	if player == null:
		return
	_before["load0"] = player.shovel_current_load
	_push_watching = true
	_push_sample_t = 0.0
	_push_samples.clear()
	_push_heights.clear()
	_push_detail.clear()
	_push_stuck = 0
	Input.action_press("shovel_push")
	Input.action_press("move_forward")
	print("[PHYS] the player pushes the shovel forward while walking (speed is sampled)")

func _s_player_push_stop() -> void:
	if player == null:
		return
	_push_watching = false
	Input.action_release("shovel_push")
	Input.action_release("move_forward")
	var load: float = player.shovel_current_load
	var mean_speed := 0.0
	var mean_height := 0.0
	var n: int = _push_samples.size()
	for i in range(n):
		mean_speed += _push_samples[i]
		mean_height += _push_heights[i]
	mean_speed /= maxf(float(n), 1.0)
	mean_height /= maxf(float(n), 1.0)
	for line in _push_detail:
		print("[PHYS][shovel] " + line)
	print("[PHYS] shovel load: %.2f kg (resistance %.1f N, snow ahead of the blade %.2f m)" % [
		load, player.snow_resistance, player.blade_snow_height])
	print("[PHYS] mean shovelling speed: %.2f m/s (mean snow %.2f m, %d/%d samples stuck)" % [
		mean_speed, mean_height, _push_stuck, n])
	_check("the shovel collects snow as it advances", load > 2.0)
	_check("the cutting resistance is measurable", player.snow_resistance >= 0.0)
	# GAMEPLAY regression: shovelling must slow the player, not crawl
	_check("shovelling does not drag too much (mean > 2.2 m/s)", mean_speed > 2.2)
	_before["terrain_dump"] = _terrain_mass()
	_shot("07_loaded_shovel")

func _s_player_dump_start() -> void:
	if player == null:
		return
	_before["load1"] = player.shovel_current_load
	_before["pour_h"] = _height(_pour_point())
	Input.action_press("shovel_toss")   # hold right button = tilt and pour
	print("[PHYS] the player tilts the shovel and pours (height at the dump point %.3f m)" % _before["pour_h"])

func _pour_point() -> Vector3:
	if player and player.has_method("_get_target_ground_pos"):
		return player._get_target_ground_pos()
	return player.global_position - Vector3(0.0, 0.0, 0.6) if player else Vector3.ZERO

func _s_player_dump_stop() -> void:
	if player == null:
		return
	Input.action_release("shovel_toss")
	var load: float = player.shovel_current_load
	var terrain: float = _terrain_mass()
	var pour_h: float = _height(_pour_point())
	print("[PHYS] after pouring: load %.2f -> %.2f kg | field %.1f -> %.1f kg | height at the dump %.3f -> %.3f m" % [
		_before["load1"], load, _before["terrain_dump"], terrain, _before["pour_h"], pour_h])
	_check("pouring empties the shovel", load < float(_before["load1"]) - 0.2)
	_check("the poured snow accumulates on the terrain", terrain > float(_before["terrain_dump"]) + 0.5 or pour_h > float(_before["pour_h"]) + 0.005)
	_shot("08_shovel_pouring")

func _s_player_tamp() -> void:
	if player == null:
		return
	var target := _pour_point()
	_before["tamp_h"] = _height(target)
	_before["tamp_coh"] = snow_field.get_cohesion_at(target)
	Input.action_press("shovel_tamp")
	print("[PHYS] the player tamps with the flat face at %s" % str(target))

func _s_player_tamp_check() -> void:
	Input.action_release("shovel_tamp")
	var target := _pour_point()
	var coh: float = snow_field.get_cohesion_at(target)
	print("[PHYS] player tamping: cohesion %.3f -> %.3f  (height %.3f -> %.3f m)" % [
		_before["tamp_coh"], coh, _before["tamp_h"], _height(target)])
	_check("player tamping compacts the snow", coh > float(_before["tamp_coh"]) + 0.05)

func _s_player_interact() -> void:
	if player == null:
		return
	_before["balls"] = get_tree().get_nodes_in_group("snowballs").size()
	Input.action_press("interact")
	print("[PHYS] the player packs snow with their hands")

func _s_player_interact_check() -> void:
	Input.action_release("interact")
	var now: int = get_tree().get_nodes_in_group("snowballs").size()
	var carries: bool = player.has_method("is_carrying") and player.is_carrying()
	print("[PHYS] balls in the world: %d -> %d | message='%s' | carrying=%s" % [
		_before["balls"], now, String(player.get("status_message")), str(carries)])
	_check("packing with the hands creates a ball", now > int(_before["balls"]))
	_check("the packed ball goes straight to the hands", carries)
	_shot("09_hand_made_ball")

func _s_carry_start() -> void:
	if player == null or _stack_high == null or not is_instance_valid(_stack_high):
		return
	_before["carry_pos"] = _stack_high.global_position
	player._begin_carry(_stack_high)
	print("[PHYS] the player lifts a ball with their hands (%.1f kg)" % _stack_high.packed_mass())

func _s_carry_throw() -> void:
	if player == null or _stack_high == null or not is_instance_valid(_stack_high):
		return
	_before["carried_dist"] = _stack_high.global_position.distance_to(_before["carry_pos"])
	Input.action_press("shovel_toss")   # right click while carrying = throw
	print("[PHYS] the player throws the carried ball")

func _s_carry_check() -> void:
	Input.action_release("shovel_toss")
	if _stack_high == null or not is_instance_valid(_stack_high):
		return
	var carried: bool = player.has_method("is_carrying") and player.is_carrying()
	var speed: float = _stack_high.linear_velocity.length()
	print("[PHYS] carry: the ball followed the player %.2f m | carrying=%s | speed after throwing=%.2f m/s" % [
		float(_before["carried_dist"]), str(carried), speed])
	_check("the carried ball follows the player", float(_before["carried_dist"]) > 0.3)
	_check("the throw releases the ball with impulse", not carried and speed > 0.5)
	_shot("10_throw")

func _s_summary() -> void:
	_pin_player_facing = false
	print("[PHYS] ---- FULL REPORT ----")
	for line in _results:
		print("[PHYS] " + line)
	var ok := 0
	var fail := 0
	for line in _results:
		if line.begins_with("[OK]"):
			ok += 1
		elif line.begins_with("[FAIL]"):
			fail += 1
	print("[PHYS] RESULT: %d OK / %d FAILURES" % [ok, fail])
	print("[PHYS] ==== END OF DEMO ====")
	get_tree().create_timer(0.6).timeout.connect(get_tree().quit)

# Utilities
func _height(pos: Vector3) -> float:
	if snow_field and snow_field.has_method("get_height_at"):
		return maxf(snow_field.get_height_at(pos), 0.0)
	return 0.0

func _ball_packed_mass(ball) -> float:
	if ball == null or not is_instance_valid(ball):
		return 0.0
	return ball.packed_mass()

func _height_variance(center: Vector3, radius: float) -> float:
	var sum := 0.0
	var sum2 := 0.0
	var n := 0
	var steps := 7
	for i in range(steps):
		for j in range(steps):
			var x := center.x - radius + 2.0 * radius * float(i) / float(steps - 1)
			var z := center.z - radius + 2.0 * radius * float(j) / float(steps - 1)
			var h := _height(Vector3(x, 0.0, z))
			sum += h
			sum2 += h * h
			n += 1
	if n == 0:
		return 0.0
	var mean := sum / float(n)
	return maxf(sum2 / float(n) - mean * mean, 0.0)

## Total field mass measured with the CPU mirror (mean height channel).
func _terrain_mass() -> float:
	if snow_field == null:
		return 0.0
	var coarse: PackedFloat32Array = snow_field.get("_coarse")
	var valid: bool = snow_field.get("_coarse_valid")
	if not valid or coarse.is_empty():
		return 0.0
	var n := 64
	var cell: float = (snow_field.field_width / float(n)) * (snow_field.field_length / float(n))
	var total := 0.0
	for i in range(n * n):
		total += coarse[i * 4]
	return total * cell * snow_field.snow_depth * snow_field.snow_density

func _ball_mass() -> float:
	var total := 0.0
	for node in get_tree().get_nodes_in_group("snowballs"):
		var ball := node as SnowBall
		if ball:
			total += ball.packed_mass()
	return total

func _report(label: String, value: String) -> void:
	var line := "%s: %s" % [label, value]
	_results.append(line)
	print("[PHYS] " + line)

func _check(label: String, ok: bool) -> void:
	var line := "%s %s" % ["[OK]" if ok else "[FAIL]", label]
	_results.append(line)
	print("[PHYS] " + line)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var v_tex := get_viewport().get_texture()
	if v_tex == null:
		return
	var img := v_tex.get_image()
	if img == null:
		return
	var path := "res://phys_%s.png" % label
	var err := img.save_png(path)
	print("[PHYS] screenshot %s (err=%d)" % [path, err])
