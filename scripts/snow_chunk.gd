extends RigidBody3D

# A loose clod of snow. Any fragment that runs out of kinetic energy dissolves
# and gives its volume back to the snow field where it stopped (Block 3.3), so
# the system never loses mass along the way.

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

var kg_weight: float = 2.0
var snow_field: Node3D
var has_hit: bool = false
var lifetime: float = 0.0
var bounce_count: int = 0
var is_toss: bool = false

static var snow_mat: StandardMaterial3D

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	add_to_group("snow_chunks")

	var phys_mat = PhysicsMaterial.new()
	phys_mat.bounce = 0.32
	phys_mat.friction = 0.55
	physics_material_override = phys_mat

	if not snow_mat:
		snow_mat = StandardMaterial3D.new()
		snow_mat.albedo_color = Color(0.93, 0.96, 1.0)
		snow_mat.roughness = 0.55
		snow_mat.rim_enabled = true
		snow_mat.rim = 0.60
		snow_mat.rim_tint = 0.35

	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = clampf(0.08 + kg_weight * 0.02, 0.08, 0.22)
	sphere.height = sphere.radius * 1.8
	sphere.radial_segments = 8
	sphere.rings = 6
	mesh_inst.mesh = sphere
	mesh_inst.material_override = snow_mat
	add_child(mesh_inst)

	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = sphere.radius
	col.shape = shape
	add_child(col)

func _process(delta: float) -> void:
	lifetime += delta
	# A rolled clod that has run out of energy dissolves into the snow field
	if not is_toss and lifetime > 0.4 and linear_velocity.length() < 0.55 and is_on_floor_ish():
		_reabsorb()
		return
	if lifetime > 2.6:
		var s = maxf(1.0 - (lifetime - 2.6) / 0.8, 0.01)
		scale = Vector3(s, s, s)
	if lifetime > 3.4:
		_reabsorb()

func is_on_floor_ish() -> bool:
	if snow_field and snow_field.has_method("get_height_at"):
		var h: float = snow_field.get_height_at(global_position)
		return h >= 0.0 and global_position.y <= h + 0.25
	return false

## Gives the volume back to the terrain (strict mass conservation).
func _reabsorb() -> void:
	if snow_field and snow_field.has_method("dump_snow"):
		var r := clampf(0.10 + kg_weight * 0.03, 0.10, 0.28)
		snow_field.dump_snow(global_position, kg_weight, r)
	queue_free()

func _on_body_entered(_body: Node) -> void:
	bounce_count += 1

	if is_toss:
		if has_hit:
			return
		has_hit = true
		if snow_field and "check_snowbank_hit" in snow_field:
			snow_field.check_snowbank_hit(global_position, kg_weight)

		var sfx = AudioStreamPlayer3D.new()
		sfx.stream = SoundEffectsScript.get_snow_thud()
		sfx.pitch_scale = randf_range(0.85, 1.15)
		sfx.volume_db = -1.0
		sfx.unit_size = 12.0
		get_parent().add_child(sfx)
		sfx.global_position = global_position
		sfx.play()
		sfx.finished.connect(sfx.queue_free)
		_reabsorb()
	else:
		if bounce_count == 1:
			var sfx = AudioStreamPlayer3D.new()
			sfx.stream = SoundEffectsScript.get_snow_thud()
			sfx.pitch_scale = randf_range(0.95, 1.25)
			sfx.volume_db = -7.0
			sfx.unit_size = 6.0
			get_parent().add_child(sfx)
			sfx.global_position = global_position
			sfx.play()
			sfx.finished.connect(sfx.queue_free)
