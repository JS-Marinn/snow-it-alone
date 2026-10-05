extends Node3D

# PropsSystem - System 4: scatters loose objects around the yard and builds
# snowballs.
#
# There is no assembly bench: branches, stones, carrot and coal are simply lying
# in the snow. The player picks them up and throws them, and the same physics
# rules decide whether they stick, roll or fall out.

const SnowBallScript = preload("res://scripts/snowball.gd")
const PinPropScript = preload("res://scripts/pin_prop.gd")

var snow_field: Node3D
var _rng := RandomNumberGenerator.new()
var _spawned: bool = false

func _ready() -> void:
	add_to_group("props_system")
	_rng.seed = 20260104

func setup(field: Node3D) -> void:
	snow_field = field

func _process(_delta: float) -> void:
	if _spawned or snow_field == null:
		return
	# Wait until the snow field has a CPU mirror before placing anything, so props
	# land on the real surface height.
	if snow_field.has_method("get_height_at") and snow_field.get_height_at(Vector3.ZERO) >= 0.0:
		_spawned = true
		_spawn_loose_props()

func _spawn_loose_props() -> void:
	var kit_z := -6.6
	# Snowman kit next to the bench: carrot and coals
	spawn_prop(PinProp.Kind.CARROT, Vector3(-4.6, 0.0, kit_z), Vector3(deg_to_rad(78.0), 0.4, 0.0))
	for i in range(3):
		spawn_prop(PinProp.Kind.COAL, Vector3(-4.35 + float(i) * 0.16, 0.0, kit_z + 0.28 + float(i) * 0.05), Vector3(randf(), randf(), randf()))
	# Dry branches scattered along the path edges
	var stick_spots := [
		Vector3(-3.4, 0.0, 3.6), Vector3(3.1, 0.0, 1.2), Vector3(-2.2, 0.0, -2.4),
		Vector3(3.6, 0.0, -4.1), Vector3(-3.9, 0.0, -0.6), Vector3(2.4, 0.0, 4.6)
	]
	for spot in stick_spots:
		var rot := Vector3(deg_to_rad(88.0), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.25, 0.25))
		spawn_prop(PinProp.Kind.STICK, spot, rot)
	# Stones
	var stone_spots := [
		Vector3(-3.0, 0.0, 5.0), Vector3(3.3, 0.0, -1.0), Vector3(-2.6, 0.0, -4.4), Vector3(2.9, 0.0, 3.0)
	]
	for spot in stone_spots:
		spawn_prop(PinProp.Kind.STONE, spot, Vector3(randf(), randf(), randf()))

func spawn_prop(kind: PinProp.Kind, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> PinProp:
	var prop := PinPropScript.new() as PinProp
	prop.kind = kind
	prop.snow_field = snow_field
	add_child(prop)
	var h := 0.0
	if snow_field and snow_field.has_method("get_height_at"):
		h = maxf(snow_field.get_height_at(pos), 0.0)
	prop.global_position = Vector3(pos.x, h + 0.06, pos.z)
	prop.global_rotation = rot
	if kind == PinProp.Kind.STICK:
		prop.length = _rng.randf_range(0.55, 1.05)
		# The mesh was already built in _ready with the default length: adjust it
		prop.call_deferred("_rebuild_for_length")
	return prop

## Creates a snowball in the world. Its starting mass comes from the volume the
## player has packed together with their hands.
func spawn_snowball(pos: Vector3, radius: float = 0.12) -> SnowBall:
	var ball := SnowBallScript.new() as SnowBall
	ball.snow_field = snow_field
	add_child(ball)
	ball.setup(radius)
	var h := 0.0
	if snow_field and snow_field.has_method("get_height_at"):
		h = maxf(snow_field.get_height_at(pos), 0.0)
	ball.global_position = Vector3(pos.x, maxf(pos.y, h + radius + 0.01), pos.z)
	return ball
