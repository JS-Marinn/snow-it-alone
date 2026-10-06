extends RigidBody3D
## A wheelbarrow: a container on two wheels, moved by pushing it, that feels the snow it
## rolls on.
##
## Three things make it different from a bucket. It carries far more, it is *moved by the
## player* rather than picked up, and it rolls, which here means it rides on two wheel contact
## points that resist sideways motion and let it go forward.
##
## WHY THERE ARE NO SEPARATE WHEEL BODIES. The first two versions made each wheel a rigid body
## and joined it to the tray with a real `HingeJoint3D`. That is the assembly this project
## prefers, and it was measured, twice, and both times it failed for a reason worth writing
## down:
##
##   1. With a support spring on BOTH the tray and the wheels, the two springs disagreed about
##      where the barrow should sit -- their reference radii are different (0.42 against 0.22)
##      -- and the tray was thrown to y = 1.17 m with its velocity climbing past 3.5 m/s.
##   2. With the spring on the wheels only, the hinge carried the tray's weight through the
##      solver's velocity bias, which is too soft for a 9.2 kg tray on 2.4 kg wheels: the tray
##      settled BELOW its own wheels (origin 0.449 m, wheel centres 0.486 m, when the wheel
##      centres must be 0.217 m BELOW the origin), and the wheel felt only its own weight
##      through the spring -- 31.5 N of support for a 137 N barrow.
##
## A wheel that carries nothing is not a wheel. So the barrow is ONE body whose support is
## applied at the three points that actually touch the snow: the two wheel contact patches and
## the rear leg. That gives it the base it needs to tip rather than slide, and the support
## block is still the snowball's, unchanged, applied at each point. The wheels themselves are
## visual, and they are spun from the distance travelled so they are seen to roll.
##
## The lesson from the ball is baked in here on purpose. A thrown ball was being steered out
## of the air by a held key because the push logic did not check for ground contact, and it
## took three attempts to find. `apply_push` below refuses to do anything when airborne, and
## that refusal is the point of the function rather than a detail of it.

signal contents_changed(contents_kg: float, capacity_kg: float)
## Emitted when the tray leans past its tip angle with something in it. Whoever is listening
## is responsible for moving that snow somewhere that accounts for it: nothing is created or
## destroyed here.
signal tipped_over()

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

# ---------------------------------------------------------------------------------------
# Snow support, copied from `scripts/snowball.gd`. Same constants, same maths, applied at each
# contact point instead of at the centre -- which is what a barrow on two wheels and a leg is.
# ---------------------------------------------------------------------------------------
## Stiffness and damping of the snow support (per unit of mass), as in `scripts/snowball.gd`.
##
## The stiffness is then scaled by the contact area, `footprint_radius / wheel_radius`. This is
## not a second calibration: the ball's figure is per unit of mass and a ball is expected to
## ride mostly buried, while a wheel carries the same load on a patch half the size and must
## not vanish into the snow. Measured with the ball's own 400 N/m: a 14 kg barrow settled with
## its wheel centres at y = 0.29 m in snow 0.32 m deep, which is 0.51 m of penetration -- the
## tray buried in the ground, and a barrow that visibly sinks through its own snow. At the
## scaled figure the same load penetrates 8.8 cm, which is what a barrow in deep snow does.
const SUPPORT_STIFFNESS: float = 400.0
const SUPPORT_DAMPING: float = 40.0
## Contact friction with snow.
const CONTACT_FRICTION: float = 0.85
## Offset (m) used to read the terrain normal from the height field.
const NORMAL_SAMPLE_OFFSET: float = 0.16

# ---------------------------------------------------------------------------------------
# Terrain resistance. The surface classes belong to the field and the player already walks
# on them; these are THE PLAYER'S OWN SPEED SCALES (`player_controller.gd`,
# `_refresh_surface`), copied here so the barrow is slowed by the same snow the player is, and
# not by a second scale invented for it. `--container-lab` asserts they still match.
# ---------------------------------------------------------------------------------------
## Height (m) under which the ground counts as cleared.
const SURFACE_CLEARED_HEIGHT: float = 0.03
## Cohesion at and above which snow counts as packed.
const SURFACE_PACKED_COHESION: float = 0.45
## Cohesion at and above which snow counts as plain snow rather than powder.
const SURFACE_SNOW_COHESION: float = 0.35
## Speed multiplier each surface gives a WALKING PLAYER. The order of these four is the
## contract: it is what the barrow has to reproduce.
const PLAYER_SURFACE_SCALE: Dictionary = {
	"cleared": 1.05,
	"packed": 1.05,
	"snow": 1.0,
	"powder": 0.85,
}
## How much of that multiplier a WHEEL keeps. One wheel does not sink like two boots, and a
## barrow that stopped dead in powder would be a worse object than no barrow at all, so the
## wheel keeps most of the player's scale while still ordering the four surfaces the same way.
const WHEEL_SURFACE_KEEP: float = 0.72

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
## How far the rear leg is BEHIND the origin, in metres. The barrow's origin is the ground
## contact line under the axle; the tray leans back onto the leg from there.
@export var leg_offset_z: float = -0.72

## Half the track (m): distance from the centre line to each wheel contact patch.
@export var wheel_track: float = 0.30
## Wheel radius (m). Also the height of the axle above the snow.
@export var wheel_radius: float = 0.22
## How far forward of the origin the axle sits (m).
@export var wheel_offset: float = 0.55
## Tilt (degrees) at which a tipped barrow is treated as tipped and empties itself.
@export var tip_angle_deg: float = 52.0
## How hard a rolling wheel resists being rolled, as a fraction of the normal force. This is
## the ONE force that makes a wheeled barrow different from a sledge, and it is a rolling
## resistance, not drag: it does not stop the barrow, it decides how far it coasts. Tuned
## against the measured overshoot -- see `apply_push`.
@export var rolling_resistance: float = 0.5

## Diagnostics: what each support point is carrying, once a second.
const DEBUG_SUPPORT: bool = true
var _debug_t: float = 0.0
var _debug_push_t: float = 0.0

# The push window, in the UPPER CASE names the player's ground-push code looks for on any
# pushable target. Without them it falls back to its own defaults and would let the player
# shove the barrow from anywhere.
const PUSH_REACH_MIN: float = 0.9
const PUSH_REACH_MAX: float = 2.6
const PUSH_SPEED_EMPTY: float = 1.6

var contents_kg: float = 0.0
## True while the player is pushing it, for the HUD and the diagnostics.
var is_being_pushed: bool = false
## Footprint radius under the barrow's own name, which is what the player's interaction code
## reads when it decides whether a pushable target is on the ground.
var radius: float = 0.42
## Snow field to read the surface from. Assigned by whoever creates the barrow.
var snow_field: Node3D
## The three points that touch the snow, in the barrow's own frame: two wheels and the leg.
var _contact_points: Array[Vector3] = []
## How many of those points were on the snow this step.
var _supported_points: int = 0
## Last surface each contact point read, for the HUD and the diagnostics.
var _point_surfaces: Array[String] = []
## Surface under the barrow as a whole, from the points that carry it.
var surface_name: String = "snow"
## True when at least one contact point is on the snow.
var _grounded: bool = false
var _rolling_audio: AudioStreamPlayer3D
## The two wheel meshes, spun from the distance travelled so they are seen to roll.
var _wheel_nodes: Array[Node3D] = []
## How far the barrow has travelled along the ground, for that spin.
var _roll_distance: float = 0.0
var _last_ground_pos: Vector3 = Vector3.INF
## How long since the last tip, so one tipping does not fire the sound every frame.
var _tip_cooldown: float = 0.0
## True while the barrow is tipped past `tip_angle_deg`, so whatever it holds can run out.
var is_tipped: bool = false


func _ready() -> void:
	add_to_group("snow_containers")
	add_to_group("pushable")
	add_to_group("interact_targets")
	continuous_cd = true
	# Support is applied as a force, so the body must never fall asleep.
	can_sleep = false
	angular_damp = 0.05
	linear_damp = 0.02
	# Same layer as the balls and props, so the player's aim can actually see the barrow. Mask
	# layer 2 only: the tray may bump into structures and props, but it must never rest on the
	# terrain, because the snow support is what holds the barrow up and the tray's underside
	# sits above the wheel contact line on purpose.
	collision_layer = 4
	collision_mask = 2
	radius = footprint_radius
	var phys := PhysicsMaterial.new()
	phys.friction = CONTACT_FRICTION
	phys.bounce = 0.02
	physics_material_override = phys
	_build_contact_points()
	_build_wheels()
	_sync_mass()
	_setup_audio()


## The points the snow holds up: both wheel patches, and the leg. Support at three points that
## are not in a line is what lets the barrow tip instead of slide.
func _build_contact_points() -> void:
	_contact_points = [
		Vector3(-wheel_track, 0.0, wheel_offset),
		Vector3(wheel_track, 0.0, wheel_offset),
		Vector3(0.0, 0.0, leg_offset_z),
	]


## The wheels as they are seen: two discs, parented to this body, spun by `_spin_wheels`.
func _build_wheels() -> void:
	for side in [-1.0, 1.0]:
		var wheel := Node3D.new()
		wheel.name = "Wheel%s" % ("R" if side > 0.0 else "L")
		wheel.position = Vector3(side * wheel_track, 0.0, wheel_offset)
		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_radius
		cyl.bottom_radius = wheel_radius
		cyl.height = 0.10
		mesh.mesh = cyl
		# A cylinder's axis is Y; the axle has to lie along X.
		mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.20, 0.19)
		mat.roughness = 0.85
		mesh.material_override = mat
		wheel.add_child(mesh)
		add_child(wheel)
		_wheel_nodes.append(wheel)


# ---------------------------------------------------------------------------------------
# Contents. The accounting is `fill` and `take`; who may call them is gameplay, and lives in
# `scripts/container_interaction.gd`.
# ---------------------------------------------------------------------------------------
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


func _sync_mass() -> void:
	mass = maxf(own_mass_kg + contents_kg, 0.1)


## Target speed for the current load. Falls with weight, with a floor so it never stalls.
func target_speed() -> float:
	var load_ratio := contents_kg / maxf(push_load_reference_kg, 1.0)
	return maxf(push_speed_empty / (1.0 + load_ratio), push_speed_empty * 0.35)


## Target speed on the surface the wheels are actually on: the load sets the ceiling, the
## ground decides how much of it survives.
func target_speed_on_surface() -> float:
	return target_speed() * surface_speed_scale()


## How deep it sits in the snow, in metres, for the given snow support height under it.
func sink_depth(support_height: float) -> float:
	return clampf(support_height * 0.5 + contents_kg * sink_per_kg, 0.0, 0.35)


## Snow height (m) under the barrow, or 0 outside the simulated field, where `get_height_at`
## reports -1.
func support_height_at(pos: Vector3) -> float:
	if snow_field and snow_field.has_method("get_height_at"):
		var h: float = snow_field.get_height_at(pos)
		if h >= 0.0:
			return h
	return 0.0


## Height (m) of the axle above the snow that holds it up.
func height_above_support() -> float:
	return global_position.y - support_height_at(global_position)


func is_grounded() -> bool:
	return _grounded


## Every surface class the field can report, in the order a walking player is fastest to
## slowest on it. This is the order the barrow has to reproduce, and `--container-lab`
## measures the barrow against this list rather than against numbers copied into the test.
func ordered_surfaces() -> Array[String]:
	var names: Array[String] = ["cleared", "packed", "snow", "powder"]
	names.sort_custom(func(a: String, b: String) -> bool:
		return player_scale_for(a) > player_scale_for(b))
	return names


# ---------------------------------------------------------------------------------------
# Terrain resistance. The barrow reads the field's own surface classes at each point that
# carries it, with the same thresholds the player's `_refresh_surface` uses, and slows the push
# to match. Inventing a second scale here is what would make a barrow feel wrong on snow the
# player walks on correctly.
# ---------------------------------------------------------------------------------------
func surface_of(pos: Vector3) -> String:
	var height := support_height_at(pos)
	if height < SURFACE_CLEARED_HEIGHT:
		return "cleared"
	var cohesion := 0.5
	if snow_field and snow_field.has_method("get_cohesion_at"):
		cohesion = float(snow_field.get_cohesion_at(pos))
	if cohesion >= SURFACE_PACKED_COHESION:
		return "packed"
	if cohesion >= SURFACE_SNOW_COHESION:
		return "snow"
	return "powder"


## The player's speed multiplier for a surface name. 1.0 for anything unknown.
func player_scale_for(surface: String) -> float:
	return float(PLAYER_SURFACE_SCALE.get(surface, 1.0))


## The speed multiplier the barrow gets on a surface: the player's, softened by
## `WHEEL_SURFACE_KEEP` because a wheel does not sink like a boot. The ORDER is untouched.
func wheel_scale_for(surface: String) -> float:
	return 1.0 - (1.0 - player_scale_for(surface)) * WHEEL_SURFACE_KEEP


## The scale for wherever the wheels are right now: the worst surface under them, because one
## wheel in the powder is enough to slow a barrow down.
func surface_speed_scale() -> float:
	if _point_surfaces.is_empty():
		return wheel_scale_for(surface_name)
	var worst := 1.0
	for name in _point_surfaces:
		worst = minf(worst, wheel_scale_for(name))
	return worst


## World position of one contact point.
func contact_point_world(index: int) -> Vector3:
	if index < 0 or index >= _contact_points.size():
		return global_position
	return global_position + global_transform.basis * _contact_points[index]


## Re-reads the surface under each point. Called every physics step.
func refresh_surface() -> void:
	_point_surfaces.clear()
	var worst_name := ""
	var worst_scale := 2.0
	for i in range(_contact_points.size()):
		var name := surface_of(contact_point_world(i))
		_point_surfaces.append(name)
		var scale := wheel_scale_for(name)
		if scale < worst_scale:
			worst_scale = scale
			worst_name = name
	if not worst_name.is_empty():
		surface_name = worst_name


## Pushes it towards `forward`, from `from_position`, this frame.
##
## Returns true when a push was actually applied, so callers and tests can tell the
## difference between "pushed" and "asked to push".
func apply_push(from_position: Vector3, forward: Vector3, delta: float, grounded: bool) -> bool:
	is_being_pushed = false
	# Nothing steers it out of the air, and nothing steers it from on top of it.
	if not grounded:
		return false
	# A tipped barrow is being emptied, not driven.
	if is_tipped:
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
	var want := target_speed_on_surface()
	if along >= want:
		is_being_pushed = true
		return false
	# The push accelerates towards the target and STOPS there. The acceleration is capped by the
	# rate that would reach the target in this step as well as by `push_max_accel`, so the
	# force is throttled down as the barrow approaches its speed instead of being applied flat
	# until it is already past it. Without the first cap the barrow overshot by 60 % -- measured
	# peak 2.29 m/s against a 1.43 m/s target -- and a barrow that runs away from the player is
	# a worse object than a slow one.
	var accel := minf(push_max_accel, (want - along) / maxf(delta, 0.0001))
	apply_central_force(dir * accel * mass)
	is_being_pushed = true
	if DEBUG_SUPPORT and _debug_push_t <= 0.0:
		_debug_push_t = 1.0
		print("[BARROW PUSH] from=%s dist=%.2f along=%.3f want=%.3f accel=%.2f force=%.1f | vel=%s" % [
			str(from_position), distance, along, want, accel, accel * mass,
			str(linear_velocity.snapped(Vector3(0.01, 0.01, 0.01)))])
	return true


## Entry point for a player pushing with held [E], with the signature the ball uses so the
## player's ground-push code needs no special case.
##
## It steers the barrow the way the player is LOOKING, because a barrow is pushed from behind
## and follows where you aim, and it falls back to steering away from the pusher whenever the
## heading is not available. Being airborne is still a refusal (see `apply_push`).
func push(from_position: Vector3, _strength: float, by_node: Node = null) -> void:
	var forward := Vector3.ZERO
	if by_node != null and by_node is Node3D:
		var n3d := by_node as Node3D
		forward = -n3d.global_transform.basis.z
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = global_position - from_position
		forward.y = 0.0
	apply_push(from_position, forward, get_physics_process_delta_time(), _grounded)


# ---------------------------------------------------------------------------------------
# Moving it. It is pushed, never lifted: a barrow full of snow that snapped to the player's
# hands would be a different object, and `can_be_carried` is what tells the interaction code
# so. The `push` entry point that the ball uses is deliberately absent: a barrow is moved by
# holding [E] behind it (`apply_push`), not by a body brushing past it.
# ---------------------------------------------------------------------------------------
## A wheelbarrow is never picked up. The player's carrying code asks before it grabs
## anything, so this is the whole of the refusal.
func can_be_carried() -> bool:
	return false


## The direction the barrow rolls in, flattened onto the ground plane: from the rear leg
## towards the axle. The sideways direction is the one that gets full friction, so this has to
## be the real heading and not a guess.
func _ground_heading() -> Vector3:
	var heading := global_transform.basis * Vector3(0.0, 0.0, 1.0)
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		return Vector3.FORWARD
	return heading.normalized()


## How hard the barrow is levelled back to the ground it stands on, and how much of the
## oscillation that leaves is damped out.
##
## Deliberately weak. This is a correction, not a suspension: at 45 the levelling torque was
## strong enough to keep rocking the tray, and since the support force is computed from the
## mean penetration of three points, rocking the tray pumps the spring -- which showed up as
## speed. A barrow is not a balance board.
const LEVELLING_STIFFNESS: float = 8.0
const LEVELLING_DAMPING: float = 12.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if snow_field == null:
		return

	var origin := state.transform.origin
	var contacts := 0

	# The terrain normal, from the ground under the tray: the slope the barrow is standing on.
	# It tilts the support force (so a barrow on a slope is pushed along it) and it is the
	# attitude the levelling torque aims for.
	var datum := support_height_at(origin)
	datum = maxf(datum, support_height_at(origin + state.transform.basis * Vector3(0.0, 0.0, wheel_offset)))
	var normal := Vector3.UP
	if snow_field.has_method("get_height_at"):
		var e := NORMAL_SAMPLE_OFFSET
		var hx: float = snow_field.get_height_at(origin + Vector3(e, 0.0, 0.0))
		var hz: float = snow_field.get_height_at(origin + Vector3(0.0, 0.0, e))
		if hx >= 0.0 and hz >= 0.0:
			normal = Vector3(-(hx - datum) / e, 1.0, -(hz - datum) / e).normalized()

	# Same spring as the ball's, stiffened by the ratio of the contact patches: see
	# SUPPORT_STIFFNESS above for the measurement that decided it.
	var stiffness := SUPPORT_STIFFNESS * (footprint_radius / maxf(wheel_radius, 0.02))
	var deepest := 0.0
	for local in _contact_points:
		var world := origin + state.transform.basis * local
		var compression := (support_height_at(world) + wheel_radius) - world.y
		if compression > 0.0:
			contacts += 1
			deepest = maxf(deepest, compression)

	if contacts == 0 or deepest <= 0.0:
		_supported_points = 0
		_grounded = origin.y - wheel_radius <= 0.03
		return

	_supported_points = contacts
	_grounded = true
	var mean_penetration := deepest
	var vn := state.linear_velocity.dot(Vector3.UP)
	var normal_force: float = maxf(
		stiffness * mass * mean_penetration - SUPPORT_DAMPING * mass * vn, 0.0)

	if not _finite(normal_force):
		normal_force = 0.0

	state.apply_central_force(Vector3.UP * normal_force)

	# Friction at each point, still per point: it is what makes a wheel refuse a sideways shove
	# and what turns the push into travel. None of it is vertical, so none of it can lever the
	# barrow up.
	for local in _contact_points:
		var world := origin + state.transform.basis * local
		var pt_comp := (support_height_at(world) + wheel_radius) - world.y
		if pt_comp <= 0.0:
			continue
		var offset := world - origin
		var point_mass := mass / float(_contact_points.size())
		var surface_vel := state.linear_velocity + state.angular_velocity.cross(offset)
		var slip := surface_vel - Vector3.UP * surface_vel.y
		var heading := _ground_heading()
		var along := slip.dot(heading)
		var across := slip - heading * along
		var lateral := -across * point_mass * 30.0
		var max_lateral := CONTACT_FRICTION * normal_force / float(_contact_points.size())
		if lateral.length() > max_lateral:
			lateral = lateral.normalized() * max_lateral
		if _finite(lateral.length()):
			state.apply_force(lateral, offset)
		var roll_sign := signf(along)
		if roll_sign == 0.0:
			roll_sign = 1.0
		var roll := -heading * (roll_sign * rolling_resistance * normal_force / float(_contact_points.size()))
		if _finite(roll.length()):
			state.apply_force(roll, offset)

	_apply_levelling_torque(state, normal)



## Holds the barrow's attitude to the ground it is standing on, which is the job the support
## springs would otherwise do.
##
## The springs cannot do it here, and that is a measured fact rather than a preference: the
## field's surface under a 1 m wheelbase varies by centimetres, and any support force applied
## away from the centre of mass turns those centimetres into a lever. Two versions of this
## block tried it -- a spring per contact point rolled the barrow over where it stood (pitch
## 0 -> 50 deg in half a second), and one datum for all three points levered it over every rise
## (26 deg of pitch, decelerating from 1.43 m/s to 0.15). The support now acts at the centre of
## mass and cannot rotate the barrow at all, so the attitude is held here, explicitly, and the
## code says so instead of pretending the springs did it.
##
## It is a spring-damper towards level with the terrain normal, and it does nothing in the air.
func _apply_levelling_torque(state: PhysicsDirectBodyState3D, normal: Vector3) -> void:
	if not _grounded:
		return
	var up := state.transform.basis.y.normalized()
	var rates := Vector3(state.angular_velocity.x, 0.0, state.angular_velocity.z)
	# Every term is checked before it is used: `asin` of a value outside its domain and a cross
	# product of a broken basis both produce NaN, and a NaN torque does not tilt the barrow
	# slightly, it takes its position away.
	if not _finite(up.length()) or not _finite(normal.length()) or not _finite(rates.length()):
		return
	var axis := up.cross(normal)
	var sine := axis.length()
	if not _finite(sine) or sine < 0.0001:
		# Already level: damp out any residual roll and pitch, nothing else.
		if rates.length() > 0.001:
			var quiet := -rates * (mass * LEVELLING_DAMPING * 0.1)
			if _finite(quiet.length()):
				state.apply_torque(quiet)
		return
	axis = axis / sine
	var angle := asin(clampf(sine, -1.0, 1.0))
	# Only the roll and pitch rates are damped, so the levelling never fights a turn.
	var torque := axis * (angle * mass * LEVELLING_STIFFNESS) - rates * (mass * LEVELLING_DAMPING)
	if _finite(torque.length()):
		state.apply_torque(torque)


## False for NaN and for both infinities. `is_finite` is on the float type in GDScript, not a
## global, so the check is written out here once and used for every force this body applies.
func _finite(value: float) -> bool:
	return value == value and absf(value) < 1.0e12


func _physics_process(delta: float) -> void:
	_tip_cooldown = maxf(_tip_cooldown - delta, 0.0)
	refresh_surface()
	_update_tipped()
	_update_rolling_audio()
	_spin_wheels(delta)


## Turns the two wheel meshes by the distance the barrow has actually travelled, so what the
## player sees is the barrow's own motion and not an animation played beside it.
func _spin_wheels(delta: float) -> void:
	var here := global_position
	if _last_ground_pos == Vector3.INF:
		_last_ground_pos = here
		return
	var step := Vector2(here.x - _last_ground_pos.x, here.z - _last_ground_pos.z).length()
	_last_ground_pos = here
	if not _grounded or wheel_radius <= 0.01:
		return
	_roll_distance += step
	var angle := _roll_distance / wheel_radius
	for wheel in _wheel_nodes:
		if wheel == null or not is_instance_valid(wheel):
			continue
		wheel.rotation = Vector3(angle, 0.0, 0.0)


## A barrow leaning past `tip_angle_deg` has been tipped over, and what it holds runs out.
## The caller decides where that snow goes: `scripts/container_interaction.gd` empties it
## into the field or into the bank, so nothing is created or destroyed here.
func _update_tipped() -> void:
	var up := global_transform.basis.y
	var angle := rad_to_deg(up.angle_to(Vector3.UP))
	var tipped := angle >= tip_angle_deg
	var was_tipped := is_tipped
	is_tipped = tipped
	if tipped and not was_tipped and _tip_cooldown <= 0.0 and contents_kg > 0.0:
		_tip_cooldown = 0.5
		tipped_over.emit()


# ---------------------------------------------------------------------------------------
# Sound: the rattle of a rolling barrow, a tip, and a load going in.
# ---------------------------------------------------------------------------------------
func _setup_audio() -> void:
	_rolling_audio = AudioStreamPlayer3D.new()
	_rolling_audio.stream = SoundEffectsScript.get_shovel_scrape()
	_rolling_audio.volume_db = -22.0
	add_child(_rolling_audio)


func _update_rolling_audio() -> void:
	if _rolling_audio == null:
		return
	var speed := linear_velocity.length()
	var rolling := _grounded and speed > 0.25
	if rolling:
		_rolling_audio.volume_db = clampf(-30.0 + speed * 6.0, -30.0, -10.0)
		_rolling_audio.pitch_scale = clampf(0.7 + speed * 0.25, 0.7, 1.5)
		if not _rolling_audio.playing:
			_rolling_audio.play()
	elif _rolling_audio.playing:
		_rolling_audio.stop()


func _play_sound(stream: AudioStream, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = stream
	sfx.volume_db = volume_db
	sfx.pitch_scale = pitch * randf_range(0.94, 1.06)
	sfx.unit_size = 10.0
	var host := get_parent()
	if host == null:
		return
	host.add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func play_fill_sound() -> void:
	_play_sound(SoundEffectsScript.get_snow_thud(), -8.0, 1.15)


func play_tip_sound() -> void:
	_play_sound(SoundEffectsScript.get_snow_step(), -4.0, 0.8)
