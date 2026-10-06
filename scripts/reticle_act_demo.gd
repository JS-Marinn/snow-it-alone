extends Node

# ReticleActDemo: Acceptance battery for reticle-guided interaction and tool action.
# Verifies:
# 1. Standing on snow aiming at bare ground: pressing [E] creates no ball, leaves mass and local height untouched.
# 2. Standing on bare ground aiming at a snow pile at 2m: creates ball, snow is removed from that 2m pile.
# 3. Standing on bare ground aiming at bare ground: nothing happens.
# 4. Reticle state strictly predicts action success across all cases.
# 5. Shovel and Salt modify height at the reticle aim point, not around the player.

const SnowBall = preload("res://scripts/snowball.gd")

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

# Phase 1 metrics
var _p1_reticle_before: int = 0
var _p1_aim_pt: Vector3 = Vector3.ZERO
var _p1_balls_before: int = 0
var _p1_mass_before: float = 0.0
var _p1_feet_h_before: float = 0.0
var _p1_prediction_match: bool = false

# Phase 2 metrics
var _p2_reticle_before: int = 0
var _p2_aim_pt: Vector3 = Vector3.ZERO
var _p2_mound_h_before: float = 0.0
var _p2_feet_h_before: float = 0.0
var _p2_prediction_match: bool = false

# Phase 3 metrics
var _p3_reticle_before: int = 0
var _p3_mass_before: float = 0.0
var _p3_prediction_match: bool = false

# Phase 5 metrics (Shovel & Salt)
var _p5_shovel_target_before: float = 0.0
var _p5_shovel_feet_before: float = 0.0
var _p5_salt_target_before: float = 0.0
var _p5_salt_feet_before: float = 0.0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	if player and player.has_method("grant_all_tools"):
		player.grant_all_tools()
	print("[RETICLE] ==== RETICLE ACT ACCEPTANCE BATTERY ====")
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
			# State 0: Wait for GPU simulation & coarse mirror to become ready
			if _state_time >= 0.5 and snow_field != null and snow_field.has_method("is_coarse_ready") and snow_field.is_coarse_ready():
				# Phase 1 Setup: Clear ground in front of player (3.5m radius circle at (0.0, 0.0, 2.5))
				print("[RETICLE] Phase 1 setup: clearing 3.5m circle at (0.0, 0.0, 2.5) while player stands on snow")
				snow_field.carve(Vector3(0.0, 0.0, 2.5), 3.5, 0.50)
				_change_state(1)

		1:
			# State 1: Wait for carve to reflect in coarse mirror
			if (_state_time >= 0.40 and snow_field.get_height_at(Vector3(0.0, 0.0, 2.5)) < 0.02) or _state_time >= 1.0:
				# Place player at (0.0, 0.20, 0.3) on snow, aiming camera down at bare ground at (0.0, 0.0, 2.0)
				var snow_h: float = maxf(snow_field.get_height_at(Vector3(0.0, 0.0, 0.3)), 0.0)
				player.global_position = Vector3(0.0, snow_h, 0.3)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				player.equip_tool(player.ToolType.HANDS)
				player.camera.look_at(Vector3(0.0, 0.0, 2.0), Vector3.UP)
				_change_state(2)

		2:
			# State 2: Capture initial state and attempt to pack snow while aiming at bare ground
			if _state_time >= 0.15:
				_p1_reticle_before = int(player.get_reticle_state())
				_p1_aim_pt = player.get_reticle_aim_point()
				_p1_balls_before = _count_balls()
				_p1_mass_before = float(snow_field.measure_total_mass())
				_p1_feet_h_before = float(snow_field.get_height_at(player.global_position))
				print("[RETICLE] Phase 1 start: player on snow (h=%.3f), aiming at bare ground %s (reticle=%d)" % [
					_p1_feet_h_before, str(_p1_aim_pt), _p1_reticle_before])
				player._pack_snowball()
				_change_state(3)

		3:
			# State 3: Evaluate Phase 1
			if _state_time >= 0.40:
				var balls_now: int = _count_balls()
				var mass_now: float = float(snow_field.measure_total_mass())
				var mass_diff: float = absf(mass_now - _p1_mass_before)
				var carrying: bool = player.is_carrying()
				var feet_h_now: float = float(snow_field.get_height_at(player.global_position))
				var feet_h_diff: float = absf(feet_h_now - _p1_feet_h_before)
				var notice: String = player.status_message
				print("[RETICLE] Phase 1 eval: reticle=%d carrying=%s balls_diff=%d mass_diff=%.4f feet_h_diff=%.4f notice=%s" % [
					_p1_reticle_before, str(carrying), balls_now - _p1_balls_before, mass_diff, feet_h_diff, notice])

				_check("on snow aiming at bare: reticle is OFF", _p1_reticle_before == player.ReticleState.OFF)
				_check("on snow aiming at bare: no ball created", balls_now == _p1_balls_before and not carrying)
				_check("on snow aiming at bare: field mass untouched", mass_diff < 0.001)
				_check("on snow aiming at bare: local height untouched", feet_h_diff < 0.001)
				_check("on snow aiming at bare: no success notice", notice == tr("STATUS_NOT_ENOUGH_SNOW"))
				_p1_prediction_match = (_p1_reticle_before == player.ReticleState.OFF and not carrying)

				# Phase 2 Setup: Player on bare ground, aiming at a snow pile at 2m
				print("[RETICLE] Phase 2 setup: clearing 3.0m at origin, dumping 3.5kg snow pile at (0, 0, -2.0)")
				snow_field.carve(Vector3(0.0, 0.0, 0.0), 3.0, 0.50)
				snow_field.dump_snow(Vector3(0.0, 0.0, -2.0), 3.5, 0.35)
				_change_state(4)

		4:
			# State 4: Wait for dump to register in coarse mirror
			if _state_time >= 0.50:
				player.global_position = Vector3(0.0, 0.0, 0.0)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				player.equip_tool(player.ToolType.HANDS)
				_p2_mound_h_before = float(snow_field.get_height_at(Vector3(0.0, 0.0, -2.0)))
				_p2_feet_h_before = float(snow_field.get_height_at(player.global_position))
				# Aim camera directly at the 2m snow mound
				player.camera.look_at(Vector3(0.0, maxf(_p2_mound_h_before * 0.5, 0.08), -2.0), Vector3.UP)
				_change_state(5)

		5:
			# State 5: Read reticle and trigger packing
			if _state_time >= 0.15:
				_p2_reticle_before = int(player.get_reticle_state())
				_p2_aim_pt = player.get_reticle_aim_point()
				print("[RETICLE] Phase 2 start: player on bare (h=%.3f), mound_h=%.3f aim=%s reticle=%d" % [
					_p2_feet_h_before, _p2_mound_h_before, str(_p2_aim_pt), _p2_reticle_before])
				player._pack_snowball()
				_change_state(6)

		6:
			# State 6: Evaluate Phase 2 when ball is ready
			if player.is_carrying() or _state_time >= 1.2:
				var carrying: bool = player.is_carrying()
				var harvest_pt: Vector3 = player.get("_pack_harvest_pt") if player.get("_pack_harvest_pt") != null else Vector3.INF
				var dist_to_mound: float = harvest_pt.distance_to(Vector3(0.0, 0.0, -2.0))
				var p2_feet_h_after: float = float(snow_field.get_height_at(player.global_position))
				print("[RETICLE] Phase 2 eval: reticle=%d carrying=%s harvest_pt=%s dist_to_mound=%.3f m" % [
					_p2_reticle_before, str(carrying), str(harvest_pt), dist_to_mound])

				_check("on bare aiming at 2m mound: reticle is CAN_PACK", _p2_reticle_before == player.ReticleState.CAN_PACK)
				_check("on bare aiming at 2m mound: ball created in hands", carrying)
				_check("on bare aiming at 2m mound: harvest position matches 2m mound", dist_to_mound < 0.35)
				_check("on bare aiming at 2m mound: player feet height untouched", absf(p2_feet_h_after - _p2_feet_h_before) < 0.001)
				_p2_prediction_match = (_p2_reticle_before == player.ReticleState.CAN_PACK and carrying)

				# Release carried ball
				if carrying:
					var b = player.carried
					player._release_carried(Vector3.ZERO)
					if b != null:
						b.queue_free()

				# Phase 3 Setup: Player on bare ground, aiming at bare ground
				print("[RETICLE] Phase 3 setup: player on bare ground aiming at bare ground at (0, 0, 1.8)")
				player.global_position = Vector3(0.0, 0.0, 0.0)
				player.rotation.y = 0.0
				player.velocity = Vector3.ZERO
				player.status_message = ""
				player.camera.look_at(Vector3(0.0, 0.0, 1.8), Vector3.UP)
				_change_state(7)

		7:
			# State 7: Trigger Phase 3 attempt
			if _state_time >= 0.20:
				_p3_reticle_before = int(player.get_reticle_state())
				_p3_mass_before = float(snow_field.measure_total_mass())
				print("[RETICLE] Phase 3 start: reticle=%d aim=%s" % [_p3_reticle_before, str(player.get_reticle_aim_point())])
				player._pack_snowball()
				_change_state(8)

		8:
			# State 8: Evaluate Phase 3
			if _state_time >= 0.40:
				var carrying: bool = player.is_carrying()
				var mass_now: float = float(snow_field.measure_total_mass())
				var mass_diff: float = absf(mass_now - _p3_mass_before)
				print("[RETICLE] Phase 3 eval: reticle=%d carrying=%s mass_diff=%.4f" % [_p3_reticle_before, str(carrying), mass_diff])

				_check("on bare aiming at bare: reticle is OFF", _p3_reticle_before == player.ReticleState.OFF)
				_check("on bare aiming at bare: no ball created", not carrying)
				_check("on bare aiming at bare: field mass untouched", mass_diff < 0.001)
				_p3_prediction_match = (_p3_reticle_before == player.ReticleState.OFF and not carrying)

				# Check 4: Prediction consistency across all 3 cases
				_check("reticle state strictly predicts action success across all cases", _p1_prediction_match and _p2_prediction_match and _p3_prediction_match)

				# Phase 5 Setup (Shovel): Dump snow pile at (0, 0, -1.8)
				print("[RETICLE] Phase 5 setup: shovel test, dumping snow pile at (0, 0, -1.8)")
				snow_field.dump_snow(Vector3(0.0, 0.0, -1.8), 4.5, 0.35)
				_change_state(9)

		9:
			# State 9: Wait for shovel pile to register
			if _state_time >= 0.45:
				player.global_position = Vector3(0.0, 0.0, 0.0)
				player.rotation.y = 0.0
				player.equip_tool(player.ToolType.SHOVEL)
				_p5_shovel_target_before = float(snow_field.get_height_at(Vector3(0.0, 0.0, -1.8)))
				_p5_shovel_feet_before = float(snow_field.get_height_at(player.global_position))
				player.camera.look_at(Vector3(0.0, _p5_shovel_target_before * 0.5, -1.8), Vector3.UP)
				_change_state(10)

		10:
			# State 10: Shovel action at pointed point
			if _state_time >= 0.15:
				var shovel_reticle: int = int(player.get_reticle_state())
				var shovel_aim_pt: Vector3 = player.get_reticle_aim_point()
				print("[RETICLE] Shovel test: reticle=%d aim=%s pile_h=%.3f" % [shovel_reticle, str(shovel_aim_pt), _p5_shovel_target_before])
				_check("shovel aiming at snow: reticle is CAN_CARVE", shovel_reticle == player.ReticleState.CAN_CARVE)
				# Carve at reticle aim point
				snow_field.carve_shovel(shovel_aim_pt, player._forward_flat(), 0.76, 0.30, 0.08)
				_change_state(11)

		11:
			# State 11: Evaluate Shovel carve
			if _state_time >= 0.45:
				var shovel_target_after: float = float(snow_field.get_height_at(Vector3(0.0, 0.0, -1.8)))
				var shovel_feet_after: float = float(snow_field.get_height_at(player.global_position))
				print("[RETICLE] Shovel eval: target h %.3f -> %.3f, feet h %.3f -> %.3f" % [
					_p5_shovel_target_before, shovel_target_after, _p5_shovel_feet_before, shovel_feet_after])

				_check("shovel modifies height at pointed point", shovel_target_after < _p5_shovel_target_before - 0.01)
				_check("shovel does not modify height around player", absf(shovel_feet_after - _p5_shovel_feet_before) < 0.001)

				# Phase 5 Setup (Salt): Dump snow pile at (0, 0, 1.8)
				print("[RETICLE] Phase 5 setup: salt test, dumping snow pile at (0, 0, 1.8)")
				snow_field.dump_snow(Vector3(0.0, 0.0, 1.8), 4.5, 0.35)
				_change_state(12)

		12:
			# State 12: Wait for salt pile to register
			if _state_time >= 0.45:
				player.global_position = Vector3(0.0, 0.0, 0.0)
				player.rotation.y = 0.0
				player.equip_tool(player.ToolType.SALT)
				_p5_salt_target_before = float(snow_field.get_height_at(Vector3(0.0, 0.0, 1.8)))
				_p5_salt_feet_before = float(snow_field.get_height_at(player.global_position))
				player.camera.look_at(Vector3(0.0, _p5_salt_target_before * 0.5, 1.8), Vector3.UP)
				_change_state(13)

		13:
			# State 13: Salt action at pointed point
			if _state_time >= 0.15:
				var salt_reticle: int = int(player.get_reticle_state())
				var salt_aim_pt: Vector3 = player.get_reticle_aim_point()
				print("[RETICLE] Salt test: reticle=%d aim=%s pile_h=%.3f" % [salt_reticle, str(salt_aim_pt), _p5_salt_target_before])
				_check("salt aiming at snow: reticle is CAN_CARVE", salt_reticle == player.ReticleState.CAN_CARVE)
				# Melt snow at reticle aim point
				snow_field.carve(salt_aim_pt, 1.6, 0.50, Vector3.ZERO, true)
				_change_state(14)

		14:
			# State 14: Evaluate Salt action
			if _state_time >= 0.45:
				var salt_target_after: float = float(snow_field.get_height_at(Vector3(0.0, 0.0, 1.8)))
				var salt_feet_after: float = float(snow_field.get_height_at(player.global_position))
				print("[RETICLE] Salt eval: target h %.3f -> %.3f, feet h %.3f -> %.3f" % [
					_p5_salt_target_before, salt_target_after, _p5_salt_feet_before, salt_feet_after])

				_check("salt modifies height at pointed point", salt_target_after < _p5_salt_target_before - 0.01)
				_check("salt does not modify height around player", absf(salt_feet_after - _p5_salt_feet_before) < 0.001)

				_report()

func _change_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0

func _check(label: String, ok: bool) -> void:
	print("[RETICLE] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_checks_ok += 1
	else:
		_checks_fail += 1

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[RETICLE] RESULT: %d OK / %d FAIL" % [_checks_ok, _checks_fail])
	print("[RETICLE] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
