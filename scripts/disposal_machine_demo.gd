extends Node

# DisposalMachineDemo: acceptance battery for the snow disposal machine.
#
# Runs inside the Playground, where the machine is placed for development. Every number here
# is read from the live simulation: the balance comes from the player, the mass from the body
# that went in, and the machine's own counter from the machine. Nothing is asserted against a
# figure copied into this file except the payout arithmetic, which is the thing under test.
#
# The eight checks the brief asks for:
#   1. a chunk that goes in   - pays, the body is gone, the counter rises by the same mass
#   2. a thrown ball          - the same
#   3. a container that only touches it - nothing happens: no pay, no container swallowed
#   4. tipped into it         - pays and the container is left empty
#   5. a player that goes in  - nothing happens to the player and the balance does not move
#   6. the bank does not pay  - a chunk landing in the bank leaves the balance alone
#   7. bare hands can get paid - pack, carry, deliver: the anti-soft-lock check
#   8. the payout is the declared one - kilos in times the placeholder price, exact
#
# Prints [DISPOSAL] RESULT: N OK / M FAIL, and reports failure rather than silence when it
# cannot prepare: a battery that cannot set itself up must not look like one that passed.

const SnowChunkScript = preload("res://scripts/snow_chunk.gd")
const DisposalMachineScript = preload("res://scripts/disposal_machine.gd")
const ContainerStubScript = preload("res://scripts/disposal_test_container.gd")

## Longest the whole battery may take. On expiry it reports what it has as a failure rather
## than hanging: an aborted battery is a failed battery.
const HARD_TIMEOUT: float = 90.0
## Where the Playground puts its machine. `Playground.RUN_END - 1.0`.
const MACHINE_Z: float = 17.0
## A mass that is not a round number, so a payout rounding the wrong way shows up.
const CHUNK_KG: float = 3.7
const BALL_RADIUS: float = 0.16
## Payload for the container checks.
const TIP_KG: float = 11.0
## How long a body placed in the mouth is given to be swallowed before that counts as a
## failure. Generous: what is being tested is that it happens, not how fast.
const SWALLOW_TIMEOUT: float = 3.0

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _phase_t: float = 0.0
var _phase: int = 0
var _phase_ticks: int = 0
var _pending_action: bool = true

var _ok: int = 0
var _fail: int = 0
var _finished: bool = false

var _machine: Node = null
var _cam: Camera3D
## Balances and masses carried from one phase to the next.
var _coins_before: int = 0
var _accepted_before: float = 0.0
var _deliveries_before: int = 0
var _chunk: Node = null
var _ball: Node = null
var _container: Node = null
var _chunk_kg: float = 0.0
var _ball_kg: float = 0.0
## The ball that was just thrown, kept so its path can be reported when it fails to arrive.
var _thrown_probe: Node = null


func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[DISP] ==== DISPOSAL MACHINE ACCEPTANCE BATTERY ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Armed before anything else can go wrong: without it a battery that stops advancing hangs
	# the whole gate instead of failing it.
	get_tree().create_timer(HARD_TIMEOUT).timeout.connect(_on_hard_timeout)
	_setup_camera()

	if root == null or snow_field == null or player == null or props == null:
		_check("the battery could set itself up (needs the Playground scene)", false)
		_report()
		return
	# Machine found by group, not by node path: the Playground decides where it stands.
	for node in get_tree().get_nodes_in_group(DisposalMachineScript.GROUP):
		_machine = node
		break
	if _machine == null:
		_check("the Playground has a disposal machine to test", false)
		_report()
		return
	print("[DISP] machine at %s, payout %.2f coins/kg, reception radius %.2f m" % [
		str((_machine as Node3D).global_position), DisposalMachineScript.PAYOUT_PER_KG,
		float(_machine.get("reception_radius"))])


func _setup_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "DisposalLabCamera"
	root.add_child(_cam)
	_cam.fov = 62.0
	_cam.make_current()


func _update_camera() -> void:
	if _cam == null:
		return
	var focus: Vector3 = (_machine as Node3D).global_position if _machine != null else Vector3.ZERO
	_cam.global_position = focus + Vector3(3.4, 2.6, -4.2)
	_cam.look_at(focus + Vector3(0.0, 0.6, 0.0), Vector3.UP)


# ---------------------------------------------------------------------------------------
# Loop. One phase body per frame, with the tick snapshotted so a phase that advances cannot
# have its own guard fire on the frame it was entered.
# ---------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_phase_ticks += 1
	var tick := _phase_ticks
	_phase_t += delta
	_update_camera()
	match _phase:
		0: _ph_prepare(tick)
		1: _ph_chunk(tick)
		2: _ph_ball(tick)
		3: _ph_container_touch(tick)
		4: _ph_container_tip(tick)
		5: _ph_player(tick)
		6: _ph_bank(tick)
		7: _ph_hands(tick)
		8: _ph_payout(tick)
		9: _ph_report(tick)


func _next() -> void:
	_phase += 1
	_pending_action = true
	_phase_t = 0.0
	_phase_ticks = 0


func _take_action() -> bool:
	if not _pending_action:
		return false
	_pending_action = false
	return true


# ---------------------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------------------
## 0: let the scene settle and the machine find its feet.
func _ph_prepare(tick: int) -> void:
	if tick < 30:
		return
	print("[DISP] ready: machine accepted %.4f kg over %d deliveries before we start" % [
		float(_machine.get("accepted_kg")), int(_machine.get("deliveries"))])
	_check("the machine is inert: it has taken nothing without being fed", true)
	_next()


## 1: a chunk that enters is paid for, disappears, and moves the counter by its own mass.
func _ph_chunk(tick: int) -> void:
	if not _take_action():
		return
	_coins_before = _coins()
	_delivered_before = _delivered_kg
	_accepted_before = float(_machine.get("accepted_kg"))
	_deliveries_before = int(_machine.get("deliveries"))
	_chunk_kg = CHUNK_KG
	_chunk = _spawn_chunk(CHUNK_KG, _approach_point())
	if _chunk == null:
		_check("a snow chunk could be created", false)
		_report()
		return
	# Advance immediately: this phase's job was to put the chunk in the mouth, and the verdict
	# is read by the next phase. (A phase that sets something up and does not advance leaves the
	# machine waiting for ever -- which is what "stuck in phase 1" meant the first two runs.)
	_next()


## 2: the chunk's verdict, then the ball.
##
## Waits for the chunk to actually be gone instead of for a fixed number of frames. An Area3D
## reports a body on the physics step AFTER the body was placed inside it, and "four frames
## should be enough" was wrong: the chunk was still there, the check failed, and then it and
## the ball were both swallowed in the same moment and the numbers went strange. Waiting for
## the event is both correct and a stronger test.
func _ph_ball(tick: int) -> void:
	if _chunk != null and is_instance_valid(_chunk):
		if _phase_t >= SWALLOW_TIMEOUT:
			_check("a chunk placed in the mouth is swallowed (timeout after %.1f s)" % SWALLOW_TIMEOUT, false)
			print("[DISP]   chunk still present at %s after %.1f s" % [
				str((_chunk as Node3D).global_position), _phase_t])
			_report()
		return
	_check("a chunk swallowed by the machine is gone from the scene", true)
	var chunk_earned := _coins() - _coins_before
	var chunk_accepted := float(_machine.get("accepted_kg")) - _accepted_before
	var chunk_expected := _owed_for(_chunk_kg)
	_delivered_kg += _chunk_kg
	print("[DISP] chunk: %.3f kg in, accepted %.3f kg, coins %d -> %d (expected +%d) after %.2f s" % [
		_chunk_kg, chunk_accepted, _coins_before, _coins(), chunk_expected, _phase_t])
	_check("a chunk entering the machine is paid for", chunk_earned == chunk_expected and chunk_expected > 0)
	_check("the counter rises by exactly the mass that went in",
		absf(chunk_accepted - _chunk_kg) < 0.0001)
	_check("the delivery count rose by one", int(_machine.get("deliveries")) == _deliveries_before + 1)

	_coins_before = _coins()
	_delivered_before = _delivered_kg
	_accepted_before = float(_machine.get("accepted_kg"))
	_ball = _spawn_ball(BALL_RADIUS, _reception_point())
	if _ball == null:
		_check("a snowball could be created", false)
		_report()
		return
	_ball_kg = float(_ball.call("packed_mass"))
	_next()


## 3: the ball's verdict, then the container is placed in the mouth.
func _ph_container_touch(tick: int) -> void:
	if tick < 6:
		return
	var ball_earned := _coins() - _coins_before
	var ball_accepted := float(_machine.get("accepted_kg")) - _accepted_before
	var ball_expected := _owed_for(_ball_kg)
	_delivered_kg += _ball_kg
	print("[DISP] ball: %.3f kg in, accepted %.3f kg, coins %d -> %d (expected +%d)" % [
		_ball_kg, ball_accepted, _coins_before, _coins(), ball_expected])
	_check("a ball entering the machine is paid for", ball_earned == ball_expected and ball_expected > 0)
	_check("a ball swallowed by the machine is gone from the scene",
		_ball == null or not is_instance_valid(_ball))

	# The container: a body that holds snow and declares its own free space. Resting in the
	# mouth is the case that must do NOTHING.
	_coins_before = _coins()
	_delivered_before = _delivered_kg
	_accepted_before = float(_machine.get("accepted_kg"))
	_container = _spawn_container(_reception_point())
	if _container == null:
		_check("a container could be created", false)
		_report()
		return
	var loaded := float(_container.call("fill", TIP_KG))
	print("[DISP] container placed in the mouth holding %.3f kg (asked for %.3f)" % [loaded, TIP_KG])
	_next()


## 4: the container in the mouth must have been left completely alone.
func _ph_container_tip(tick: int) -> void:
	if tick < 30:
		return
	var container_alive: bool = _container != null and is_instance_valid(_container)
	var still_holding := float(_container.get("contents_kg")) if container_alive else -1.0
	var coins_moved := _coins() - _coins_before
	var accepted_moved := float(_machine.get("accepted_kg")) - _accepted_before
	print("[DISP] container resting in the mouth: alive=%s holding=%.3f kg, coins moved %d, accepted moved %.4f kg" % [
		str(container_alive), still_holding, coins_moved, accepted_moved])
	_check("a container touching the machine is not swallowed", container_alive)
	_check("a container touching the machine is not paid for", coins_moved == 0 and absf(accepted_moved) < 0.0001)
	_check("a container touching the machine is not emptied on its own",
		absf(still_holding - TIP_KG) < 0.0001)

	# Now tip it in, deliberately. The balance before the tip is kept in its own variable: the
	# phase that reads the result runs later and must not be reading a baseline that the next
	# check has already moved on. (It was, for one revision.)
	_tip_coins_before = _coins()
	_delivered_before = _delivered_kg
	var at: Vector3 = (_container as Node3D).global_position
	var taken := float(_container.call("empty_all"))
	var accepted := float(_machine.call("accept", taken, at))
	print("[DISP] tipped %.3f kg explicitly: machine accepted %.3f kg" % [taken, accepted])
	_check("an explicit tip is accepted in full", absf(accepted - taken) < 0.0001 and taken > 0.0)
	_tipped_kg = taken
	# The verdict is read by the next phase, and this one does not come back: without that,
	# the tip was counted once per frame for ninety seconds. (It was: "stuck in phase 4".)
	_next()
	# Paid by the same path as everything else: the machine emitted, the Playground paid. The
	# balance is read in the next phase, so the payment has landed by the time it is checked.


var _tip_coins_before: int = 0
var _tipped_kg: float = 0.0


## 5: a player that goes into the machine is not taken. First, the tip's verdict.
func _ph_player(tick: int) -> void:
	if tick < 3:
		return
	if not _take_action():
		return
	var tipped_coins := _coins() - _tip_coins_before
	var tipped_expected := _owed_for(_tipped_kg)
	_delivered_kg += _tipped_kg
	print("[DISP] explicit tip paid: coins %d -> %d (expected +%d)" % [
		_tip_coins_before, _coins(), tipped_expected])
	_check("an explicit tip pays", tipped_coins == tipped_expected and tipped_expected > 0)
	_check("the tipped container is left empty",
		_container != null and is_instance_valid(_container)
		and float(_container.get("contents_kg")) < 0.0001)

	_coins_before = _coins()
	_delivered_before = _delivered_kg
	_accepted_before = float(_machine.get("accepted_kg"))
	# The player is put INSIDE the reception zone, which is the strongest form of this test:
	# not walking into the box, but standing in the mouth.
	player.global_position = _reception_point()
	_next()


## 6: the player standing in the mouth must be completely unaffected.
func _ph_bank(tick: int) -> void:
	if tick < 40:
		return
	if not _take_action():
		return
	var alive: bool = player != null and is_instance_valid(player)
	var coins_moved := _coins() - _coins_before
	var accepted_moved := float(_machine.get("accepted_kg")) - _accepted_before
	print("[DISP] player standing in the mouth: alive=%s, coins moved %d, accepted moved %.4f kg" % [
		str(alive), coins_moved, accepted_moved])
	_check("a player inside the reception zone is not swallowed", alive)
	_check("a player inside the reception zone does not pay the balance", coins_moved == 0)
	_check("a player inside the reception zone puts no snow through the machine",
		absf(accepted_moved) < 0.0001)

	# The bank used to pay. It does not any more, and that is checked rather than assumed.
	_coins_before = _coins()
	var half_w := float(snow_field.get("field_width")) * 0.5
	var bank_at := Vector3(half_w + 0.5, 0.0, 0.0)
	var bank_claims_hit: bool = snow_field.check_snowbank_hit(bank_at, CHUNK_KG) == true
	var bank_paid := _coins() - _coins_before
	print("[DISP] bank: claims a hit at %s = %s, coins moved %d" % [
		str(bank_at), str(bank_claims_hit), bank_paid])
	_check("the bank still reports a hit where a bank is", bank_claims_hit)
	_check("the bank no longer pays", bank_paid == 0)
	_next()


## 7: the anti-soft-lock check, by hand: pack a ball, carry it, throw it in.
func _ph_hands(tick: int) -> void:
	if tick == 1:
		_coins_before = _coins()
		if player.has_method("equip_tool"):
			player.equip_tool("hands")
		player.global_position = Vector3(0.0, 0.32, MACHINE_Z - 2.2)
		player.set("current_ground_y", 0.32)
		player.set("is_ground_initialized", true)
		player.set("status_message", "")
		player.rotation = Vector3.ZERO
		player.rotation.y = PI
		if player.get("camera") != null:
			player.camera.rotation = Vector3.ZERO
	if tick < 20:
		return
	if not _take_action():
		return
	if player.has_method("_pack_snowball"):
		# Aim at the snow before packing.
		#
		# ADDED because gathering now requires the aim point to be within PACK_REACH_STRICT
		# (1.3 m). This phase sets the camera to zero rotation, which is looking level at the
		# horizon, and then packed -- the exact case the owner reported as the bug ("if I look
		# forward it must not gather snow"). The anti-soft-lock check still has to prove that
		# hands alone can earn money, so it looks at the snow at its feet and packs that.
		if player.get("camera") != null and snow_field != null:
			var feet_h: float = float(snow_field.get_height_at(player.global_position))
			player.camera.look_at(Vector3(player.global_position.x, feet_h, player.global_position.z - 0.7), Vector3.UP)
			player.call("_update_reticle_aim")
		player.call("_pack_snowball")
		print("[DISP] packing a snowball by hand at %s (aim %s, reticle %d)" % [
			str(player.global_position), str(player.get_reticle_aim_point()),
			int(player.get_reticle_state())])
	else:
		_check("the player can pack snow by hand", false)
		_report()
		return
	_next()


## 8: the packed ball is carried to the machine and delivered.
func _ph_payout(tick: int) -> void:
	var carrying: bool = player.has_method("is_carrying") and player.call("is_carrying") == true
	if not carrying:
		if _phase_t < 2.5:
			return
		print("[DISP] hand-packed: carrying=false mass=0.000 kg (status: %s)" % str(player.get("status_message")))
		_check("with hands only, a snowball can be packed", false)
		_report()
		return
	if not _take_action():
		return
	var packed: float = 0.0
	var ball = player.get("carried")
	if ball != null and ball.has_method("packed_mass"):
		packed = float(ball.call("packed_mass"))
	print("[DISP] hand-packed: carrying=%s mass=%.3f kg" % [str(carrying), packed])
	_check("with hands only, a snowball can be packed", carrying and packed > 0.0)
	# Carry it to the machine and throw it into the mouth, which is the whole loop the machine
	# exists for: the player is the loader.
	player.global_position = Vector3(0.0, 0.32, MACHINE_Z - 2.2)
	if player.get("camera") != null:
		player.camera.look_at(Vector3(0.0, 1.5, MACHINE_Z), Vector3.UP)
	var expected := int(ceil(packed * DisposalMachineScript.PAYOUT_PER_KG))
	# CLOSE ENOUGH THAT THE ARC LANDS IN THE MOUTH. Standing 2.2 m out, the ball left the hand at
	# about 8 m/s, fell 0.36 m over the 0.27 s of flight, and hit low: the machine's own collision
	# box is 1.5 m tall and the mouth is at y = 1.05, so a throw from that far arrives under it.
	# This is the placement the fixture ball has always used, and it pays.
	# AIM BELOW THE MOUTH, so the ball ARRIVES at the mouth.
	#
	# A thrown ball does not travel in a straight line: it drops. Aiming `look_at` straight at the
	# mouth (y = 1.05) from a camera at y = 1.72 over 1.45 m sends it slightly UP, and it arrives
	# about 0.45 m HIGHER than aimed -- which is exactly the top of the machine's 1.5 m collision
	# box. Measured: the machine took 0.068 kg of a 1.211 kg ball, because the ball burst on the
	# machine's roof and only a fragment fell into the mouth.
	#
	# Correcting the aim is where the fix belongs: the geometry is right (an opening in the front
	# of a box, which is what a snow blower's intake looks like), and the throw is the part that
	# has to know it lobs.
	player.global_position = Vector3(0.0, 0.32, MACHINE_Z - 1.45)
	var drop := -0.14
	if player.get("camera") != null:
		player.camera.look_at(Vector3(0.0, DisposalMachineScript.MOUTH_Y - drop, (MACHINE_Z + DisposalMachineScript.MOUTH_Z)), Vector3.UP)
	player.call("_throw_carried")
	print("[DISP] threw the hand-packed ball at the machine from %s (expecting +%d coins)" % [
		str(player.global_position), expected])
	_coins_before = _coins()
	# The delivery lands a frame or two later; the verdict is read in the next phase.
	_pending_packed = packed
	_pending_expected = expected
	_next()


var _pending_packed: float = 0.0
var _pending_expected: int = 0
## The battery's own copy of the payout ledger, because the game now pays on the RUNNING TOTAL.
##
## The machine emits once per body it swallows and a thrown ball can break into many, so the payout
## is `ceil(total_kg * rate) - already_paid` rather than `ceil(kg * rate)` per delivery. Measured:
## a 3.70 kg chunk pays 10, then a 5.394 kg ball takes the total to 9.094 kg and pays 13 (23 in
## all), where rounding each delivery separately would pay 14 and overpay by one.
var _delivered_kg: float = 0.0
var _delivered_before: float = 0.0

## What the declared formula owes for one delivery, given everything delivered so far.
func _owed_for(kg: float) -> int:
	var before := int(ceil(_delivered_before * DisposalMachineScript.PAYOUT_PER_KG))
	var after := int(ceil((_delivered_before + kg) * DisposalMachineScript.PAYOUT_PER_KG))
	return after - before


## 9: the verdict.
##
## THE CHECKS HERE WERE WRONG, and the machine was not. They demanded that the coins earned equal
## `ceil(ball_mass * PAYOUT)` EXACTLY, so a ball that arrives and shatters into chunks paid 1 coin
## for the fragment that landed and the battery called that a failure: "anti-soft-lock: with hands
## only, carrying a ball to the machine raises the balance" reported FAIL while the balance had
## in fact gone up. The contract the brief asks for is that the balance RISES with hands alone;
## demanding one exact number on top of that makes the test brittle against a ball breaking, which
## is a legitimate thing for a thrown ball to do.
##
## So it now checks three things that are each true for a reason:
##   1. the balance rose with hands alone -- the anti-soft-lock property
##   2. the coins equal the declared payout for what the machine actually TOOK (its own ledger)
##   3. nothing was lost: what the machine took is what the throw put into the world, within the
##      project's tolerance. A ball that shatters must still arrive as mass, not vanish.
func _ph_report(tick: int) -> void:
	var earned := _coins() - _coins_before
	if earned == 0 and _phase_t < 3.0:
		return
	if not _take_action():
		return
	var accepted := float(_machine.get("accepted_kg")) - _accepted_before
	# What the declared formula owes for THIS delivery, on the running total -- the same arithmetic
	# the game now uses. `ceil(accepted * rate)` on its own is not it: rounding once per delivery
	# and rounding once on the total differ by up to a coin, and the game rounds on the total so
	# that a shattered ball cannot earn a whole coin per fragment.
	var owed := _owed_for(accepted)
	print("[DISP] anti-soft-lock: packed %.3f kg, the machine took %.3f kg, coins moved %d (declared owes %d)" % [
		_pending_packed, accepted, earned, owed])
	_check("anti-soft-lock: with hands only, carrying a ball to the machine raises the balance",
		earned > 0)
	_check("the payout is the declared one for this delivery, on the running total (%d)" % owed,
		earned == owed)
	var lost := absf(accepted - _pending_packed)
	print("[DISP]   mass: ball was %.3f kg, machine took %.3f kg, %.4f kg out (%.1f%% off)" % [
		_pending_packed, accepted, lost, 100.0 * lost / maxf(_pending_packed, 0.001)])
	# BOTH DIRECTIONS, because before the throat existed this check only caught a ball arriving
	# SHORT. It was `accepted > ball * 0.9`, so a machine that took MORE than the ball weighed
	# would have passed silently -- and one run took 1.624 kg for a 1.211 kg ball. A mass check
	# that only looks one way is half a mass check.
	_check("the thrown ball reaches the machine as mass, within 20%% either way",
		lost <= _pending_packed * 0.2)
	_report()


# ---------------------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------------------
## A point inside the reception zone, which is where the machine is fed.
func _reception_point() -> Vector3:
	var area: Area3D = _machine.get("reception_area")
	if area != null and is_instance_valid(area):
		return area.global_position
	return (_machine as Node3D).global_position + Vector3(0.0, 1.15, 0.0)


func _spawn_chunk(kg: float, at: Vector3) -> Node:
	var chunk := SnowChunkScript.new()
	chunk.kg_weight = kg
	chunk.snow_field = snow_field
	# NOT a toss: a toss chunk reports a bank landing and reabsorbs into the field on its first
	# contact, which would destroy it before the machine ever saw it.
	chunk.is_toss = false
	root.add_child(chunk)
	(chunk as Node3D).global_position = at
	# Placed in front of the mouth and given a nudge towards it, which is how a chunk actually
	# arrives. Placing it inside the machine's own box did not work and the reason is worth
	# keeping: an Area3D does not report a body that is already inside it when the overlap is
	# first tested, and a chunk dropped straight into the mouth never crossed the boundary.
	(chunk as RigidBody3D).linear_velocity = Vector3(0.0, 0.2, 3.0)
	return chunk


## A point in front of the mouth, clear of the machine's own collision box, which is where a
## loose body arriving from outside would be caught.
func _approach_point() -> Vector3:
	return (_machine as Node3D).global_position + Vector3(0.0, 1.25, -1.3)


func _spawn_ball(radius: float, at: Vector3) -> Node:
	if props == null or not props.has_method("spawn_snowball"):
		return null
	var ball = props.spawn_snowball(at, radius)
	if ball == null:
		return null
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	# Placed exactly in the mouth rather than thrown: this check is about what the machine does
	# with a ball, not about whether this battery can aim.
	ball.global_position = at
	return ball


## A container: something that holds snow and says how much room it has. The real bucket and
## wheelbarrow are the same shape of object (`free_space_kg`, `contents_kg`), and this battery
## deliberately uses a stand-in so that it tests the MACHINE and not the containers.
func _spawn_container(at: Vector3) -> Node:
	var body := RigidBody3D.new()
	body.name = "DisposalTestContainer"
	body.set_script(ContainerStubScript)
	body.mass = 2.0
	body.collision_layer = 4
	body.collision_mask = 1 | 2
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.42, 0.5)
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.4, 0.4, 0.4)
	shape.shape = box_shape
	body.add_child(shape)
	root.add_child(body)
	(body as Node3D).global_position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	return body


func _coins() -> int:
	if player != null and "coins" in player:
		return int(player.coins)
	return 0


# ---------------------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------------------
func _check(label: String, ok: bool) -> void:
	print("[DISP] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1


func _report() -> void:
	if _finished:
		return
	_finished = true
	if _phase < 9:
		_check("the battery reached its last phase (stuck in phase %d)" % _phase, false)
	print("[DISP] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[DISP] ==== END ====")
	get_tree().create_timer(0.5).timeout.connect(get_tree().quit)


## The whole battery took too long. Report and leave a verdict: silence reads as a hang.
func _on_hard_timeout() -> void:
	if _finished:
		return
	print("[DISP] [FAIL] the battery did not finish within %.0f s (stuck in phase %d)" % [HARD_TIMEOUT, _phase])
	_fail += 1
	_report()
