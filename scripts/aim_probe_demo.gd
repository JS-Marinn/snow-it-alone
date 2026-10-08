extends Node

# AimProbeDemo: a measuring instrument, not a battery.
#
# It answers one question with numbers, before and after a code change: for the aim cases the
# owner described, what does the reticle decide, and what does pressing actually do to the field
# and to the player's hands? It asserts nothing; it prints.
#
#   --aim-probe
#
# ONE CASE PER PHASE, deliberately. An earlier version drove the cases from a list with an index
# and skipped half of them, which is a measuring instrument lying about its own measurements.
#
# The bare-ground case is carved AT A DIFFERENT PLACE from the snow case, so that preparing one
# case cannot destroy the other's ground.

const SnowBallScript = preload("res://scripts/snowball.gd")

## Where the player stands for every case.
const PLAYER_POS: Vector3 = Vector3(0.0, 0.32, 6.0)
## Untouched snow, straight down and just in front of the feet.
const SNOW_AHEAD: Vector3 = Vector3(0.0, 0.0, 5.2)
## Where the snow is carved away, for the bare-ground case. Off to the side on purpose.
const BARE_GROUND: Vector3 = Vector3(1.6, 0.0, 6.0)

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _cam: Camera3D

## What was read at the moment of pressing, per case.
var _press_mass: float = 0.0
var _press_balls: int = 0
var _row: Dictionary = {}


func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[AIM] ==== AIM PROBE (measuring, not asserting) ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 65.0
	_cam.make_current()
	if player and player.has_method("equip_tool"):
		player.equip_tool(player.ToolType.HANDS)


func _physics_process(delta: float) -> void:
	_t += delta
	_state_time += delta
	if _cam and player:
		_cam.global_position = player.global_position + Vector3(2.6, 1.9, 2.6)
		_cam.look_at(player.global_position + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	match _state:
		0: _ph_wait()
		1: _ph_case0()
		2: _ph_read0()
		3: _ph_case1()
		4: _ph_read1()
		5: _ph_case2()
		6: _ph_read2()
		7: _ph_carve()
		8: _ph_case3()
		9: _ph_read3()


func _ph_wait() -> void:
	if _state_time < 0.6:
		return
	if snow_field == null or not snow_field.has_method("is_coarse_ready") or not snow_field.is_coarse_ready():
		return
	player.global_position = PLAYER_POS
	player.velocity = Vector3.ZERO
	player.set("status_message", "")
	_change(1)


func _ph_case0() -> void:
	_press("looking down at snow at the feet", SNOW_AHEAD)
	_change(2)


func _ph_read0() -> void:
	if _read_outcome():
		_change(3)


func _ph_case1() -> void:
	_press("looking forward along the ground", Vector3(0.0, 0.32, 18.0))
	_change(4)


func _ph_read1() -> void:
	if _read_outcome():
		_change(5)


func _ph_case2() -> void:
	_press("looking at the sky", Vector3(0.0, 40.0, 6.0))
	_change(6)


func _ph_read2() -> void:
	if _read_outcome():
		_change(7)


func _ph_carve() -> void:
	if _state_time < 0.1:
		return
	if snow_field != null and snow_field.has_method("clear_for_diagnostics"):
		snow_field.clear_for_diagnostics(BARE_GROUND, 1.2)
		print("[AIM] (carved a 1.2 m disc at %s for the bare-ground case)" % str(BARE_GROUND))
	_change(8)


func _ph_case3() -> void:
	# The carve needs a beat to reach the coarse mirror before the aim means anything.
	if _state_time < 1.0:
		return
	if float(snow_field.get_height_at(BARE_GROUND)) > 0.02 and _state_time < 3.0:
		return
	_press("looking down at cleared ground", BARE_GROUND)
	_change(9)


func _ph_read3() -> void:
	if _read_outcome():
		_report()
		_change(10)


## Aims at `target`, records what the reticle decided, and presses.
##
## The baseline is taken only once the field's own mass has stopped moving. Reading it while the
## world is still settling reported a 1.3 kg ball as having taken 158 kg out of the field, which
## is a measurement of the settling and not of the ball.
func _press(label: String, target: Vector3) -> void:
	_row = {"label": label, "reticle": "?", "hit": false, "dist": -1.0, "avail": -1.0}
	if player == null or player.camera == null:
		return
	player.camera.look_at(target, Vector3.UP)
	player._update_reticle_aim()
	var aim: Vector3 = player.get_reticle_aim_point()
	_row["reticle"] = _state_name(int(player.get_reticle_state()))
	_row["hit"] = bool(player.get("reticle_has_hit"))
	if aim != Vector3.INF:
		var off := aim - player.global_position
		_row["dist"] = Vector2(off.x, off.z).length()
		_row["avail"] = float(player._estimate_available_snow_kg(aim))
	# The LOCAL height at the aim point, which is what catches a hole with no ball: the whole
	# field's integral cannot see a hole 22 cm across, but this can.
	_row["aim"] = aim
	_row["h_before"] = _local_height(aim)
	_press_mass = _settled_mass()
	_press_balls = _count_balls()
	# Three readings around the press: what the baseline was worth, what it is worth the instant
	# after the press, and what it settles to. A whole-field integral that moves 158 kg for a
	# 1.3 kg ball is measuring something other than the ball, and this says which reading moved.
	print("[AIM]   baseline=%.2f kg  immediately_after_press=%.2f kg" % [_press_mass, _field_mass()])
	player._pack_snowball()
	print("[AIM]   after_pack_call=%.2f kg" % _field_mass())


## The field's mass once two consecutive readings agree, so the number measured is the world's
## and not the solver's.
func _settled_mass() -> float:
	var a := _field_mass()
	var b := _field_mass()
	var tries := 0
	while absf(a - b) > 0.05 and tries < 40:
		a = b
		b = _field_mass()
		tries += 1
	return b


## Snow height averaged over a small disc, from the field's own query.
func _local_height(at: Vector3) -> float:
	if at == Vector3.INF:
		return -1.0
	var total := 0.0
	var count := 0
	for angle in range(6):
		var offset := Vector2(0.18, 0.0).rotated(TAU * float(angle) / 6.0)
		total += maxf(float(snow_field.get_height_at(at + Vector3(offset.x, 0.0, offset.y))), 0.0)
		count += 1
	total += maxf(float(snow_field.get_height_at(at)), 0.0)
	return total / float(count + 1)


## Waits out the beat the harvest needs, then prints the case. True when done.
##
## The ball's OWN mass is what gets reported, not the change in the whole field's integral. The
## field drifts a few kilograms between readings while its solver relaxes -- measured: 23199.15,
## then 23202.04 for the same untouched world -- so subtracting two whole-field integrals cannot
## see a 1.3 kg ball. The local hole is reported beside it, because a hole with no ball is the
## failure mode this fix had to avoid.
func _read_outcome() -> bool:
	if _state_time < 0.8:
		return false
	var new_balls := _count_balls() - _press_balls
	var carrying: bool = player.has_method("is_carrying") and player.is_carrying()
	var ball_kg := -1.0
	if carrying:
		var ball = player.get("carried")
		if ball != null and ball.has_method("packed_mass"):
			ball_kg = float(ball.call("packed_mass"))
	var aim: Vector3 = _row.get("aim", Vector3.INF)
	var h_after := _local_height(aim)
	var hole := float(_row.get("h_before", -1.0)) - h_after
	print("[AIM] %-38s reticle=%-9s hit=%-5s dist=%5.2f m avail=%6.3f kg | pressed -> carrying=%s new_balls=%d ball=%5.3f kg local_hole=%+.4f m" % [
		_row.get("label", "?"), _row.get("reticle", "?"), str(_row.get("hit", false)),
		float(_row.get("dist", -1.0)), float(_row.get("avail", -1.0)),
		str(carrying), new_balls, ball_kg, hole])
	return true


func _field_mass() -> float:
	if snow_field != null and snow_field.has_method("measure_total_mass"):
		return float(snow_field.measure_total_mass())
	return 0.0


func _state_name(state: int) -> String:
	match state:
		1: return "CAN_PACK"
		2: return "CAN_CARVE"
		_: return "OFF"


func _count_balls() -> int:
	var c := 0
	if props:
		for child in props.get_children():
			if child is SnowBallScript and is_instance_valid(child):
				c += 1
	return c


func _change(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0


func _report() -> void:
	print("[AIM] ==== PROBE COMPLETE ====")
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
