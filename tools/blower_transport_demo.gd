extends Node

## GPU integration battery for the blower's mass route. Runs in the real level so the test
## exercises the player's blower intake, SnowField harvest result, spawned chunks, and deposit.

const INPUT_ACTION: StringName = &"shovel_push"
const OPERATION_TIMEOUT: float = 12.0
const RETURN_TIMEOUT: float = 18.0

var _root: Node3D
var _field: Node3D
var _player: Node3D
var _owner_id: int = -1
var _target: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _phase: int = 0
var _phase_frames: int = 0
var _removed_kg: float = 0.0
var _payload_kg: float = 0.0
var _returned_kg: float = 0.0
var _payload_count: int = 0
var _baseline_ids: Dictionary = {}
var _checks_ok: int = 0
var _checks_fail: int = 0
var _finished: bool = false


func setup(scene_root: Node3D, snow_field: Node3D, player: Node3D, _props: Node3D) -> void:
	_root = scene_root
	_field = snow_field
	_player = player
	print("[BLOWER] ==== TRANSPORT MASS BATTERY ====")
	Input.action_release(INPUT_ACTION)
	get_tree().create_timer(40.0).timeout.connect(_on_timeout)
	if _root == null or _field == null or _player == null:
		_check("the level supplies a field and player", false)
		_report()
		return
	if not _field.has_signal("operation_completed"):
		_check("the field exposes operation receipts", false)
		_report()
		return
	_field.operation_completed.connect(_on_operation_completed)
	_owner_id = int(_player.get("_player_owner"))
	# Keep the normal player loop on hands; this battery invokes the real blower behavior with a
	# controlled aim sample so the result is deterministic and independent of mouse hardware.
	_player.set("current_tool", 3)
	for node in get_tree().get_nodes_in_group("snow_chunks"):
		_baseline_ids[int(node.get_instance_id())] = true


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_phase_frames += 1
	if _phase == 0:
		if not _field.has_method("is_coarse_ready") or not _field.is_coarse_ready():
			if _elapsed > OPERATION_TIMEOUT:
				_check("the snow field becomes ready before the budget expires", false)
				_report()
			return
		_target = _player.global_position - Vector3(0.0, 0.0, 0.75)
		_target.y = float(_player.call("get_snow_surface_y", _target))
		var h: float = float(_field.call("get_height_at", _target))
		if h <= 0.015:
			_check("the blower fixture starts over real snow", false)
			_report()
			return
		_check("the blower fixture starts over real snow", true)
		Input.action_press(INPUT_ACTION)
		_phase = 1
		_phase_frames = 0
		return

	_set_close_aim()
	if _phase == 1:
		if _removed_kg <= 0.0:
			_player.call("_process_blower", delta)
		if _removed_kg > 0.0 and _phase_frames >= 2:
			_capture_payloads()
			_check("a close aimed intake reports removed mass", _removed_kg > 0.0)
			_check("every removed kilogram is carried by visible payloads",
				_payload_count > 0 and absf(_payload_kg - _removed_kg) <= maxf(0.005, _removed_kg * 0.01))
			Input.action_release(INPUT_ACTION)
			_phase = 2
			_phase_frames = 0
		elif _elapsed > OPERATION_TIMEOUT:
			Input.action_release(INPUT_ACTION)
			_check("a close aimed intake completes before timeout", false)
			_report()
		return

	if _phase == 2:
		_capture_payloads()
		if _returned_kg >= _payload_kg - 0.0001:
			_check("landed blower payloads are admitted back into the field", _payload_count > 0)
			_check("returned mass matches the removed payload mass",
				absf(_returned_kg - _payload_kg) <= maxf(0.005, _payload_kg * 0.01))
			var player_payload_left := float(_field.call("payload_mass_kg", _owner_id))
			_check("runtime ledger closes blower removal, chunk ownership, and field return",
				bool(_field.call("mass_ledger_is_balanced", 0.001)) and player_payload_left <= 0.001)
			_report()
		elif _elapsed > RETURN_TIMEOUT:
			_check("blower payloads return to the field before timeout", false)
			_report()


func _set_close_aim() -> void:
	_player.set("reticle_has_hit", true)
	_player.set("reticle_aim_pt", _target)
	var offset: Vector3 = _target - _player.global_position
	_player.set("reticle_aim_distance", Vector2(offset.x, offset.z).length())


func _on_operation_completed(ticket: int, role: String, owner: int, actual_kg: float) -> void:
	if role != "blower_intake" or owner != _owner_id:
		return
	print("[BLOWER] operation %d removed %.6f kg" % [ticket, actual_kg])
	_removed_kg += actual_kg


func _capture_payloads() -> void:
	var total := 0.0
	var count := 0
	for node in get_tree().get_nodes_in_group("snow_chunks"):
		var id := int(node.get_instance_id())
		if _baseline_ids.has(id):
			continue
		count += 1
		total += maxf(float(node.get("kg_weight")), 0.0)
		if node.has_signal("reabsorbed") and not node.reabsorbed.is_connected(_on_payload_reabsorbed):
			node.reabsorbed.connect(_on_payload_reabsorbed)
	_payload_count = maxi(_payload_count, count)
	_payload_kg = maxf(_payload_kg, total)


func _on_payload_reabsorbed(kg: float, _world_pos: Vector3) -> void:
	_returned_kg += kg
	print("[BLOWER] payload rejoined field: %.6f kg (%.6f kg total)" % [kg, _returned_kg])


func _on_timeout() -> void:
	if _finished:
		return
	Input.action_release(INPUT_ACTION)
	_check("the blower battery completed before the hard timeout", false)
	_report()


func _check(label: String, ok: bool) -> void:
	if ok:
		_checks_ok += 1
		print("[BLOWER] [OK] " + label)
	else:
		_checks_fail += 1
		push_error("[BLOWER] [FAIL] " + label)


func _report() -> void:
	if _finished:
		return
	_finished = true
	Input.action_release(INPUT_ACTION)
	print("[BLOWER] RESULT: %d OK / %d FAIL" % [_checks_ok, _checks_fail])
	print("[BLOWER] ==== END ====")
	get_tree().create_timer(0.25).timeout.connect(get_tree().quit)
