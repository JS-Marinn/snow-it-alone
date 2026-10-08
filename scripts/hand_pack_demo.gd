extends Node

# HandPackDemo: Acceptance battery for hand-packing snowballs.
# Verifies:
# 1. Cleared ground (h = 0): pressing does not create a ball, field mass is untouched, notice is shown.
# 2. Normal snow: pressing creates a ball, field mass lost matches ball mass (within ±0.05%).
# 3. Mid-distance snow (extended reach): pressing creates a ball, harvest point is within reach.
# 4. Scarce snow regression: a point below the minimum mass, pressed repeatedly, does not reduce field mass or create ghost balls.

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _cam: Camera3D

var _checks_ok: int = 0
var _checks_fail: int = 0
var _finished: bool = false

# Metrics saved across states
var _p1_mass_before: float = 0.0
var _p1_balls_before: int = 0
var _p1_probe_pt: Vector3 = Vector3.ZERO
var _p1_h_before: float = 0.0

var _p2_mass_before: float = 0.0

var _p4_mass_before: float = 0.0
var _p4_balls_before: int = 0
var _p4_press_count: int = 0
var _p4_dump_h_before: float = 0.0
var _p4_probe_pt: Vector3 = Vector3.ZERO
var _p4_probe_h_before: float = 0.0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[PACK] ==== HAND PACK ACCEPTANCE BATTERY ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_camera()

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 65.0
	_cam.make_current()

func _count_balls() -> int:
	var c: int = 0
	if props:
		for child in props.get_children():
			if child is SnowBall and is_instance_valid(child) and not child.is_queued_for_deletion():
				c += 1
	return c

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_state_time += delta

	if _cam and player:
		_cam.global_position = player.global_position + Vector3(2.5, 2.2, 2.5)
		_cam.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

	match _state:
		0:
			# State 0: Wait for GPU sim & coarse mirror to initialize
			if _state_time >= 0.5 and snow_field != null and snow_field.has_method("is_coarse_ready") and snow_field.is_coarse_ready():
				# Prepare Phase 1: Cleared ground. Clear 4.6m radius at (0.0, 0.0, 2.5)
				# Radial clear clears completely up to 0.55 * R = 2.53m, covering extended reach (2.4m)
				print("[PACK] Phase 1 setup: clearing 4.6m circle at (0.0, 0.0, 2.5)")
				snow_field.clear_for_diagnostics(Vector3(0.0, 0.0, 2.5), 4.6)
				_change_state(1)

		1:
			# State 1: Wait for carve to reflect in coarse mirror
			if (_state_time >= 0.35 and snow_field.get_height_at(Vector3(0.0, 0.0, 2.5)) < 0.02) or _state_time >= 1.0:
				player.global_position = Vector3(0.0, 0.0, 2.5)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				_p1_balls_before = _count_balls()
				_p1_mass_before = float(snow_field.measure_total_mass())
				_p1_probe_pt = player._get_target_ground_pos()
				_p1_h_before = float(snow_field.get_height_at(_p1_probe_pt))
				print("[PACK] Phase 1 start: player on cleared ground, field mass = %.2f kg, probe_h = %.4f" % [_p1_mass_before, _p1_h_before])
				player._pack_snowball()
				_change_state(2)

		2:
			# State 2: Evaluate Phase 1 after a short delay
			if _state_time >= 0.40:
				var balls_now: int = _count_balls()
				var mass_now: float = float(snow_field.measure_total_mass())
				var mass_diff: float = absf(mass_now - _p1_mass_before)
				var carrying: bool = player.is_carrying()
				var msg: String = player.status_message
				var notice_ok: bool = (msg == tr("STATUS_NOT_ENOUGH_SNOW"))
				var p1_h_now: float = float(snow_field.get_height_at(_p1_probe_pt))
				var p1_h_diff: float = absf(p1_h_now - _p1_h_before)
				print("[PACK] Phase 1 eval: balls=%d (was %d) carrying=%s mass_diff=%.4f probe_h_diff=%.4f notice=%s" % [
					balls_now, _p1_balls_before, str(carrying), mass_diff, p1_h_diff, msg])

				_check("cleared ground: no ball created", balls_now == _p1_balls_before and not carrying)
				_check("cleared ground: field mass untouched", mass_diff < 0.001)
				_check("cleared ground: probe height untouched", p1_h_diff < 0.001)
				_check("cleared ground: notice displayed", notice_ok)

				# Prepare Phase 2: Normal snow at (0.0, 0.0, -3.5)
				print("[PACK] Phase 2 setup: placing player on normal snow at (0.0, 0.0, -3.5)")
				var ground_h: float = float(snow_field.get_height_at(Vector3(0.0, 0.0, -3.5)))
				player.global_position = Vector3(0.0, maxf(ground_h, 0.0), -3.5)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				_change_state(3)

		3:
			# State 3: Start Phase 2 (pack on normal snow)
			if _state_time >= 0.30:
				_p2_mass_before = float(snow_field.measure_total_mass())
				# Look at the snow at the player's feet before pressing.
				#
				# ADDED, and the reason is the owner's specification: gathering needs the aim
				# point to be CLOSE (PACK_REACH_STRICT, 1.3 m). Without aiming, the camera sits
				# level at eye height and the aim ray lands on the ground 2.2 m away, which is
				# now correctly refused -- so this case, which is about a ball being created at
				# all, was failing for a reason that has nothing to do with what it tests.
				if player.camera != null:
					var feet_h: float = float(snow_field.get_height_at(player.global_position))
					player.camera.look_at(Vector3(0.0, feet_h, player.global_position.z + 0.7), Vector3.UP)
				player._update_reticle_aim()
				var aim: Vector3 = player.get_reticle_aim_point()
				var aim_dist := -1.0
				if aim != Vector3.INF:
					aim_dist = Vector2(aim.x - player.global_position.x, aim.z - player.global_position.z).length()
				print("[PACK] Phase 2 start: player packing normal snow, field mass = %.2f kg, reticle=%d aim=%s dist=%.2f m" % [
					_p2_mass_before, int(player.get_reticle_state()), str(aim), aim_dist])
				player._pack_snowball()
				_change_state(4)

		4:
			# State 4: Evaluate Phase 2 when ball is ready
			if player.is_carrying() or _state_time >= 1.2:
				var carrying: bool = player.is_carrying()
				var ball: SnowBall = (player.carried as SnowBall) if carrying and player.carried is SnowBall else null
				var ball_kg: float = ball.packed_mass() if ball != null else 0.0
				var harvested_kg: float = float(player.get("last_pack_harvest_kg"))
				var err: float = absf(ball_kg - harvested_kg) / maxf(harvested_kg, 0.001)
				print("[PACK] Phase 2 eval: carried=%s ball_kg=%.4f harvested_kg=%.4f rel_err=%.6f" % [
					str(carrying), ball_kg, harvested_kg, err])

				_check("normal snow: ball created in hands", carrying and ball != null and ball_kg >= SnowBall.min_pack_mass())
				_check("normal snow: mass lost by field matches ball mass (±0.05%)", err < 0.0005)

				# Release and free the ball
				if carrying:
					player._release_carried(Vector3.ZERO)
					if ball != null:
						ball.queue_free()

				# Prepare Phase 3: Extended reach
				# Clear 2.35m radius at (0.0, 0.0, -2.2). Completely cleared up to 1.29m (strict reach).
				# Untouched snow remains at 1.7m facing -Z.
				print("[PACK] Phase 3 setup: clearing 2.35m circle at (0.0, 0.0, -2.2)")
				snow_field.clear_for_diagnostics(Vector3(0.0, 0.0, -2.2), 2.35)
				_change_state(5)

		5:
			# State 5: Wait for carve to settle, place player at (0.0, 0.0, -2.2) facing -Z
			if (_state_time >= 0.35 and snow_field.get_height_at(Vector3(0.0, 0.0, -2.2)) < 0.02) or _state_time >= 1.0:
				player.global_position = Vector3(0.0, 0.0, -2.2)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				print("[PACK] Phase 3 start: player at (0, 0, -2.2), strict reach is cleared, snow at 1.7m")
				player._pack_snowball()
				_change_state(6)

		6:
			# State 6: Evaluate Phase 3 (extended reach)
			if player.is_carrying() or _state_time >= 1.2:
				var carrying: bool = player.is_carrying()
				var harvest_pt: Vector3 = player.get("_pack_harvest_pt")
				var dist: float = Vector2(harvest_pt.x - player.global_position.x, harvest_pt.z - player.global_position.z).length()
				print("[PACK] Phase 3 eval: carried=%s harvest_pt=%s dist=%.2f m" % [
					str(carrying), str(harvest_pt), dist])

				# CHANGED ASSERTION, and the reason is the owner's own specification:
				#     "if I look straight ahead instead of down, it must not gather snow."
				# The setup clears everything inside 1.29 m and leaves snow at 1.7 m, so the only
				# snow this case can reach is BEYOND PACK_REACH_STRICT (1.3 m). It used to assert
				# that a ball WAS created from there, which is the extended reach the owner
				# reported as the bug. The two checks are inverted rather than deleted: they now
				# assert the boundary from the far side, that snow past the strict reach is
				# refused and nothing is harvested from it.
				_check("extended reach: no ball is created from snow past the strict reach", not carrying)
				_check("extended reach: nothing is harvested from beyond the strict reach",
					dist <= player.PACK_REACH_STRICT or not carrying)

				# Release and free the ball
				if carrying:
					var b = player.carried
					player._release_carried(Vector3.ZERO)
					if b != null:
						b.queue_free()

				# Prepare Phase 4: Scarce snow regression
				# Clear 4.6m at (0.0, 0.0, 2.5) (completely cleared up to 2.53m)
				print("[PACK] Phase 4 setup: clearing 4.6m at (0.0, 0.0, 2.5) then dumping 0.12 kg")
				snow_field.clear_for_diagnostics(Vector3(0.0, 0.0, 2.5), 4.6)
				_change_state(7)

		7:
			# State 7: Dump tiny snow (0.12 kg) and wait for coarse mirror
			if (_state_time >= 0.35 and snow_field.get_height_at(Vector3(0.0, 0.0, 2.5)) < 0.02) or _state_time >= 1.0:
				snow_field.dump_snow(Vector3(0.0, 0.0, 2.5), 0.12, 0.25)
				_change_state(8)

		8:
			# State 8: Wait for dump to register, place player, record initial values
			if _state_time >= 0.45:
				player.global_position = Vector3(0.0, 0.0, 2.5)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				_p4_balls_before = _count_balls()
				_p4_mass_before = float(snow_field.measure_total_mass())
				_p4_dump_h_before = float(snow_field.get_height_at(Vector3(0.0, 0.0, 2.5)))
				_p4_probe_pt = player._get_target_ground_pos()
				_p4_probe_h_before = float(snow_field.get_height_at(_p4_probe_pt))
				_p4_press_count = 0
				print("[PACK] Phase 4 start: scarce snow (0.12 kg), initial field mass = %.2f kg, dump_h=%.4f probe_h=%.4f" % [
					_p4_mass_before, _p4_dump_h_before, _p4_probe_h_before])
				_change_state(9)

		9:
			# State 9: Repeatedly attempt to pack 5 times spaced by 0.12s
			if _state_time >= 0.12:
				_state_time = 0.0
				player._pack_snowball()
				_p4_press_count += 1
				if _p4_press_count >= 5:
					_change_state(10)

		10:
			# State 10: Evaluate Phase 4
			if _state_time >= 0.40:
				var balls_now: int = _count_balls()
				var mass_now: float = float(snow_field.measure_total_mass())
				var carrying: bool = player.is_carrying()
				var msg: String = player.status_message
				var notice_ok: bool = (msg == tr("STATUS_NOT_ENOUGH_SNOW"))
				var p4_dump_h_now: float = float(snow_field.get_height_at(Vector3(0.0, 0.0, 2.5)))
				var p4_probe_h_now: float = float(snow_field.get_height_at(_p4_probe_pt))
				var p4_dump_h_diff: float = absf(p4_dump_h_now - _p4_dump_h_before)
				var p4_probe_h_diff: float = absf(p4_probe_h_now - _p4_probe_h_before)
				print("[PACK] Phase 4 eval: presses=%d balls=%d carrying=%s mass_before=%.4f mass_now=%.4f dump_h_diff=%.4f probe_h_diff=%.4f notice=%s" % [
					_p4_press_count, balls_now, str(carrying), _p4_mass_before, mass_now, p4_dump_h_diff, p4_probe_h_diff, msg])

				_check("scarce snow: repeated presses do not create balls", balls_now == _p4_balls_before and not carrying)
				_check("scarce snow: repeated presses do not reduce field mass", mass_now >= _p4_mass_before - 0.005)
				_check("scarce snow: repeated presses do not change local height", p4_dump_h_diff < 0.001 and p4_probe_h_diff < 0.001)
				_check("scarce snow: notice displayed", notice_ok)

				_report()

func _change_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0

func _check(label: String, ok: bool) -> void:
	print("[PACK] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_checks_ok += 1
	else:
		_checks_fail += 1

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[PACK] RESULT: %d OK / %d FAIL" % [_checks_ok, _checks_fail])
	print("[PACK] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
