extends RigidBody3D
## A bucket: a rigid body that holds a measured amount of snow.
##
## It is the small end of the same idea as the wheelbarrow: snow that is not in the field and
## not in a ball, but in a container, with the mass accounted for. The accounting and the
## limits are `fill`, `take` and `empty_all`; the part that makes it sit in the snow is the
## support block below, copied from the snowball so the two behave alike.
##
## Mass is always own_mass + contents_kg, so a full bucket is heavier than an empty one and
## the physics engine does the rest. Nothing here creates or destroys snow: `fill` refuses
## what does not fit and `take` never returns more than it holds, which is what keeps the
## project's mass invariant true. Who may fill it, and from where, is gameplay and lives in
## `scripts/container_interaction.gd`.

signal contents_changed(contents_kg: float, capacity_kg: float)

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

# ---------------------------------------------------------------------------------------
# Snow support. COPIED from `scripts/snowball.gd`, deliberately, block for block and value
# for value: the same spring against the field's height query at the body's position, the
# same Coulomb friction on the real slip at the contact point, and the same damping.
#
# It is a copy rather than a shared helper because the two bodies are otherwise unrelated.
# What must not drift is the numbers: a bucket and a ball of the same mass standing in the
# same snow have to sit at the same depth, and a player who has pushed both will notice at
# once if they do not. `--container-lab` compares them and fails if they diverge.
# ---------------------------------------------------------------------------------------
## Stiffness and damping of the snow support (per unit of mass).
const SUPPORT_STIFFNESS: float = 400.0
const SUPPORT_DAMPING: float = 40.0
## Contact friction with snow.
const CONTACT_FRICTION: float = 0.85
## Offset (m) used to read the terrain normal from the height field.
const NORMAL_SAMPLE_OFFSET: float = 0.16
## How hard the support springs push the harness point in the hand back to the body.
const CARRY_LEASH_ACCEL: float = 26.0

@export var capacity_kg: float = 12.0
## Mass of the bucket itself, without snow. A full bucket should feel heavier than the snow
## in it alone, or carrying an empty one costs nothing.
@export var own_mass_kg: float = 1.8
## Radius used for the snow support query, in metres. Roughly the footprint.
@export var footprint_radius: float = 0.22
## How far behind the player it can be dragged before it is pulled back.
@export var push_reach_max: float = 1.7
## Closer than this the leash goes slack, so the bucket can be dropped at your feet.
@export var push_reach_min: float = 0.55

## Snow field to read the surface from. Assigned by whoever creates the bucket.
var snow_field: Node3D
var contents_kg: float = 0.0

## True while a player is holding it, so the carrying code and the throw can find it.
var is_carried: bool = false
## Point in the hand the leash pulls the body towards, in world space. INF when not dragged.
var _carry_target: Vector3 = Vector3.INF
## Grounded this physics step, set by the support block.
var _grounded: bool = false


func _ready() -> void:
	add_to_group("snow_containers")
	add_to_group("interact_targets")
	continuous_cd = true
	# The support is applied as a force, so the body must never fall asleep: a sleeping
	# rigid body stops receiving `_integrate_forces` and would drop through the snow.
	can_sleep = false
	angular_damp = 0.05
	linear_damp = 0.02
	var phys := PhysicsMaterial.new()
	phys.friction = CONTACT_FRICTION
	phys.bounce = 0.02
	physics_material_override = phys
	# Collides with ground, structures and other loose snow, but NOT with the snow field:
	# support comes from the elastic response to the deformable height map. The bucket is on
	# the same layer the balls and props use, which is the layer the player's interaction ray
	# looks at.
	collision_layer = 4
	collision_mask = 1 | 4
	_sync_mass()


## A bucket is meant to be picked up. The carrying code asks before it grabs anything.
func can_be_carried() -> bool:
	return true


## Room left, in kg.
func free_space_kg() -> float:
	return maxf(capacity_kg - contents_kg, 0.0)


## How full it is, 0 to 1. For the HUD and for tests.
func fill_ratio() -> float:
	if capacity_kg <= 0.0:
		return 0.0
	return contents_kg / capacity_kg


## Puts snow in. Returns how much actually went in, which is never more than there was room
## for. The caller is responsible for having taken that snow out of the field first: this
## function does not know where snow comes from, and pretending it did would create mass.
func fill(kg: float) -> float:
	var accepted := minf(maxf(kg, 0.0), free_space_kg())
	if accepted <= 0.0:
		return 0.0
	contents_kg += accepted
	_sync_mass()
	contents_changed.emit(contents_kg, capacity_kg)
	return accepted


## Takes snow out, up to what is held. Returns how much came out.
func take(kg: float) -> float:
	var given := minf(maxf(kg, 0.0), contents_kg)
	if given <= 0.0:
		return 0.0
	contents_kg -= given
	_sync_mass()
	contents_changed.emit(contents_kg, capacity_kg)
	return given


## Empties it completely and reports the amount, so the caller can put that snow somewhere
## that accounts for it: a bank, a wheelbarrow, or back into the field.
func empty_all() -> float:
	return take(contents_kg)


func _sync_mass() -> void:
	mass = maxf(own_mass_kg + contents_kg, 0.1)


# ---------------------------------------------------------------------------------------
# Snow support: the block copied from `scripts/snowball.gd` (see the constants above).
# ---------------------------------------------------------------------------------------

## Snow height (m) under the bucket's footprint, or the flat depth when the point is
## outside the simulated field, where `get_height_at` reports -1.
func support_height_at(pos: Vector3) -> float:
	if snow_field and snow_field.has_method("get_height_at"):
		var h: float = snow_field.get_height_at(pos)
		if h >= 0.0:
			return h
	return 0.0


## True while the bucket is held up by snow or by the ground plane. The interaction code and
## the diagnostics read this instead of guessing from the position.
func is_grounded() -> bool:
	return _grounded


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if is_carried or snow_field == null:
		return

	var pos := state.transform.origin
	var height := -1.0
	if snow_field.has_method("get_height_at"):
		height = snow_field.get_height_at(pos)

	# Elastic support on the snow surface (terrain normal)
	_grounded = false
	if height >= 0.0:
		var e := NORMAL_SAMPLE_OFFSET
		var hx := height
		var hz := height
		if snow_field.has_method("get_height_at"):
			hx = snow_field.get_height_at(pos + Vector3(e, 0.0, 0.0))
			hz = snow_field.get_height_at(pos + Vector3(0.0, 0.0, e))
			if hx < 0.0:
				hx = height
			if hz < 0.0:
				hz = height
		var normal := Vector3(-(hx - height) / e, 1.0, -(hz - height) / e).normalized()
		var penetration := (height + footprint_radius) - pos.y
		if penetration > 0.0:
			_grounded = true
			var vn := state.linear_velocity.dot(normal)
			var normal_force: float = maxf(SUPPORT_STIFFNESS * mass * penetration - SUPPORT_DAMPING * mass * vn, 0.0)
			state.apply_central_force(normal * normal_force)

			# Coulomb friction on the REAL SLIP at the contact point (not on the
			# centre velocity): the torque it produces turns sliding into ROLLING,
			# and a bucket that already slides is not slowed down. Snow friction is
			# dry, so there is no bounce.
			var contact_offset := -normal * footprint_radius
			var surface_vel := state.linear_velocity + state.angular_velocity.cross(contact_offset)
			var slip := surface_vel - normal * surface_vel.dot(normal)
			var friction_force := -slip * mass * 30.0
			var max_friction := CONTACT_FRICTION * normal_force
			if friction_force.length() > max_friction:
				friction_force = friction_force.normalized() * max_friction
			state.apply_force(friction_force, contact_offset)

	if pos.y - footprint_radius <= 0.03:
		_grounded = true

	# The bucket is dragged, not carried: the ground holds its weight and the leash only
	# pulls it along, so it trails behind, skids on a turn and still has to be hauled
	# through deep snow. A frozen body would follow the hand exactly and weigh nothing.
	if is_carried:
		_apply_leash(state)


## Keeps a dragged bucket near the hand: a force towards the hand point, and no force at all
## once it is close enough that a real handle would have gone slack.
func _apply_leash(state: PhysicsDirectBodyState3D) -> void:
	if _carry_target == Vector3.INF:
		return
	var to_target := _carry_target - state.transform.origin
	var distance := to_target.length()
	if distance <= push_reach_min or distance < 0.001:
		return
	var pull := to_target / distance
	var accel := minf(CARRY_LEASH_ACCEL, (distance - push_reach_min) * 24.0)
	state.apply_central_force(pull * accel * mass)


# ---------------------------------------------------------------------------------------
# Carrying and dragging, on the same state the snowball uses: `is_carried` plus these three
# calls are the whole contract the player's carrying code knows about. `carry_to` remembers
# where the hand is and lets the physics step haul the body there, rather than teleporting
# it, so a carried bucket still collides with the world.
# ---------------------------------------------------------------------------------------
func begin_carry() -> void:
	is_carried = true
	sleeping = false


func carry_to(target: Vector3, _delta: float) -> void:
	_carry_target = target


func end_carry(impulse_velocity: Vector3 = Vector3.ZERO, _by_node: Node = null) -> void:
	is_carried = false
	_carry_target = Vector3.INF
	linear_velocity = impulse_velocity
	sleeping = false
	_play_sound(SoundEffectsScript.get_snow_thud(), -14.0, 0.9)


# ---------------------------------------------------------------------------------------
# Sound. Tipping, loading and being set down all get a voice; none of them changes the
# physics, and a missing stream is simply silent.
# ---------------------------------------------------------------------------------------
func _play_sound(stream: AudioStream, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = stream
	sfx.volume_db = volume_db
	sfx.pitch_scale = pitch * randf_range(0.94, 1.06)
	sfx.unit_size = 6.0
	var host := get_parent()
	if host == null:
		return
	host.add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func play_fill_sound() -> void:
	_play_sound(SoundEffectsScript.get_snow_thud(), -9.0, 1.25)


func play_tip_sound() -> void:
	_play_sound(SoundEffectsScript.get_snow_step(), -5.0, 0.85)

