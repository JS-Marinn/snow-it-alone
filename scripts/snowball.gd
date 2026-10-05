class_name SnowBall
extends RigidBody3D

# Snow ball (system 3): a free 3D granular body that accretes mass.
# It follows no preset motion: it rolls under gravity over the snow surface
# (spring-damper support along the terrain normal), steals volume from the
# height map as it travels (cylindrical harvest) and grows by the equivalent
# sphere R = cbrt(R^3 + 3*dV/(4*pi)). Its mass, inertia and collision radius
# are recomputed dynamically, so a giant ball needs a full body push and slows
# down almost at once.
# Resting on another ball deforms the contact and, if the settle is stable,
# creates a real joint (packed snow) that a hard hit can break.

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

## Density of loose snow in the field (kg/m3): reference for turning a
## terrain volume into mass when the ball absorbs it.
const LOOSE_DENSITY: float = 150.0
## Density of freshly packed snow (kg/m3): denser than the field snow.
const PACKED_DENSITY: float = 300.0
## Density of a large, well-rolled ball: the snow compacts and pushes air out.
const PACKED_DENSITY_COMPACT: float = 470.0
const MAX_RADIUS: float = 0.55
const MIN_RADIUS: float = 0.07
## Maximum force the player can push a ball with (N). Being a force and not
## an acceleration, a heavy ball barely moves.
const PUSH_FORCE_NEWTONS: float = 260.0
## Push acceleration cap, so a tiny ball is not launched across the field.
const PUSH_MAX_ACCEL: float = 26.0
## Stiffness and damping of the snow support (per unit of mass).
const SUPPORT_STIFFNESS: float = 400.0
const SUPPORT_DAMPING: float = 40.0
## Contact friction with snow (rolling grip).
const CONTACT_FRICTION: float = 0.85
## Minimum harvest step (m), so the GPU operation queue is not flooded.
const HARVEST_STEP: float = 0.12
## Largest jump (m) still treated as continuous rolling. A bigger jump is a
## throw, a fall or a respawn, and that stretch is never harvested.
const MAX_HARVEST_STEP: float = 0.45
## Stable contact time needed to consolidate a joint (s).
const SETTLE_TIME: float = 0.30

# Ball size tiers, which decide what a hit does to a player.
enum BallTier { SMALL = 0, MEDIUM = 1, LARGE = 2 }
## Radius bounds of the tiers (m). Small is a ball packed by hand, large is one
## that needs both hands.
const TIER_SMALL_MAX: float = 0.18
const TIER_MEDIUM_MAX: float = 0.34
## Minimum impact speed (m/s) for each tier to have any effect at all. A ball
## that is rolling into you is not a hit.
const TIER_MIN_SPEED: Array[float] = [5.0, 3.5, 2.5]
## Node group that receives ball hits: players and training dummies.
const IMPACT_GROUP: String = "impact_targets"
## Frames of speed history used to work out the speed a contact arrived at.
const ARRIVAL_HISTORY: int = 4

static func tier_for_radius(r: float) -> int:
	if r < TIER_SMALL_MAX:
		return BallTier.SMALL
	if r < TIER_MEDIUM_MAX:
		return BallTier.MEDIUM
	return BallTier.LARGE

func tier() -> int:
	return tier_for_radius(radius)

static var _ball_material: StandardMaterial3D

signal settled_on(ball: SnowBall)

var radius: float = 0.12
var snow_field: Node3D
var is_carried: bool = false
## Accretion efficiency: the share of harvested snow that sticks.
@export var accretion_efficiency: float = 0.75
## Impact speed (m/s) at which the ball BREAKS APART. Rolling and falling
## gently do not break it, a hard hit does.
@export var break_speed_threshold: float = 7.0
## Diagnostic traces for the harvest loop.
var debug_harvest: bool = false
var _harvest_requests: int = 0
var _shattered: bool = false
## Previous position used to sweep for hits on players: a ball crossing a face
## between two frames must still connect.
var _prev_impact_pos: Vector3 = Vector3.INF
## Velocity at the start of the frame, kept for the shatter direction.
var _prev_velocity: Vector3 = Vector3.ZERO
## Fastest speed of the last few frames. A contact is reported after the solver
## has already cancelled the ball's velocity, so the frame it arrives on is not
## the speed it actually arrived at.
var _speed_history: Array[float] = []

var _mesh_instance: MeshInstance3D
var _sphere_mesh: SphereMesh
var _collision: CollisionShape3D
var _shape: SphereShape3D
var _grounded: bool = false

var _last_harvest_pos: Vector3 = Vector3.INF
var _harvest_pending: bool = false
var _harvest_owner: int = 0

var _contact_partner: SnowBall = null
var _contact_time: float = 0.0
var _weld_joint: Generic6DOFJoint3D = null
var _welded_to: SnowBall = null
var _thud_cooldown: float = 0.0

func _ready() -> void:
	_harvest_owner = int(get_instance_id())
	mass = _mass_for_radius(radius)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	angular_damp = 0.05
	linear_damp = 0.02
	# Snow support is resolved by forces, so the ball must never fall asleep or
	# it would stop receiving the field's lift.
	can_sleep = false

	var phys := PhysicsMaterial.new()
	phys.friction = CONTACT_FRICTION
	phys.bounce = 0.02
	physics_material_override = phys

	if not _ball_material:
		_ball_material = StandardMaterial3D.new()
		_ball_material.albedo_color = Color(0.94, 0.965, 1.0)
		_ball_material.roughness = 0.62
		_ball_material.rim_enabled = true
		_ball_material.rim = 0.55
		_ball_material.rim_tint = 0.35

	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radial_segments = 24
	_sphere_mesh.rings = 16
	_apply_radius_to_mesh()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _sphere_mesh
	_mesh_instance.material_override = _ball_material
	add_child(_mesh_instance)

	_shape = SphereShape3D.new()
	_shape.radius = radius
	_collision = CollisionShape3D.new()
	_collision.shape = _shape
	add_child(_collision)

	# Collides with ground, structures and other balls, but NOT with the snow
	# field: support comes from the elastic response to the deformable height
	# map.
	collision_layer = 4
	collision_mask = 1 | 4

	body_entered.connect(_on_body_entered)

	if snow_field and snow_field.has_signal("op_volume_ready"):
		snow_field.op_volume_ready.connect(_on_op_volume_ready)

	add_to_group("snowballs")

func _exit_tree() -> void:
	_break_weld()

# Utilities
## Bulk density of the ball by size: freshly packed snow is fluffy, but as the
## ball grows by rolling it compacts and pushes air out, so a big ball weighs
## far more than a constant density R^3 would suggest.
static func density_for_radius(r: float) -> float:
	var t: float = clampf(r / MAX_RADIUS, 0.0, 1.0)
	return lerpf(PACKED_DENSITY, PACKED_DENSITY_COMPACT, t * t)

func _mass_for_radius(r: float) -> float:
	return (4.0 / 3.0) * PI * r * r * r * density_for_radius(r)

func _apply_radius_to_mesh() -> void:
	if _sphere_mesh:
		_sphere_mesh.radius = radius
		_sphere_mesh.height = radius * 2.0

## Sets the radius, and with it mass, inertia and collision shape are recomputed.
func set_radius(new_radius: float) -> void:
	radius = clampf(new_radius, MIN_RADIUS, MAX_RADIUS)
	mass = _mass_for_radius(radius)
	if _shape:
		_shape.radius = radius
	_apply_radius_to_mesh()

func setup(r0: float) -> void:
	set_radius(r0)
	_last_harvest_pos = Vector3.INF

func packed_mass() -> float:
	return _mass_for_radius(radius)

# Accretion
func _on_op_volume_ready(role: String, owner: int, kg: float) -> void:
	if role != "harvest" or owner != _harvest_owner:
		return
	_harvest_pending = false
	if kg <= 0.0 or is_carried:
		return
	_grow_by_mass(kg * accretion_efficiency)

func _grow_by_mass(kg: float) -> void:
	if kg <= 0.0:
		return
	# Absorbed snow is compacted to the consistency the ball already has
	var dv := kg / density_for_radius(radius)
	var r3 := radius * radius * radius + (3.0 * dv) / (4.0 * PI)
	set_radius(pow(maxf(r3, 1e-9), 1.0 / 3.0))

## Equivalent radius after absorbing a VOLUME of loose field snow.
func absorb_loose_volume(volume_m3: float) -> void:
	_grow_by_mass(volume_m3 * LOOSE_DENSITY)

## Asks the GPU to harvest the trench under the ball and to absorb that exact
## volume.
##
## The `_last_harvest_pos` anchor is the point the harvest runs from to the
## current position, so it is ONLY valid while the ball touches the field
## continuously: as soon as the ball flies (thrown, bouncing or falling) the
## anchor becomes invalid. Without that, landing after a throw harvested a
## straight strip from the launch point to the landing point, leaving an
## unnatural "line" in the snow.
func _try_harvest(_delta: float) -> void:
	if snow_field == null or _harvest_pending:
		return
	if is_carried:
		_last_harvest_pos = Vector3.INF
		return
	if not _grounded:
		# Without support the anchor is only dropped when the ball is CLEARLY
		# airborne (its lowest point above the field), so a flicker of contact
		# while rolling over a bump does not reset the harvest, while a throw or a
		# fall does avoid harvesting the strip between origin and destination.
		var surface := -1.0
		if snow_field.has_method("get_height_at"):
			surface = snow_field.get_height_at(global_position)
		if surface < 0.0 or global_position.y - radius > surface + 0.05:
			_last_harvest_pos = Vector3.INF
		return
	var pos := global_position
	if _last_harvest_pos == Vector3.INF:
		_last_harvest_pos = pos
		return
	var travel := Vector2(pos.x - _last_harvest_pos.x, pos.z - _last_harvest_pos.z).length()
	if travel < HARVEST_STEP:
		return
	if travel > MAX_HARVEST_STEP:
		# Big jump (throw, fall, respawn): re-anchor without harvesting anything
		_last_harvest_pos = pos
		return
	var height := 0.0
	if snow_field.has_method("get_height_at"):
		height = snow_field.get_height_at(pos)
	if height < 0.045 or not snow_field.has_method("request_harvest"):
		_last_harvest_pos = pos
		return
	# The ball sinks partially: it harvests a strip as wide as its footprint and
	# of limited depth (never more than half a ball).
	var max_depth: float = clampf(height * 0.45, 0.01, radius * 0.6)
	snow_field.request_harvest(_harvest_owner, _last_harvest_pos, pos, radius * 0.9, max_depth)
	_harvest_pending = true
	_harvest_requests += 1
	if debug_harvest:
		print("[BALL %d] harvest #%d  from=%s to=%s  depth=%.3f m  h=%.3f" % [
			_harvest_owner, _harvest_requests, str(_last_harvest_pos), str(pos), max_depth, height])
	_last_harvest_pos = pos

# Physics
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if is_carried or snow_field == null or _shattered:
		return

	var pos := state.transform.origin
	var height := -1.0
	if snow_field.has_method("get_height_at"):
		height = snow_field.get_height_at(pos)

	# Elastic support on the snow surface (terrain normal)
	var was_grounded := _grounded
	_grounded = false
	if height >= 0.0:
		var e := 0.16
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
		var penetration := (height + radius) - pos.y
		if penetration > 0.0:
			_grounded = true
			var vn := state.linear_velocity.dot(normal)
			# First contact after flight: a hard hit shatters the ball
			if not was_grounded and absf(vn) > break_speed_threshold:
				_shatter(state.linear_velocity)
				return
			var normal_force: float = maxf(SUPPORT_STIFFNESS * mass * penetration - SUPPORT_DAMPING * mass * vn, 0.0)
			state.apply_central_force(normal * normal_force)

			# Coulomb friction on the REAL SLIP at the contact point (not on the
			# centre velocity): the torque it produces turns sliding into ROLLING,
			# and a ball that already rolls is not slowed down. Snow friction is
			# dry, so there is no bounce.
			var contact_offset := -normal * radius
			var contact_point := pos + contact_offset
			var surface_vel := state.linear_velocity + state.angular_velocity.cross(contact_offset)
			var slip := surface_vel - normal * surface_vel.dot(normal)
			var friction_force := -slip * mass * 30.0
			var max_friction := CONTACT_FRICTION * normal_force
			if friction_force.length() > max_friction:
				friction_force = friction_force.normalized() * max_friction
			state.apply_force(friction_force, contact_offset)

	if pos.y - radius <= 0.03:
		_grounded = true

	# Rolling resistance: grows steeply with ball size
	if _grounded:
		var omega := state.angular_velocity
		if omega.length() > 0.02:
			var size_ratio := clampf(radius / MAX_RADIUS, 0.0, 1.0)
			var decel := (0.012 + 0.38 * size_ratio * size_ratio * size_ratio) * 9.81
			state.apply_torque(-omega.normalized() * (0.4 * mass * radius * decel))
		# Deep snow: progressive braking only while the ball is well buried
		var burial := clampf((height - radius * 0.75) / maxf(radius, 0.05), 0.0, 2.0)
		if burial > 0.0:
			state.linear_velocity *= 1.0 - minf(0.25 * burial * state.step, 0.25)

	_check_ball_contacts(state)

func _check_ball_contacts(state: PhysicsDirectBodyState3D) -> void:
	var partner: SnowBall = null
	var normal := Vector3.ZERO
	for i in range(state.get_contact_count()):
		var other := state.get_contact_collider_object(i)
		if other is SnowBall and other != self:
			partner = other
			normal = (state.transform.basis * state.get_contact_local_normal(i)).normalized()
			break

	if partner == null:
		_contact_time = 0.0
		_contact_partner = null
		return

	# Only balls resting ON TOP of another, well centred, consolidate
	var above: bool = state.transform.origin.y > partner.global_position.y
	var vertical: bool = absf(normal.y) > 0.72
	var slow: bool = state.linear_velocity.length() < 0.4 and partner.linear_velocity.length() < 0.4
	if above and vertical and slow:
		if _contact_partner == partner:
			_contact_time += state.step
		else:
			_contact_partner = partner
			_contact_time = 0.0
		if _contact_time >= SETTLE_TIME and _weld_joint == null and partner._weld_joint == null:
			_weld_to(partner)
	else:
		_contact_partner = partner
		_contact_time = 0.0

## Deformed contact area: the snow yields into a flat surface that gives the
## stack its mechanical stability (block 4.1).
func _weld_to(partner: SnowBall) -> void:
	var joint := Generic6DOFJoint3D.new()
	get_parent().add_child(joint)
	joint.global_position = (global_position + partner.global_position) * 0.5
	joint.exclude_nodes_from_collision = true
	for flag in [Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT]:
		joint.set_flag_x(flag, true)
		joint.set_flag_y(flag, true)
		joint.set_flag_z(flag, true)
	for param in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
			Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
		joint.set_param_x(param, 0.0)
		joint.set_param_y(param, 0.0)
		joint.set_param_z(param, 0.0)
	joint.node_a = joint.get_path_to(self)
	joint.node_b = joint.get_path_to(partner)
	_weld_joint = joint
	_welded_to = partner
	settled_on.emit(partner)

func _break_weld() -> void:
	if _weld_joint and is_instance_valid(_weld_joint):
		_weld_joint.queue_free()
	_weld_joint = null
	if _welded_to and is_instance_valid(_welded_to) and _welded_to._welded_to == self:
		_welded_to._welded_to = null
	_welded_to = null
	_contact_time = 0.0

func is_welded() -> bool:
	return _weld_joint != null

# Ball hits on players and dummies

## Sweeps the ball's own path against every impact target and resolves the first
## hit. Deliberately not a physics contact: a thrown ball must not shove anyone
## around, and what happens depends on the ball's size, not on the solver.
func _check_impact_hits() -> void:
	var to := global_position
	var from := _prev_impact_pos
	_prev_impact_pos = to
	if from == Vector3.INF:
		return
	var speed := linear_velocity.length()
	# The heaviest tier has the lowest bar, so this is the cheapest global gate.
	if speed < TIER_MIN_SPEED[BallTier.LARGE]:
		return
	var ball_tier := tier()
	if speed < TIER_MIN_SPEED[ball_tier]:
		return
	for target in get_tree().get_nodes_in_group(IMPACT_GROUP):
		if not target.has_method("impact_spheres"):
			continue
		# Anything with a body of its own is resolved by its contact instead: the
		# body stops the ball before the sphere test could connect, and doing both
		# would count the hit twice. The sweep exists for targets without one.
		if target is PhysicsBody3D:
			continue
		for sphere in target.impact_spheres():
			var point := _segment_sphere_hit(from, to, sphere["center"], float(sphere["radius"]) + radius)
			if point == Vector3.INF:
				continue
			var accepted: bool = target.receive_ball_hit(ball_tier, speed, bool(sphere["head"]), point, linear_velocity)
			if accepted:
				_shatter(linear_velocity)
			return

## Closest approach of a segment to a sphere: the impact point, or INF on a miss.
func _segment_sphere_hit(from: Vector3, to: Vector3, center: Vector3, sphere_radius: float) -> Vector3:
	var segment := to - from
	var len_sq := segment.length_squared()
	var t := 0.0
	if len_sq > 1e-6:
		t = clampf((center - from).dot(segment) / len_sq, 0.0, 1.0)
	var closest := from + segment * t
	if closest.distance_to(center) <= sphere_radius:
		return closest
	return Vector3.INF

# Loop
func _physics_process(delta: float) -> void:
	if _shattered:
		return
	_thud_cooldown = maxf(_thud_cooldown - delta, 0.0)
	if is_carried:
		return

	# Kept before the physics step, so a contact reported later in the frame can
	# still tell how fast the ball was actually travelling.
	_prev_velocity = linear_velocity
	_speed_history.append(linear_velocity.length())
	while _speed_history.size() > ARRIVAL_HISTORY:
		_speed_history.remove_at(0)
	_try_harvest(delta)
	_check_impact_hits()

	# A hard impact breaks the packed snow joint
	if _weld_joint != null and linear_velocity.length() > 1.8:
		_break_weld()

## Fastest speed seen in the last few frames: see `_speed_history`.
func arrival_speed() -> float:
	var fastest := 0.0
	for s in _speed_history:
		fastest = maxf(fastest, s)
	return fastest

func _on_body_entered(body: Node) -> void:
	if _shattered:
		return
	# Hitting a person. Resolved from this actual contact and not from the sweep:
	# a body stops the ball before it would reach the analytic spheres.
	if body != null and body.is_in_group(IMPACT_GROUP) and body.has_method("receive_ball_hit"):
		var arrival := _prev_velocity
		# The faster of the two. By the time a contact is reported the solver may already
		# have cancelled the ball's velocity, and reading only one of these is how a ball
		# thrown at 8 m/s failed its own size's speed gate and did nothing.
		var hit_speed := maxf(arrival_speed(), linear_velocity.length())
		var ball_tier := tier()
		# The two ways this can end with no reaction recorded: the gate below refused the
		# speed, or the target refused the hit because it was mid-reaction or immune. Both
		# are printed so the next run says which, instead of being guessed at.
		print("[HITDBG] r=%.2f tier=%d speed=%.2f min=%.2f target=%s state=%s immunity=%s" % [
			radius, ball_tier, hit_speed, TIER_MIN_SPEED[ball_tier], body.name,
			str(body.get("hit_state")), str(body.get("hit_immunity"))])
		if hit_speed >= TIER_MIN_SPEED[ball_tier]:
			body.receive_ball_hit(ball_tier, hit_speed, _is_head_hit(body), global_position, arrival)
		# A snowball that lands on a person always bursts, whether or not they were in a
		# state to react. Falling through to the generic branch below used to break the
		# ball on them with no reaction and no record that anything had happened.
		_shatter(arrival)
		return
	var speed := linear_velocity.length()
	# Hard hit against anything shatters the ball
	if speed > break_speed_threshold:
		_shatter(linear_velocity)
		return
	if _thud_cooldown > 0.0:
		return
	if speed < 0.6:
		return
	_thud_cooldown = 0.25
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_thud()
	sfx.volume_db = clampf(-22.0 + speed * 1.2, -22.0, -2.0)
	sfx.pitch_scale = randf_range(0.85, 1.1)
	sfx.unit_size = 8.0
	get_parent().add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
	if _weld_joint != null and speed > 1.8:
		_break_weld()

## A hit counts as one to the face when the ball is level with the head.
func _is_head_hit(body: Node) -> bool:
	if not body.has_method("impact_spheres"):
		return false
	for sphere in body.impact_spheres():
		if bool(sphere["head"]):
			return global_position.y >= float(sphere["center"].y) - float(sphere["radius"]) - radius * 0.5
	return false

## Shatters the ball on impact: its mass is split between the field and a burst
## of fragments (see `scripts/snow_burst.gd`). The ball stops existing as a body.
func _shatter(impact_velocity: Vector3 = Vector3.ZERO) -> void:
	if _shattered or is_carried:
		return
	# Where a ball dies is only half the fact: position says where it happened, the call
	# site says who did it. Four theories in a row were acted on without either.
	var origin := "unknown"
	var stack := get_stack()
	if stack.size() >= 2:
		origin = "%s:%d" % [String(stack[1].get("source", "?")).get_file(), int(stack[1].get("line", 0))]
	print("[BALLDBG] %.2f m ball burst at %s moving %.1f m/s from %s" % [
		radius, str(global_position), impact_velocity.length(), origin])
	_shattered = true
	_break_weld()
	SnowBurst.spawn(get_parent(), global_position, radius, packed_mass(), impact_velocity, snow_field)
	queue_free()

# Interaction
## Player push: a capped FORCE (not an acceleration) applied at the grip point
## rather than at the centre of mass. The ball therefore rolls instead of
## sliding and, above all, a heavy ball barely moves while a light one rolls away.
func push(from_position: Vector3, strength: float) -> void:
	if is_carried:
		return
	var dir := global_position - from_position
	dir.y = 0.0
	if dir.length_squared() < 1e-4:
		return
	dir = dir.normalized()
	var grip := global_position - Vector3(0.0, radius * 0.45, 0.0)
	# Capped force, with an acceleration cap for very light balls
	var force := minf(strength * PUSH_FORCE_NEWTONS, PUSH_MAX_ACCEL * mass)
	apply_force(dir * force, grip - global_position)

func begin_carry() -> void:
	_break_weld()
	_prev_impact_pos = Vector3.INF
	_speed_history.clear()
	is_carried = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	sleeping = false

func carry_to(target: Vector3, delta: float) -> void:
	global_position = global_position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))

func end_carry(impulse_velocity: Vector3 = Vector3.ZERO) -> void:
	is_carried = false
	freeze = false
	linear_velocity = impulse_velocity
	_last_harvest_pos = global_position
	_prev_impact_pos = Vector3.INF
	_speed_history.clear()
