extends Node

# BallShapeDemo: the snowball must ALWAYS be spherical (--ball-shape).

var root: Node3D
var snow_field: Node3D
var player: Node3D
var props: Node3D

var _t: float = 0.0
var _steps: Array = []
var _i: int = 0
var _cam: Camera3D
var _focus := Vector3.ZERO
var _cam_dist: float = 1.45
var _cam_height: float = 0.06
var _ball: SnowBall = null
var _stack_low: SnowBall = null
var _stack_high: SnowBall = null
var _ok: int = 0
var _fail: int = 0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[BALL] ==== SPHERICAL SHAPE CHECK ====")
	if ply:
		ply.global_position = Vector3(0.0, 0.32, 9.5)
	_setup_camera()
	_steps = [
		[0.8, _s_spawn],
		[1.6, func(): _measure(_ball, "initial ball")],
		[2.0, func(): _grow(0.02)],
		[2.6, func(): _measure(_ball, "after +0.02 m3")],
		[3.0, func(): _grow(0.05)],
		[3.6, func(): _measure(_ball, "after +0.05 m3")],
		[4.0, func(): _grow(0.12)],
		[4.6, func(): _measure(_ball, "after +0.12 m3")],
		[5.0, _s_spawn_stack],
		[7.0, _s_measure_stack],
		[7.6, _s_weight_report],
		# Throw: the airborne path must leave no groove
		[8.0, _s_throw_setup],
		[10.2, _s_throw_check],
		[10.8, _s_summary],
	]

## The ball must become HEAVIER than a plain R3: it compacts as it grows.
func _s_weight_report() -> void:
	var r := 0.12
	var prev_ratio := 0.0
	var line := ""
	while r <= 0.56:
		var dens := SnowBall.density_for_radius(r)
		var mass: float = (4.0 / 3.0) * PI * r * r * r * dens
		var ratio: float = mass / (r * r * r)
		line += "r=%.2f:%.0fkg " % [r, mass]
		prev_ratio = ratio
		r += 0.08
	print("[BALL] mass per radius: %s" % line)
	print("[BALL] density: r=0.12 -> %.0f kg/m3 | r=0.55 -> %.0f kg/m3 (mass/R3 ratio %.0f -> %.0f)" % [
		SnowBall.density_for_radius(0.12), SnowBall.density_for_radius(0.55),
		(4.0 / 3.0) * PI * SnowBall.density_for_radius(0.12),
		prev_ratio])
	_check("the ball gains density as it grows (heavier than R3)",
		SnowBall.density_for_radius(0.55) > SnowBall.density_for_radius(0.12) * 1.4)

var _throw_from := Vector3.ZERO
var _throw_ball: SnowBall = null
var _throw_watching: bool = false
var _throw_landing := Vector3.INF

## Throws a ball from hand height, as the player does when carrying and throwing.
## The mowing anchor is pinned at the throw point.
func _s_throw_setup() -> void:
	_throw_ball = props.spawn_snowball(Vector3(0.8, 0.5, 4.6), 0.14)
	if _throw_ball == null:
		return
	# This test measures the mowing groove, not breaking: breaking is disabled.
	_throw_ball.break_speed_threshold = 999.0
	_throw_ball.begin_carry()
	_throw_ball.global_position = Vector3(0.8, 1.55, 4.6)
	_throw_from = _throw_ball.global_position
	_throw_ball.end_carry(Vector3(0.0, 2.2, -5.0))
	_throw_watching = true
	_throw_landing = Vector3.INF
	_focus = Vector3(0.8, 0.4, 2.4)
	_cam_dist = 6.0
	_cam_height = 2.6
	if _cam:
		_cam.fov = 60.0
	print("[BALL] ball thrown from %s with impulse (0, 2.2, -5.0)" % str(_throw_from))

## Records the first contact with the field: from there on the groove the rolling
## ball leaves is correct and must not be part of the check.
func _watch_throw() -> void:
	if not _throw_watching or _throw_ball == null or not is_instance_valid(_throw_ball):
		return
	if bool(_throw_ball.get("_grounded")):
		_throw_landing = _throw_ball.global_position
		_throw_watching = false
		print("[BALL] landing at %s" % str(_throw_landing))

func _s_throw_check() -> void:
	if _throw_ball == null or not is_instance_valid(_throw_ball):
		return
	var resting := _throw_ball.global_position
	var landing: Vector3 = _throw_landing if _throw_landing != Vector3.INF else resting
	var mid := (_throw_from + landing) * 0.5
	var mid_h := _height(mid)
	var land_h := _height(landing)
	print("[BALL] throw: from %s to %s (flight %.2f m), at rest at %s" % [
		str(_throw_from), str(landing),
		Vector2(landing.x - _throw_from.x, landing.z - _throw_from.z).length(), str(resting)])
	print("[BALL] height at the mid-point of the path: %.3f m (virgin field 0.320) | at the landing: %.3f m" % [
		mid_h, land_h])
	# Profile along the FLIGHT (the landing point itself is excluded, since the
	# ball starts rolling there and its groove is correct): it reveals any mown
	# strip between the launch point and the landing point.
	var line := ""
	var min_h := 99.0
	for i in range(13):
		var t: float = 0.85 * float(i) / 12.0
		var p: Vector3 = _throw_from.lerp(landing, t)
		var hp := _height(p)
		min_h = minf(min_h, hp)
		line += "%.2f " % hp
	print("[BALL] flight profile (deepest=%.3f m): %s" % [min_h, line])
	# A landing used to mow a straight strip from the launch point to the landing
	# point: a "line" in the snow.
	# The BOTTOM of the profile is checked, not only the mid-point: the mown strip
	# can fall in any section, depending on where the ball ends up bouncing.
	_check("the throw does not scratch a line into the field (bottom > 0.28 m)", min_h > 0.28)
	_shot("throw")

func _height(pos: Vector3) -> float:
	if snow_field and snow_field.has_method("get_height_at"):
		return maxf(snow_field.get_height_at(pos), 0.0)
	return 0.0

func _check(label: String, ok: bool) -> void:
	print("[BALL] %s %s" % ["[OK]" if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 45.0
	_update_camera()
	_cam.make_current()

## Side camera at the focus height: perspective cannot fake the silhouette (a
## sphere seen from the side is always a circle).
func _update_camera() -> void:
	if _cam == null:
		return
	_cam.position = _focus + Vector3(0.0, _cam_height, _cam_dist)
	_cam.look_at(_focus, Vector3.UP)

func _process(delta: float) -> void:
	_t += delta
	while _i < _steps.size() and _t >= float(_steps[_i][0]):
		var fn: Callable = _steps[_i][1]
		fn.call()
		_i += 1
	_update_camera()
	_watch_throw()

# Steps
func _s_spawn() -> void:
	_focus = Vector3(-1.25, 0.30, 0.0)
	_ball = props.spawn_snowball(_focus + Vector3(0.0, 0.15, 0.0), 0.12)
	if _ball == null:
		print("[BALL] [FAIL] the ball was not created")
		_fail += 1
		return
	_ball.linear_velocity = Vector3.ZERO
	print("[BALL] ball created with radius %.3f m" % _ball.radius)

func _grow(volume: float) -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	_ball.absorb_loose_volume(volume)

func _s_spawn_stack() -> void:
	var ground: float = maxf(snow_field.get_height_at(Vector3(1.5, 0.0, 1.0)), 0.0)
	_stack_low = props.spawn_snowball(Vector3(1.5, ground + 0.24, 1.0), 0.24)
	if _stack_low == null:
		return
	_stack_low.linear_velocity = Vector3.ZERO
	_stack_low.angular_velocity = Vector3.ZERO
	_stack_high = props.spawn_snowball(Vector3(1.5, ground + 0.24 * 2.0 + 0.16 + 0.01, 1.0), 0.16)
	if _stack_high:
		_stack_high.linear_velocity = Vector3.ZERO
		_stack_high.angular_velocity = Vector3.ZERO
	_focus = Vector3(1.5, ground + 0.34, 1.0)
	_cam_dist = 4.2
	_cam_height = 1.15
	if _cam:
		_cam.fov = 55.0
	print("[BALL] two stacked balls to consolidate the snow weld")

func _s_measure_stack() -> void:
	if _stack_low == null or _stack_high == null or not is_instance_valid(_stack_high):
		return
	# Check that the test is valid: the top ball must still be ON TOP
	var dxz := Vector2(_stack_high.global_position.x - _stack_low.global_position.x,
		_stack_high.global_position.z - _stack_low.global_position.z).length()
	var dy := _stack_high.global_position.y - _stack_low.global_position.y
	print("[BALL] actual stack: drift=%.3f m  dy=%.3f m (expected %.3f)  welded=%s" % [
		dxz, dy, _stack_low.radius + _stack_high.radius, str(_stack_high.is_welded())])
	print("[BALL] positions: lower=%s  upper=%s  camera=%s" % [
		str(_stack_low.global_position), str(_stack_high.global_position), str(_cam.global_position)])
	_measure(_stack_low, "lower stacked ball")
	_measure(_stack_high, "upper stacked ball")

## Measures the rendered sphere: the three axes of the scaled AABB must match.
func _measure(ball, label: String) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var mesh_inst: MeshInstance3D = ball.get("_mesh_instance")
	var sphere: SphereMesh = ball.get("_sphere_mesh")
	var shape: SphereShape3D = ball.get("_shape")
	var scale: Vector3 = mesh_inst.scale if mesh_inst else Vector3.ONE
	var aabb: Vector3 = mesh_inst.get_aabb().size if mesh_inst else Vector3.ZERO
	var rendered := Vector3(aabb.x * scale.x, aabb.y * scale.y, aabb.z * scale.z)
	var ratio_xy: float = rendered.y / maxf(rendered.x, 1e-6)
	var ratio_zy: float = rendered.z / maxf(rendered.y, 1e-6)
	var round_ok: bool = absf(ratio_xy - 1.0) < 0.02 and absf(ratio_zy - 1.0) < 0.02
	print("[BALL] %-26s r=%.4f  mesh(r=%.4f h=%.4f)  scale=(%.3f, %.3f, %.3f)  AABB=(%.4f, %.4f, %.4f)  %.2f kg  %s" % [
		label + ":", ball.radius, sphere.radius if sphere else -1.0, sphere.height if sphere else -1.0,
		scale.x, scale.y, scale.z, rendered.x, rendered.y, rendered.z, ball.packed_mass(),
		"SPHERE OK" if round_ok else "OVAL"])
	print("[BALL]   collision r=%.4f | y/x=%.4f z/y=%.4f" % [
		shape.radius if shape else -1.0, ratio_xy, ratio_zy])
	if round_ok:
		_ok += 1
	else:
		_fail += 1
	_shot(label.replace(" ", "_").replace(",", "").replace("+", ""))

func _s_summary() -> void:
	print("[BALL] RESULT: %d checks OK / %d failures" % [_ok, _fail])
	print("[BALL] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)

func _shot(label: String) -> void:
	# Geometry and mass checks are headless-safe; image capture is not. Waiting on
	# frame_post_draw in headless mode never completes and used to hang the battery before verdict.
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var v_tex := get_viewport().get_texture()
	if v_tex == null:
		return
	var img := v_tex.get_image()
	if img == null:
		return
	var err := img.save_png("res://ball_%s.png" % label)
	print("[BALL] screenshot ball_%s.png (err=%d)" % [label, err])
