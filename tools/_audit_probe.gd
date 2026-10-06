extends SceneTree

var _ticks := 0

func _initialize() -> void:
	print("PROBE ---- start ----")
	_t1()
	_t2()
	_t3()
	_t4()
	_t5()
	_t6()
	_t7()
	_coro()
	print("PROBE ---- all cases issued ----")

func _process(_delta: float) -> bool:
	_ticks += 1
	if _ticks >= 20:
		print("PROBE ---- end ----")
		return true
	return false

func _t1() -> void:
	var n := Node.new()
	var ref = n
	n.free()
	print("PROBE freed-node: (ref == null) = ", ref == null, " ; is_instance_valid = ", is_instance_valid(ref))

func _t2() -> void:
	var v = null
	print("PROBE float(null) = ", float(v))

func _t3() -> void:
	var v = null
	print("PROBE int(null) = ", int(v))

func _t4() -> void:
	var d := {"a": 1}
	print("PROBE dict missing key = ", d["b"])

func _t5() -> void:
	var arr: Array = []
	print("PROBE empty array [0] = ", arr[0])

func _t6() -> void:
	var v = null
	print("PROBE format %.1f against null = ", "%.1f" % v)

func _t7() -> void:
	var v = null
	var t: int = v
	print("PROBE typed int = null -> ", t)

func _coro() -> void:
	print("PROBE   inside coroutine, before await")
	await create_timer(0.05).timeout
	print("PROBE   inside coroutine, AFTER await (it did resume)")
