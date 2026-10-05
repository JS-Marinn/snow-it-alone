class_name PinProp
extends RigidBody3D

# Environment props (system 4.2) that pin themselves physically.
# Sticks, stones, carrots and coal have no "assemble button": entering packed
# snow (the field or a ball) fast enough pins them with a real PinJoint3D or by
# kinematic freezing at the contact point. If the player pulls on them they come
# out again, and if the snow holding them is shovelled away they fall on their own.

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

enum Kind { STICK, STONE, CARROT, COAL }

const SUPPORT_STIFFNESS: float = 500.0
const SUPPORT_DAMPING: float = 45.0

static var _wood_mat: StandardMaterial3D
static var _stone_mat: StandardMaterial3D
static var _carrot_mat: StandardMaterial3D
static var _coal_mat: StandardMaterial3D

@export var kind: Kind = Kind.STICK
@export var length: float = 0.85
## 0 = blunt (will not pin), 1 = very sharp.
@export_range(0.0, 1.0) var sharpness: float = 0.85
## Minimum kinetic energy (J per kg) for the object to pin.
@export var pin_min_speed: float = 0.55
## Support radius on the field (m), so the prop does not sink to the ground.
@export var support_radius: float = 0.05

var snow_field: Node3D
var is_pinned: bool = false
var is_carried: bool = false
var support_radius_effective: float = 0.05

var _tip_local: Vector3 = Vector3.ZERO
var _pin_joint: PinJoint3D = null
var _pinned_ball: SnowBall = null
var _pin_ball_offset: Vector3 = Vector3.ZERO
var _pin_world_point: Vector3 = Vector3.ZERO
var _pin_snow_depth: float = 0.0
var _mesh: MeshInstance3D
var _check_timer: float = 0.0
var _thud_cooldown: float = 0.0

func _ready() -> void:
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	angular_damp = 0.4
	linear_damp = 0.1

	var phys := PhysicsMaterial.new()
	phys.friction = 0.7
	phys.bounce = 0.08
	physics_material_override = phys

	collision_layer = 8
	collision_mask = 1 | 4 | 8

	_build_mesh()
	body_entered.connect(_on_body_entered)
	add_to_group("pin_props")

## Rebuilds a stick's mesh once the game fixes its final length.
func _rebuild_for_length() -> void:
	if kind != Kind.STICK or _mesh == null:
		return
	var cyl := CylinderMesh.new()
	var r := clampf(0.012 + length * 0.012, 0.012, 0.03)
	cyl.top_radius = r * 0.7
	cyl.bottom_radius = r
	cyl.height = length
	cyl.radial_segments = 8
	_mesh.mesh = cyl
	_tip_local = Vector3(0.0, -length * 0.5, 0.0)
	support_radius_effective = r

func _tip_offset_length() -> float:
	return _tip_local.length()

func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var radius := 0.03
	match kind:
		Kind.STICK:
			var cyl := CylinderMesh.new()
			radius = clampf(0.012 + length * 0.012, 0.012, 0.03)
			cyl.top_radius = radius * 0.7
			cyl.bottom_radius = radius
			cyl.height = length
			cyl.radial_segments = 8
			_mesh.mesh = cyl
			_mesh.material_override = _get_wood_material()
			_tip_local = Vector3(0.0, -length * 0.5, 0.0)
			support_radius_effective = radius
		Kind.STONE:
			var sph := SphereMesh.new()
			radius = randf_range(0.06, 0.13)
			sph.radius = radius
			sph.height = radius * 2.0
			sph.radial_segments = 10
			sph.rings = 6
			_mesh.mesh = sph
			_mesh.material_override = _get_stone_material()
			_tip_local = Vector3(0.0, -radius * 0.6, 0.0)
			support_radius_effective = radius
			sharpness = minf(sharpness, 0.25)
		Kind.CARROT:
			var cone := CylinderMesh.new()
			radius = 0.045
			cone.top_radius = 0.004
			cone.bottom_radius = radius
			cone.height = 0.26
			cone.radial_segments = 10
			_mesh.mesh = cone
			_mesh.material_override = _get_carrot_material()
			_tip_local = Vector3(0.0, -0.13, 0.0)
			support_radius_effective = 0.045
		Kind.COAL:
			var box := BoxMesh.new()
			box.size = Vector3(0.045, 0.045, 0.045)
			_mesh.mesh = box
			_mesh.material_override = _get_coal_material()
			_tip_local = Vector3(0.0, -0.02, 0.0)
			support_radius_effective = 0.023
			sharpness = minf(sharpness, 0.15)
	add_child(_mesh)

func _get_wood_material() -> StandardMaterial3D:
	if not _wood_mat:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.albedo_color = Color(0.36, 0.24, 0.14)
		_wood_mat.roughness = 0.85
	return _wood_mat

func _get_stone_material() -> StandardMaterial3D:
	if not _stone_mat:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_color = Color(0.42, 0.43, 0.46)
		_stone_mat.roughness = 0.9
	return _stone_mat

func _get_carrot_material() -> StandardMaterial3D:
	if not _carrot_mat:
		_carrot_mat = StandardMaterial3D.new()
		_carrot_mat.albedo_color = Color(0.92, 0.45, 0.09)
		_carrot_mat.roughness = 0.7
	return _carrot_mat

func _get_coal_material() -> StandardMaterial3D:
	if not _coal_mat:
		_coal_mat = StandardMaterial3D.new()
		_coal_mat.albedo_color = Color(0.09, 0.09, 0.1)
		_coal_mat.roughness = 0.6
	return _coal_mat

# Physics
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if is_carried or is_pinned or snow_field == null:
		return
	if not snow_field.has_method("get_height_at"):
		return
	var pos := state.transform.origin
	var height: float = snow_field.get_height_at(pos)
	if height < 0.0:
		return
	# Soft support on the field (there is no real collision with snow)
	var penetration := (height + support_radius_effective) - pos.y
	if penetration > 0.0:
		var vn := state.linear_velocity.y
		var force: float = maxf(SUPPORT_STIFFNESS * mass * penetration - SUPPORT_DAMPING * mass * vn, 0.0)
		state.apply_central_force(Vector3.UP * force)

func _physics_process(delta: float) -> void:
	_thud_cooldown = maxf(_thud_cooldown - delta, 0.0)
	if is_carried:
		return

	if is_pinned:
		_maintain_pin()
		return

	# Pin check at 15 Hz: enough, and cheap
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.066
	_try_pin()

func _maintain_pin() -> void:
	# Pinned in the field: if the snow holding it disappears, it falls on its own
	if _pinned_ball == null and snow_field and snow_field.has_method("get_height_at"):
		var h: float = snow_field.get_height_at(_pin_world_point)
		if h < _pin_snow_depth * 0.35:
			unpin(Vector3.ZERO)
			return
	# Pinned to a ball: if the pivot drifts too far away, it pops out
	if _pinned_ball != null:
		if not is_instance_valid(_pinned_ball):
			unpin(Vector3.ZERO)
			return
		var offset := global_position - _pinned_ball.global_position
		if offset.distance_to(_pin_ball_offset) > 0.30:
			unpin(_pinned_ball.linear_velocity)

## Tries to pin the object into the snow or into a snow ball.
func _try_pin() -> void:
	if sharpness < 0.3:
		return
	var tip_world := global_transform * _tip_local
	var speed := linear_velocity.length()

	# 1) Is there a snow ball in the path of the tip?
	var ball := _find_ball_near(tip_world, maxf(_tip_offset_length(), 0.12))
	if ball != null:
		if speed >= pin_min_speed or global_position.distance_to(ball.global_position) < ball.radius + _tip_offset_length():
			_pin_to_ball(ball, tip_world)
			return

	# 2) Is the tip inside the field, and is that snow compact enough?
	if snow_field == null or not snow_field.has_method("get_height_at"):
		return
	var height: float = snow_field.get_height_at(tip_world)
	if height <= 0.0:
		return
	var depth := height - tip_world.y
	if depth <= 0.01:
		return
	var cohesion := 1.0
	if snow_field.has_method("get_cohesion_at"):
		cohesion = snow_field.get_cohesion_at(tip_world)
	var loose := 0.0
	if snow_field.has_method("get_loose_fraction_at"):
		loose = snow_field.get_loose_fraction_at(tip_world)
	# Freshly dumped powder snow holds nothing; packed snow does.
	var holds := sharpness * (0.35 + 0.65 * cohesion) * (1.0 - 0.6 * loose)
	if holds < 0.22:
		return
	if speed < pin_min_speed and depth < 0.05:
		return
	_pin_to_ground(tip_world, depth)

## Returns the ball whose surface is closer than `reach` to the given point.
func _find_ball_near(point: Vector3, reach: float) -> SnowBall:
	var best: SnowBall = null
	var best_gap := reach
	for node in get_tree().get_nodes_in_group("snowballs"):
		var ball := node as SnowBall
		if ball == null:
			continue
		var gap := ball.global_position.distance_to(point) - ball.radius
		if gap < best_gap:
			best = ball
			best_gap = gap
	return best

## Player push on a loose object (body to body or with the shovel).
func push(from_position: Vector3, strength: float) -> void:
	if is_carried:
		return
	if is_pinned:
		return
	var dir := global_position - from_position
	dir.y = 0.0
	if dir.length_squared() < 1e-4:
		return
	apply_central_impulse(dir.normalized() * strength * mass * 0.02)

func _pin_to_ball(ball: SnowBall, tip_world: Vector3) -> void:
	var joint := PinJoint3D.new()
	get_parent().add_child(joint)
	joint.global_position = tip_world
	joint.node_a = joint.get_path_to(ball)
	joint.node_b = joint.get_path_to(self)
	_pin_joint = joint
	_pinned_ball = ball
	_pin_ball_offset = global_position - ball.global_position
	is_pinned = true
	_play_pin_sound(0.0)

func _pin_to_ground(tip_world: Vector3, depth: float) -> void:
	_pin_world_point = tip_world
	_pin_snow_depth = depth
	_pinned_ball = null
	is_pinned = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_play_pin_sound(0.0)

## Releases the object. With a non-zero `impulse` it is thrown out.
func unpin(impulse: Vector3 = Vector3.ZERO) -> void:
	if _pin_joint and is_instance_valid(_pin_joint):
		_pin_joint.queue_free()
	_pin_joint = null
	_pinned_ball = null
	is_pinned = false
	if freeze:
		freeze = false
		linear_velocity = impulse
	_play_pin_sound(0.05)

## Deliberate pull by the player: returns true if it came loose.
func try_extract() -> bool:
	if not is_pinned:
		return false
	unpin(Vector3(0.0, 0.8, 0.0))
	return true

func _play_pin_sound(bend: float) -> void:
	if _thud_cooldown > 0.0:
		return
	_thud_cooldown = 0.2
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_thud()
	sfx.volume_db = -16.0 + linear_velocity.length()
	sfx.pitch_scale = randf_range(0.7, 0.95) + bend
	sfx.unit_size = 6.0
	get_parent().add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

func _on_body_entered(body: Node) -> void:
	if body is SnowBall and is_pinned and _pinned_ball == null:
		# A hard impact rips out an object pinned in the field
		var ball := body as SnowBall
		if ball.linear_velocity.length() > 1.2:
			unpin(ball.linear_velocity * 0.6)

# Interaction
func begin_carry() -> void:
	if is_pinned:
		unpin(Vector3.ZERO)
	is_carried = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	sleeping = false

func carry_to(target: Vector3, delta: float) -> void:
	global_position = global_position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))

func end_carry(impulse_velocity: Vector3 = Vector3.ZERO, _by_node: Node = null) -> void:
	is_carried = false
	freeze = false
	linear_velocity = impulse_velocity
	# Natural orientation when thrown: the tip (local -Y) points along the
	# impulse, so a stick thrown downwards pins itself.
	if impulse_velocity.length() > 1.5:
		var dir := impulse_velocity.normalized()
		var y_axis := -dir
		var up_ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var x_axis := up_ref.cross(y_axis)
		if x_axis.length() < 0.01:
			x_axis = Vector3.RIGHT
		x_axis = x_axis.normalized()
		transform.basis = Basis(x_axis, y_axis, x_axis.cross(y_axis).normalized())
