extends SceneTree

## Headless unit checks for the small domain modules; this script has no scene or GPU dependency.

const SnowMassLedgerScript = preload("res://scripts/snow_mass_ledger.gd")
const SnowOperationQueueScript = preload("res://scripts/snow_operation_queue.gd")
const PlayerAimRulesScript = preload("res://scripts/player_aim_rules.gd")
const PlayerMovementModelScript = preload("res://scripts/player_movement_model.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_queue_admission_and_fifo()
	_check_mass_ownership_and_delivery()
	_check_shared_aim_predicates()
	_check_movement_model()
	print("RESULT: %d OK / %d FAIL" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check_queue_admission_and_fifo() -> void:
	var queue = SnowOperationQueueScript.new(2)
	var first: Dictionary = queue.submit(Vector4.ZERO, Vector4.ONE, "first", 10)
	var second: Dictionary = queue.submit(Vector4.ONE, Vector4.ZERO, "second", 11)
	var rejected: Dictionary = queue.submit(Vector4.ZERO, Vector4.ZERO, "overflow", 12)
	_check(bool(first["accepted"]) and bool(second["accepted"]), "queue admits requests up to capacity")
	_check(not bool(rejected["accepted"]) and int(rejected["ticket"]) == 0, "full queue explicitly rejects without a ticket")
	_check(queue.pending_count() == 2 and queue.rejected_count == 1, "rejection does not evict or mutate queued requests")
	var batch: Array[Dictionary] = queue.drain(1)
	_check(batch.size() == 1 and int(batch[0]["ticket"]) == int(first["ticket"]), "queue drains accepted requests in FIFO order")
	_check(queue.pending_count() == 1, "drain removes only the dispatched request")


func _check_mass_ownership_and_delivery() -> void:
	var ledger = SnowMassLedgerScript.new()
	_check(ledger.record_source(&"field", 10.0, &"initial_level"), "ledger records initial field mass")
	_check(ledger.transfer(&"field", &"blower_payload", 4.0, 101), "ledger moves measured mass into a payload")
	_check(ledger.transfer(&"blower_payload", &"snow_chunks", 4.0, 102), "payload mass can be split into a physical destination")
	_check(ledger.deliver(&"snow_chunks", 1.0, 103), "only explicit delivery consumes mass")
	_check(not ledger.transfer(&"field", &"blower_payload", 99.0, 104), "overdrawn transfer is rejected")
	_check(ledger.is_balanced(), "ledger closes after transfers, delivery, and rejected overdraw")
	var snapshot: Dictionary = ledger.snapshot()
	_check(is_equal_approx(float(snapshot["issued_kg"]), 10.0), "ledger preserves its source total")
	_check(is_equal_approx(float(snapshot["delivered_kg"]), 1.0), "ledger records delivered mass separately")
	_check(is_equal_approx(ledger.account_kg(&"field"), 6.0), "field account reflects acknowledged transfers")
	_check(is_equal_approx(ledger.account_kg(&"snow_chunks"), 3.0), "undelivered payload remains accounted")


func _check_shared_aim_predicates() -> void:
	var point := Vector3(0.0, 0.0, -0.8)
	_check(not PlayerAimRulesScript.close_snow_target_valid(false, point, 0.8, 1.3, 0.32),
		"no ray hit cannot activate gathering")
	_check(not PlayerAimRulesScript.close_snow_target_valid(true, point, 2.0, 1.3, 0.32),
		"forward-looking distant snow is outside close reach")
	_check(not PlayerAimRulesScript.close_snow_target_valid(true, point, 0.8, 1.3, -1.0),
		"cleared ground or sky cannot activate snow tools")
	_check(PlayerAimRulesScript.close_snow_target_valid(true, point, 0.8, 1.3, 0.32),
		"close aimed snow activates the shared target predicate")
	_check(not PlayerAimRulesScript.pack_target_valid(true, point, 0.8, 1.3, 0.32, 0.2, 0.435),
		"reticle and pack refuse less than the minimum mass")
	_check(PlayerAimRulesScript.pack_target_valid(true, point, 0.8, 1.3, 0.32, 0.5, 0.435),
		"reticle and pack accept sufficient close snow")


func _check_movement_model() -> void:
	var accelerated := PlayerMovementModelScript.accelerate(
		Vector3.ZERO, Vector3.FORWARD, 4.2, 12.0, 1.0 / 60.0)
	_check(is_equal_approx(accelerated.z, -0.84), "movement acceleration preserves the Quake wish-speed step")
	var capped := PlayerMovementModelScript.cap_horizontal_speed(Vector3(20.0, 2.0, 0.0), 10.0)
	_check(is_equal_approx(Vector2(capped.x, capped.z).length(), 10.0) and is_equal_approx(capped.y, 2.0),
		"horizontal movement cap preserves vertical velocity")
	var stopped := PlayerMovementModelScript.apply_ground_friction(Vector3(0.05, 0.0, 0.0), 5.0, 1.0, 1.5, 1.0 / 60.0)
	_check(is_zero_approx(stopped.x) and is_zero_approx(stopped.z), "ground friction clears sub-threshold drift")


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[OK] " + label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)
