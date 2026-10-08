extends RefCounted

## Session-level accounting for snow whose ownership crosses a system boundary.
##
## The GPU heightfield is deliberately not integrated to calculate this ledger: its reduced
## gameplay mirror is quantized, and a field-wide integral is too noisy for tool-sized transfers.
## Callers record the mass reported by a completed snow operation instead.

signal transaction_recorded(entry: Dictionary, balance: Dictionary)

const DISPOSAL_SINK: StringName = &"disposal_machine"
const DELIVERED_ACCOUNT: StringName = &"delivered"

var _accounts: Dictionary = {}
var _issued_kg: float = 0.0
var _delivered_kg: float = 0.0
var _transaction_count: int = 0


## Records a source such as initial level snow or snowfall.
func record_source(destination: StringName, kg: float, source: StringName) -> bool:
	if destination.is_empty() or source.is_empty() or not _is_valid_mass(kg):
		return false
	_add_to_account(destination, kg)
	_issued_kg += kg
	_record("source", source, destination, kg, -1)
	return true


## Moves measured snow between two live accounts without changing the world total.
func transfer(source: StringName, destination: StringName, kg: float, operation_id: int = -1) -> bool:
	if source.is_empty() or destination.is_empty() or source == destination or not _is_valid_mass(kg):
		return false
	if account_kg(source) + 0.000001 < kg:
		return false
	_add_to_account(source, -kg)
	_add_to_account(destination, kg)
	_record("transfer", source, destination, kg, operation_id)
	return true


## Consumes mass at the one permitted sink. Other destruction paths must use `transfer`.
func deliver(source: StringName, kg: float, operation_id: int = -1) -> bool:
	if source.is_empty() or not _is_valid_mass(kg):
		return false
	if account_kg(source) + 0.000001 < kg:
		return false
	_add_to_account(source, -kg)
	_delivered_kg += kg
	_record("delivery", source, DELIVERED_ACCOUNT, kg, operation_id)
	return true


func account_kg(account: StringName) -> float:
	return maxf(float(_accounts.get(account, 0.0)), 0.0)


func delivered_kg() -> float:
	return _delivered_kg


## Conservation residual from recorded sources and destinations. This is a ledger check, not a
## measurement of the GPU field texture.
func balance_error_kg() -> float:
	var live_total := 0.0
	for value in _accounts.values():
		live_total += maxf(float(value), 0.0)
	return _issued_kg - live_total - _delivered_kg


func is_balanced(tolerance_kg: float = 0.0001) -> bool:
	return absf(balance_error_kg()) <= maxf(tolerance_kg, 0.0)


func snapshot() -> Dictionary:
	var accounts_copy: Dictionary = {}
	for key in _accounts.keys():
		accounts_copy[String(key)] = float(_accounts[key])
	return {
		"issued_kg": _issued_kg,
		"delivered_kg": _delivered_kg,
		"live_kg": _issued_kg - _delivered_kg,
		"balance_error_kg": balance_error_kg(),
		"transaction_count": _transaction_count,
		"accounts": accounts_copy,
	}


func _add_to_account(account: StringName, delta_kg: float) -> void:
	var next := float(_accounts.get(account, 0.0)) + delta_kg
	if absf(next) < 0.000001:
		next = 0.0
	_accounts[account] = next


func _record(kind: String, source: StringName, destination: StringName, kg: float,
		operation_id: int) -> void:
	_transaction_count += 1
	var entry := {
		"sequence": _transaction_count,
		"kind": kind,
		"source": String(source),
		"destination": String(destination),
		"kg": kg,
		"operation_id": operation_id,
	}
	# Runtime transfers are frequent. Building a complete account snapshot for every transaction
	# is quadratic over a session as payload owners accumulate; only pay that cost for an observer.
	if transaction_recorded.get_connections().is_empty():
		return
	transaction_recorded.emit(entry, snapshot())


func _is_valid_mass(kg: float) -> bool:
	return is_finite(kg) and kg > 0.0
