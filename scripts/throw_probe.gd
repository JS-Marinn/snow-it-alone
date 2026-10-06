extends Node

# ThrowProbe: measures ONE thing -- where a thrown ball actually goes, and how fast.
#
#   --throw-probe
#
# WHY. The anti-soft-lock delivery in `--tool-ownership` has been "the ball never reaches the
# machine" for several rounds, and every diagnosis so far has been made from POSITIONS read out of
# a group query. That query returns the FIRST body in the `snowballs` group, and that battery packs
# a ball earlier in its own run, so the trace may have been following the wrong ball the whole time.
# A measurement that cannot say which object it measured is not a measurement.
#
# So this probe takes the ball the player is ACTUALLY holding before the throw, keeps that exact
# reference, and then prints its velocity every frame. Position tells you where it ended up;
# velocity tells you whether it was ever thrown.

const MACHINE_NAME: String = "DisposalMachine"

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D

var _t: float = 0.0
var _phase: int = 0
var _phase_t: float = 0.0
var _ball: Node3D = null
var _frames: int = 0
var _machine: Node3D = null


func setup(scene_root: Node3D, field: Node3D, ply: Node3D, _props: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	print("[THROWPROBE] ==== THROW PROBE ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_machine = root.get_node_or_null(MACHINE_NAME) as Node3D
	if _machine == null:
		print("[THROWPROBE] no %s in this scene; this probe needs one" % MACHINE_NAME)
		_done()
		return
	print("[THROWPROBE] machine at %s" % str(_machine.global_position))


func _physics_process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	match _phase:
		0: _ph_wait()
		1: _ph_pack()
		2: _ph_throw()
		3: _ph_follow()


func _ph_wait() -> void:
	if _phase_t < 0.6:
		return
	if snow_field == null or not snow_field.has_method("is_coarse_ready") or not snow_field.is_coarse_ready():
		return
	# Stand where the anti-soft-lock check stands, so the numbers are comparable with it.
	var mz := _machine.global_position.z
	var dir := -1.0 if mz < 0.0 else 1.0
	player.global_position = Vector3(0.0, 0.32, mz - dir * 2.2)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.set("status_message", "")
	player.set("shovel_current_load", 0.0)
	if player.has_method("equip_tool"):
		player.equip_tool(player.ToolType.HANDS)
	_next()


func _ph_pack() -> void:
	if _phase_t < 0.4:
		return
	# Aim at the snow at the feet and pack, which is the documented way to get a ball by hand.
	var feet := Vector3(player.global_position.x, 0.0, player.global_position.z + 0.7)
	if player.camera != null:
		player.camera.look_at(feet, Vector3.UP)
	player.call("_update_reticle_aim")
	player.call("_pack_snowball")
	_next()


func _ph_throw() -> void:
	if _phase_t < 0.6:
		return
	# KEEP THE EXACT BALL, before the throw nulls `carried`.
	var held = player.get("carried")
	if held == null or not is_instance_valid(held):
		print("[THROWPROBE] the player is not holding a ball; nothing to throw (status: %s)" % str(player.get("status_message")))
		_done()
		return
	_ball = held as Node3D
	var ball_mass := float(held.call("packed_mass")) if held.has_method("packed_mass") else -1.0
	print("[THROWPROBE] holding a %.3f kg ball at %s" % [ball_mass, str(_ball.global_position)])
	print("[THROWPROBE] machine mouth at %s, %.2f m away horizontally" % [
		str(_machine.global_position),
		Vector2(_ball.global_position.x - _machine.global_position.x,
			_ball.global_position.z - _machine.global_position.z).length()])
	if player.camera != null:
		# Aim where the machine's own battery aims: at the mouth, with its measured lift.
		player.camera.look_at(Vector3(_machine.global_position.x, 1.05 + 0.30, _machine.global_position.z), Vector3.UP)
	player.call("_throw_carried")
	_next()


func _ph_follow() -> void:
	if _ball == null or not is_instance_valid(_ball):
		print("[THROWPROBE] frame %d: the ball no longer exists (machine ledger %.4f kg over %d deliveries)" % [
			_frames, float(_machine.get("accepted_kg")), int(_machine.get("deliveries"))])
		_done()
		return
	var v: Vector3 = _ball.get("linear_velocity") if _ball.get("linear_velocity") != null else Vector3.ZERO
	var gap := _ball.global_position.distance_to(Vector3(_machine.global_position.x, 1.05, _machine.global_position.z))
	print("[THROWPROBE] frame %2d: pos %s  vel %.2f m/s (%.2f, %.2f, %.2f)  %.2f m from the mouth  ledger %.4f kg/%d" % [
		_frames, str(_ball.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
		v.length(), v.x, v.y, v.z, gap,
		float(_machine.get("accepted_kg")), int(_machine.get("deliveries"))])
	_frames += 1
	if _frames >= 30:
		_done()


func _next() -> void:
	_phase += 1
	_phase_t = 0.0


func _done() -> void:
	print("[THROWPROBE] ==== PROBE COMPLETE ====")
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
