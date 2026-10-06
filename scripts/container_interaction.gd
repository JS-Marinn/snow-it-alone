extends Node
## Container interaction: who fills a bucket or a wheelbarrow, who empties it, and where the
## snow goes when it leaves.
##
## The containers themselves only count (`fill`, `take`, `empty_all` in `scripts/snow_bucket.gd`
## and `scripts/wheelbarrow.gd`). This file is the decision: which of the shovel, the hands,
## the field or the bank is allowed to move snow in or out, and every path here is written so
## that mass is conserved - snow that goes in came out of the field, and snow that goes out
## ends up in the field or in the bank and nowhere else.
##
## Filling from the ground cannot be a synchronous subtraction: the field runs on the GPU and
## reports what it actually removed a few frames later, through `op_volume_ready`. So a fill
## is: ask for a cut, wait for the real figure, put that figure in the container, and give
## back whatever did not fit. The alternative - trusting an estimate - is how a container
## quietly creates snow.

const PACK_HARVEST_RADIUS: float = 0.26
const PACK_HARVEST_DEPTH: float = 0.30
## The cut asked for is larger than the free space on purpose, so one request fills a bucket
## instead of leaving it a few grams short; the surplus is handed straight back to the field.
const HARVEST_HEADROOM: float = 1.02
## Loose snow density (kg/m3), the same figure the field uses to turn volume into mass.
const LOOSE_DENSITY: float = 150.0
## Radius (m) returned snow is spread over when it goes back to the field. Deliberately wide:
## the field's CPU mirror is a coarse average, so a surplus dropped into a single texel is
## both easy to pile up and hard to measure. Spread out, it is neither.
const RETURN_RADIUS: float = 1.0
## How far a loader can reach for snow, in metres. Beyond this you carry it, which is the
## whole reason the bucket exists.
const LOAD_REACH_MAX: float = 1.7
## How far in front of the player a tipped load lands, in metres.
const DUMP_LEAD: float = 1.0
## Diagnostics: every fill and tip, with the masses involved.
const DEBUG: bool = false

var snow_field: Node3D
## Fills and tips waiting for the field's own measurement, newest last.
var _pending: Array[Dictionary] = []
## Counters for the diagnostics.
var fills_done: int = 0
var tips_done: int = 0
var kg_filled: float = 0.0
var kg_tipped: float = 0.0


func setup(field: Node3D) -> void:
	snow_field = field
	if snow_field and snow_field.has_signal("op_volume_ready"):
		if not snow_field.op_volume_ready.is_connected(_on_op_volume_ready):
			snow_field.op_volume_ready.connect(_on_op_volume_ready)


# ---------------------------------------------------------------------------------------
# The one entry point the player's interaction code calls.
# ---------------------------------------------------------------------------------------
## What a tap on a container does, given the player doing the tapping.
##
## Returns true when the tap was spent on the container, so the caller can tell it apart from
## "nothing here" and fall through to packing a ball.
func container_action(player: Node3D, container: Node) -> bool:
	if player == null or container == null:
		return false
	# A tipped barrow has been emptied by gravity; the player is not asking for anything.
	if container.get("is_tipped") == true:
		return false
	# Full container: the tap means "tip it out", onto the bank if there is one there.
	if float(container.call("fill_ratio")) >= 1.0 and float(container.get("contents_kg")) > 0.0:
		tip_out(player, container)
		return true
	# Something to hand over is handed over first: a shovel load, or a bucket in your hands.
	if _pour_from_player(player, container):
		return true
	return request_fill_from_ground(player, container)


## Fills a container from the snow under the player, remembering what was asked for until the
## field reports what it really removed.
func request_fill_from_ground(player: Node3D, container: Node) -> bool:
	if snow_field == null or not snow_field.has_method("request_harvest"):
		return false
	if player == null or not is_instance_valid(player):
		return false
	var free_kg := float(container.call("free_space_kg"))
	if free_kg <= 0.001:
		return false
	# Where the snow comes from: the point the reticle is on when the player is aiming at the
	# ground, otherwise just in front of their feet.
	var at := _aim_ground_point(player)
	# A container that gets its snow from farther away is a vacuum cleaner. Everything the
	# loader cannot reach has to be carried, and that is the point of the bucket.
	var offset := at - player.global_position
	offset.y = 0.0
	if offset.length() > LOAD_REACH_MAX:
		at = player.global_position + offset.normalized() * LOAD_REACH_MAX
		at.y = _support_height(at)
	if snow_field.has_method("get_height_at") and float(snow_field.get_height_at(at)) < 0.045:
		player.set("status_message", tr("STATUS_NO_SNOW_HERE"))
		return true
	var radius := float(container.get("footprint_radius"))
	if radius <= 0.0:
		radius = PACK_HARVEST_RADIUS
	var gross_kg := free_kg * HARVEST_HEADROOM
	var depth := gross_kg / maxf(PI * radius * radius * LOOSE_DENSITY, 0.001)
	depth = clampf(depth, 0.02, 0.30)
	var owner_id := int(container.get_instance_id())
	_pending.append({
		"owner": owner_id,
		"container": container,
		"player": player,
		"at": at,
	})
	snow_field.request_harvest(container.get_instance_id(), at, at + Vector3(0.02, 0.0, 0.02), radius, depth)
	if DEBUG:
		print("[CONT] harvest asked for: container=%d free=%.3f kg depth=%.3f m at %s" % [
			owner_id, free_kg, depth, str(at)])
	return true


func _on_op_volume_ready(role: String, owner: int, kg: float) -> void:
	if role != "harvest":
		return
	for i in range(_pending.size()):
		var entry: Dictionary = _pending[i]
		if int(entry["owner"]) != owner:
			continue
		_pending.remove_at(i)
		_apply_fill(entry, kg)
		return


## The field has reported the real mass it removed. Put it in the container and hand the
## surplus back, so the container holds exactly what the field lost and not a gram more.
func _apply_fill(entry: Dictionary, harvested_kg: float) -> void:
	var container = entry["container"]
	if container == null or not is_instance_valid(container):
		# The container died between the request and the answer. Its snow is not lost: it
		# goes back where it came from.
		if harvested_kg > 0.0:
			_return_to_field(entry["at"], harvested_kg)
		return
	var kg: float = maxf(harvested_kg, 0.0)
	var accepted := 0.0
	if kg > 0.0:
		accepted = float(container.call("fill", kg))
	var surplus: float = kg - accepted
	if surplus > 0.0:
		_return_to_field(entry["at"], surplus)
	kg_filled += accepted
	if accepted > 0.0:
		fills_done += 1
		if container.has_method("play_fill_sound"):
			container.call("play_fill_sound")
		var player = entry.get("player")
		if player != null and is_instance_valid(player):
			player.set("status_message", tr("STATUS_CONTAINER_LOADED") % accepted)
	if DEBUG:
		print("[CONT] fill: harvested=%.4f accepted=%.4f returned=%.4f" % [kg, accepted, surplus])


func _return_to_field(at: Vector3, kg: float) -> void:
	if kg <= 0.0 or snow_field == null or not snow_field.has_method("dump_snow"):
		return
	snow_field.dump_snow(at, kg, RETURN_RADIUS)


# ---------------------------------------------------------------------------------------
# Emptying. Into the bank if the container was carried there, into the field otherwise.
# ---------------------------------------------------------------------------------------
## Empties a container and accounts for every kilogram of it.
##
## Returns the mass that left the container, so a caller can assert on it.
func tip_out(player: Node3D, container: Node) -> float:
	var kg := float(container.call("empty_all"))
	if kg <= 0.0:
		return 0.0
	kg_tipped += kg
	tips_done += 1
	if container.has_method("play_tip_sound"):
		container.call("play_tip_sound")
	var at := _dump_point(player, container)
	var machine := _find_nearby_disposal_machine(at)
	if machine != null and machine.has_method("accept"):
		var accepted: float = float(machine.accept(kg, at))
		if player != null and is_instance_valid(player):
			player.set("status_message", tr("STATUS_BANK_PAID") % accepted)
		if DEBUG:
			print("[CONT] tip_out: %.4f kg into disposal machine %s" % [accepted, machine.name])
		return accepted
	var in_bank := _deposits_in_bank(at, kg)
	if DEBUG:
		print("[CONT] tip_out: %.4f kg, drop point %s, bank hit %s" % [kg, str(at), str(in_bank)])
	if in_bank:
		if player != null and is_instance_valid(player):
			player.set("status_message", tr("STATUS_CONTAINER_TIPPED") % kg)
		return kg
	_return_to_field(at, kg)
	if player != null and is_instance_valid(player):
		player.set("status_message", tr("STATUS_CONTAINER_TIPPED") % kg)
	if DEBUG:
		print("[CONT] tipped %.4f kg onto the field at %s" % [kg, str(at)])
	return kg


func _find_nearby_disposal_machine(at: Vector3) -> Node:
	for node in get_tree().get_nodes_in_group("disposal_machines"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var mach := node as Node3D
		var radius: float = float(mach.get("reception_radius")) if "reception_radius" in mach else 1.5
		var height: float = float(mach.get("reception_height")) if "reception_height" in mach else 1.15
		var mouth := mach.global_position + Vector3(0.0, height, 0.0)
		if at.distance_to(mouth) <= radius + 0.8 or at.distance_to(mach.global_position) <= radius + 1.2:
			return mach
	return null


## True when dumping `kg` at `at` lands in a snow bank, and pays for it.
##
## The bank pays through the same `check_snowbank_hit` a thrown ball uses, which emits
## `snow_tossed_in_bank` and is picked up by whoever holds the purse (the player controller
## in the level, the HUD when there is no player). So a container is not a second currency:
## it is the same snow, delivered the slow way. A bank that only paid for one of the two was
## the soft-lock this project already fixed once, and this is the check that keeps it fixed.
func _deposits_in_bank(at: Vector3, kg: float) -> bool:
	if snow_field == null or not snow_field.has_method("check_snowbank_hit"):
		return false
	return snow_field.check_snowbank_hit(at, kg) == true


# ---------------------------------------------------------------------------------------
# Handing over what the player is already holding: a loaded shovel, or a full bucket.
# ---------------------------------------------------------------------------------------
func _pour_from_player(player: Node3D, container: Node) -> bool:
	if player.has_method("is_carrying") and player.call("is_carrying") == true:
		return _pour_carried(player, container)
	if float(player.get("shovel_current_load")) <= 0.05:
		return false
	var load := float(player.get("shovel_current_load"))
	var accepted := float(container.call("fill", load))
	if accepted <= 0.0:
		return false
	player.set("shovel_current_load", maxf(load - accepted, 0.0))
	kg_filled += accepted
	fills_done += 1
	if container.has_method("play_fill_sound"):
		container.call("play_fill_sound")
	player.set("status_message", tr("STATUS_CONTAINER_LOADED") % accepted)
	return true


## A carried bucket poured into another container: the bucket is emptied, the other one is
## filled, and the difference goes back to the field, so no kilogram is lost on the way.
func _pour_carried(player: Node3D, container: Node) -> bool:
	var carried = player.get("carried")
	if carried == null or not is_instance_valid(carried) or carried == container:
		return false
	if not carried.has_method("empty_all") or not carried.has_method("fill"):
		return false
	var held := float(carried.get("contents_kg"))
	if held <= 0.0:
		return false
	var given := float(carried.call("take", held))
	if given <= 0.0:
		return false
	var accepted := float(container.call("fill", given))
	var surplus: float = given - accepted
	if surplus > 0.0:
		# Handed it all over and it did not fit: the rest goes back to the ground rather than
		# vanishing, which is what keeps the ledger true when a bucket is poured into a barrow
		# that is nearly full.
		_return_to_field(_dump_point(player, container), surplus)
	kg_filled += accepted
	if accepted > 0.0:
		fills_done += 1
		if container.has_method("play_fill_sound"):
			container.call("play_fill_sound")
	player.set("status_message", tr("STATUS_CONTAINER_LOADED") % accepted)
	return true


# ---------------------------------------------------------------------------------------
# Geometry helpers. Deliberately the same queries the player's own code uses: the support
# height, not the raw height, so a container is loaded from the snow you can see.
# ---------------------------------------------------------------------------------------
func _support_height(pos: Vector3) -> float:
	if snow_field == null:
		return 0.0
	if snow_field.has_method("get_support_snow_height"):
		return maxf(float(snow_field.get_support_snow_height(pos, 0.35)), 0.0)
	if snow_field.has_method("get_height_at"):
		return maxf(float(snow_field.get_height_at(pos)), 0.0)
	return 0.0


## Where the loader takes snow from: the aimed point if the player is aiming at the ground,
## otherwise the snow under their feet.
func _aim_ground_point(player: Node3D) -> Vector3:
	var aim = player.get("reticle_aim_pt")
	if aim != null and aim is Vector3 and aim != Vector3.INF:
		return aim
	return player.global_position


## Where a container is emptied: just in front of whoever tipped it, so walking to the bank
## and tipping over it puts the snow in the bank.
func _dump_point(player: Node3D, container: Node) -> Vector3:
	var origin: Vector3 = player.global_position if player != null and is_instance_valid(player) else container.global_position
	var forward := Vector3.FORWARD
	if player != null and is_instance_valid(player) and player.has_method("_forward_flat"):
		forward = player.call("_forward_flat")
	elif player != null and is_instance_valid(player):
		forward = -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
	var at := origin + forward * DUMP_LEAD
	at.y = _support_height(at)
	return at
