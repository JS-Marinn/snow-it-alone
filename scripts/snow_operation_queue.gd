extends RefCounted

## Bounded FIFO for requests sent to the GPU snow simulation.
##
## The GPU dispatch limit is a per-frame throughput budget, not the queue capacity. Requests
## that cannot fit in the queue are rejected before the simulation changes; accepted requests
## remain here until a dispatch slot and a result-readback slot are both available.

const DEFAULT_CAPACITY: int = 256

var _capacity: int = DEFAULT_CAPACITY
var _next_ticket: int = 1
var _pending: Array[Dictionary] = []
var rejected_count: int = 0


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = maxi(capacity, 1)


## Accepts one operation and returns its stable ticket, or ticket 0 when full.
func submit(a: Vector4, b: Vector4, role: String, owner: int, c: Vector4 = Vector4.ZERO) -> Dictionary:
	if _pending.size() >= _capacity:
		rejected_count += 1
		return {"accepted": false, "ticket": 0, "reason": "queue_full"}
	var ticket := _next_ticket
	_next_ticket += 1
	_pending.append({
		"ticket": ticket,
		"a": a,
		"b": b,
		"c": c,
		"role": role,
		"owner": owner,
	})
	return {"accepted": true, "ticket": ticket, "reason": ""}


## Removes at most `limit` oldest requests for one GPU dispatch.
func drain(limit: int) -> Array[Dictionary]:
	var count := mini(maxi(limit, 0), _pending.size())
	var batch: Array[Dictionary] = []
	for _i in range(count):
		batch.append(_pending.pop_front())
	return batch


func pending_count() -> int:
	return _pending.size()


func capacity() -> int:
	return _capacity


func is_empty() -> bool:
	return _pending.is_empty()
