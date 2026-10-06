extends RigidBody3D
## A wheelbarrow: a container on wheels, moved by pushing it, that feels the snow it rolls on.
##
## Two things make it different from a bucket. It carries far more, and it is *moved by the
## player* rather than thrown, so it needs the same push model the rolling ball uses: force
## towards a target speed, never a constant shove, and never any influence while it is not
## touching the ground.
##
## The lesson from the ball is baked in here on purpose. A thrown ball was being steered out
## of the air by a held key because the push logic did not check for ground contact, and it
## took three attempts to find. `apply_push` below refuses to do anything when airborne, and
## that refusal is the point of the function rather than a detail of it.

signal contents_changed(contents_kg: float, capacity_kg: float)

@export var capacity_kg: float = 60.0
@export var own_mass_kg: float = 14.0
@export var footprint_radius: float = 0.42
## Speed it is pushed towards, empty, in metres per second. Slower than a walking player on
## purpose: a barrow is something you follow, not something you chase.
@export var push_speed_empty: float = 1.6
## Load at which the target speed halves. Heavier loads make it slower, never impossible.
@export var push_load_reference_kg: float = 45.0
## Cap on the acceleration the push may apply, so a nudge cannot launch it.
@export var push_max_accel: float = 3.5
## How far ahead of the player it can still be pushed. Beyond this the player must walk.
@export var push_reach_max: float = 2.6
## Below this the player is standing on it, and pushing would launch it.
@export var push_reach_min: float = 0.9
## Extra sink per kg of load, in metres. A loaded barrow digs in.
@export var sink_per_kg: float = 0.0008

var contents_kg: float = 0.0
## Vertical load carried, used for the sink and for the HUD.
var is_being_pushed: bool = false


func _ready() -> void:
	add_to_group("snow_containers")
	add_to_group("pushable")
	_sync_mass()


func free_space_kg() -> float:
	return maxf(capacity_kg - contents_kg, 0.0)


func fill_ratio() -> float:
	if capacity_kg <= 0.0:
		return 0.0
	return contents_kg / capacity_kg


func fill(kg: float) -> float:
	var accepted := minf(maxf(kg, 0.0), free_space_kg())
	if accepted <= 0.0:
		return 0.0
	contents_kg += accepted
	_sync_mass()
	contents_changed.emit(contents_kg, capacity_kg)
	return accepted


func take(kg: float) -> float:
	var given := minf(maxf(kg, 0.0), contents_kg)
	if given <= 0.0:
		return 0.0
	contents_kg -= given
	_sync_mass()
	contents_changed.emit(contents_kg, capacity_kg)
	return given


func empty_all() -> float:
	return take(contents_kg)


## Target speed for the current load. Falls with weight, with a floor so it never stalls.
func target_speed() -> float:
	var load_ratio := contents_kg / maxf(push_load_reference_kg, 1.0)
	return maxf(push_speed_empty / (1.0 + load_ratio), push_speed_empty * 0.35)


## How deep it sits in the snow, in metres, for the given snow support height under it.
func sink_depth(support_height: float) -> float:
	return clampf(support_height * 0.5 + contents_kg * sink_per_kg, 0.0, 0.35)


## Pushes it towards `forward`, from `from_position`, this frame.
##
## Returns true when a push was actually applied, so callers and tests can tell the
## difference between "pushed" and "asked to push".
func apply_push(from_position: Vector3, forward: Vector3, delta: float, grounded: bool) -> bool:
	is_being_pushed = false
	# Nothing steers it out of the air, and nothing steers it from on top of it.
	if not grounded:
		return false
	var to_barrow := global_position - from_position
	to_barrow.y = 0.0
	var distance := to_barrow.length()
	if distance > push_reach_max or distance < push_reach_min:
		return false
	var dir := forward
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	# Only push while it is slower than its target along the push. Above that, let it roll.
	var along := linear_velocity.dot(dir)
	var want := target_speed()
	if along >= want:
		is_being_pushed = true
		return false
	var accel := minf(push_max_accel, (want - along) / maxf(delta, 0.0001))
	apply_central_force(dir * accel * mass)
	is_being_pushed = true
	return true


func _sync_mass() -> void:
	mass = maxf(own_mass_kg + contents_kg, 0.1)


# ---------------------------------------------------------------------------------------
# INTEGRATION POINTS, not written yet, and deliberately not guessed at:
#
# 1. Snow resistance. The barrow must be slowed by the surface it rolls on. Those classes
#    already exist in the field, with their own multipliers for a walking player, and the
#    barrow should read the same ones rather than inventing its own scale, or a barrow will
#    feel wrong on the same snow the player walks on correctly.
#
# 2. The wheels. Two of them, so it tips and steers like a barrow. A single collision shape
#    will behave like a sledge, which is a different object and a different feel. Use joints
#    rather than code: the project already assembles with the engine's joints.
#
# 3. Loading and tipping. `fill` and `take` above are the accounting; who may call them and
#    from where (shovel, hands, bucket, bank) is gameplay and belongs with the interaction
#    code, not here.
# ---------------------------------------------------------------------------------------
