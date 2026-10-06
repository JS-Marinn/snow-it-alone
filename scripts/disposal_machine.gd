extends StaticBody3D
## A snow disposal machine: the first place in this game where snow actually LEAVES the world.
##
## Everything else moves snow around. The shovel lifts it and lays it back down, the blower
## throws it, the salt flattens it, a ball rolls and packs it. Nothing destroys it, so the
## field can only ever be rearranged. This machine is the sink: snow that goes in is gone, and
## the player is paid for it.
##
## The real reference, for whoever reads this next: a two-stage snow blower fed on site, which
## throws its snow up a chute into a tipper truck. In the real job a loader brings it the snow.
## In this game the player IS the loader, which is why the machine never moves.
##
## There is no model yet and that is deliberate. A BoxMesh with a collision shape in a flat
## colour, plainly provisional, is enough to test the mechanic. What it does have is the part
## that sells it without art: a visible chute where the snow comes out, a motor and an impact
## sound, and a counter that says how much has gone through.
##
## THE RULES, and they are rules rather than tuning:
##   - INERT. It never moves, never looks for snow, never aims. It is a hole in the world.
##   - INSTANT. No queue, no timers, no internal state. A body that arrives is paid for and
##     freed in the same call. There is nothing to get stuck in because there is nothing to
##     wait for.
##   - ANY SNOW. Chunks and balls, of any size.
##   - CONTAINERS ARE EMPTIED INTO IT, never swallowed: see the two entries below.
##   - IT NEVER TAKES A PLAYER, and that is filtered EXPLICITLY rather than left to collision
##     layers, because one day somebody will change the layers.

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

## Emitted once per delivery, with the mass that left the world and where it happened.
##
## This is the ONLY money path out of this machine. It is deliberately the same shape as the
## snow bank's `snow_tossed_in_bank`: whoever holds the purse (the player controller in the
## level, the HUD when there is no player) decides what coins are worth. There is no second
## currency here and this file knows nothing about coins.
signal snow_received(kg: float, world_pos: Vector3)

## Placeholder price per kilogram. Higher than the bank's 1.5 on purpose: the bank paid for
## throwing snow a long way, this pays for carrying it all the way to the end, which costs
## more. Written down in docs/economy_placeholder.md.
const PAYOUT_PER_KG: float = 2.5
## Name of the group every machine joins, for tests and for anything that wants to find one.
const GROUP: String = "disposal_machines"

@export var machine_name: String = "Snow Disposal Machine"
## Radius (m) of the reception zone in front of the mouth. Wide enough for a thrown ball.
@export var reception_radius: float = 1.1
## How high above the machine's origin the reception zone sits (m).
@export var reception_height: float = 1.15

## Total mass this machine has taken out of the world, in kg. The number the HUD shows.
var accepted_kg: float = 0.0
## Deliveries, for the diagnostics.
var deliveries: int = 0
## The reception zone, so a test can find it.
var reception_area: Area3D = null
## Bodies already handled this frame, so one body cannot be counted twice if it is caught by
## both the area and a second overlap report before it is freed.
var _handled: Array[int] = []


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group("interact_targets")
	_build_reception()


## The receiving mouth: an Area3D in front of the machine, not the machine's own collision box.
##
## The separation is the design. A ball that flies in is caught by this zone; a bucket or a
## wheelbarrow is NOT something this zone picks up, it is something the player empties in. That
## is what makes "containers must be emptied into it" true by construction rather than by a
## check: the zone cannot swallow a container because it does not collect containers at all.
func _build_reception() -> void:
	reception_area = Area3D.new()
	reception_area.name = "Reception"
	reception_area.position = Vector3(0.0, reception_height, 0.0)
	# Layer 4 is where loose snow, balls and containers live; layer 8 is props. Layer 1, where
	# the player's own body is, is NOT in this mask.
	#
	# And the mask is not the filter. The filter is `_on_body_entered` below, which refuses a
	# player by name. Layers get edited by people in a hurry; a refusal written in the code
	# does not.
	reception_area.collision_layer = 0
	reception_area.collision_mask = 1 | 4 | 8
	reception_area.monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = reception_radius
	shape.shape = sphere
	reception_area.add_child(shape)
	add_child(reception_area)
	reception_area.body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	# The list of bodies already handled exists so a body caught twice in the same frame is not
	# paid for twice. It is cleared here rather than accumulated: this is bookkeeping for one
	# frame, not state about the world.
	_handled.clear()


# ---------------------------------------------------------------------------------------
# Entry one: the reception zone. Anything loose that flies in.
# ---------------------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if _is_player(body):
		return
	var kg := _snow_kg_of(body)
	if kg <= 0.0:
		return
	_swallow(body, kg)


## True for anything that is a player. Written out as its own refusal so that the rule is
## visible here, in this file, and not only in a collision mask three files away.
func _is_player(body: Node) -> bool:
	# The player is a CharacterBody3D. Nothing else in this project is.
	if body is CharacterBody3D:
		return true
	# And it carries the impact group, which is how the ball code already recognises a person.
	return body.is_in_group("impact_targets") and body.has_method("is_carrying")


## The kilograms a body is carrying, read from what the body ALREADY knows. Nothing here
## recomputes mass from a volume or a radius: `kg_weight` is what a chunk was made with and
## `packed_mass()` is what a ball actually weighs.
##
## Returns 0 for anything that is not snow, which includes every container: a bucket or a
## wheelbarrow reports its own empty mass through `mass`, and swallowing that would delete the
## container and pay for its steel.
func _snow_kg_of(body: Node) -> float:
	if _is_container(body):
		return 0.0
	if "kg_weight" in body:
		return maxf(float(body.get("kg_weight")), 0.0)
	if body.has_method("packed_mass"):
		return maxf(float(body.call("packed_mass")), 0.0)
	return 0.0


## A container: it counts what it holds with `free_space_kg`, and it is emptied by hand.
func _is_container(body: Node) -> bool:
	return body.has_method("free_space_kg")


## Pays for a body and takes it out of the world.
func _swallow(body: Node, kg: float) -> void:
	var id := int(body.get_instance_id())
	if _handled.has(id):
		return
	_handled.append(id)
	var at: Vector3 = (body as Node3D).global_position if body is Node3D else global_position
	body.queue_free()
	_credit(kg, at)


# ---------------------------------------------------------------------------------------
# Entry two: an explicit tip. Buckets and wheelbarrows are emptied in, by the player.
# ---------------------------------------------------------------------------------------
## Takes `kg` of snow from a container that was tipped into this machine.
##
## Called by the container interaction code when a load is tipped with the machine in front of
## it. Returns the mass accepted, which is all of it: this machine never refuses snow and has
## no capacity, so a caller can rely on a full tip being a full delivery.
func accept(kg: float, world_pos: Vector3) -> float:
	var taken := maxf(kg, 0.0)
	if taken <= 0.0:
		return 0.0
	_credit(taken, world_pos)
	return taken


## The one place a delivery becomes money and a number. Both entries end here.
func _credit(kg: float, world_pos: Vector3) -> void:
	accepted_kg += kg
	deliveries += 1
	_play_engine()
	_play_impact()
	snow_received.emit(kg, world_pos)


## True when `world_pos` is inside this machine's mouth, which is what the container
## interaction asks before it calls `accept`.
func is_mouth_at(world_pos: Vector3) -> bool:
	if reception_area == null:
		return false
	return reception_area.global_position.distance_to(world_pos) <= reception_radius * 1.6


# ---------------------------------------------------------------------------------------
# Sound: the machine exists without a model because it can be heard. A motor under the load,
# and the thump of snow landing in a box.
# ---------------------------------------------------------------------------------------
func _play_engine() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = SoundEffectsScript.get_sound("snowblower")
	player.volume_db = -8.0
	player.unit_size = 14.0
	player.pitch_scale = randf_range(0.94, 1.06)
	add_child(player)
	player.play()
	# A short burst, not a loop: it is a machine swallowing, not a machine running.
	var stop := get_tree().create_timer(0.9)
	stop.timeout.connect(func() -> void:
		if is_instance_valid(player):
			player.stop()
			player.queue_free())


func _play_impact() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = SoundEffectsScript.get_snow_thud()
	player.volume_db = -3.0
	player.unit_size = 16.0
	player.pitch_scale = randf_range(0.80, 0.95)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ---------------------------------------------------------------------------------------
# Interaction: the player can walk up to it and use it, which for a machine with one button
## means the same [E] tap a container uses.
# ---------------------------------------------------------------------------------------
## What a tap on the machine does. Returns true when the tap was spent here.
##
## Right now a tap has nothing to do: snow has to be thrown in or tipped in. It answers true
## so the tap is not mistaken for "pack a snowball", and it says so on screen, because a
## machine that silently ignores the player reads as broken.
func interact(player: Node3D, _aim: Vector3) -> bool:
	if player == null:
		return false
	player.set("status_message", tr("STATUS_DISPOSAL_HOWTO"))
	return true
