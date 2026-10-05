class_name SnowBurst
extends Object

# Splits a snowball's mass between the snow field, which takes the bulk of it at
# the impact point, and a burst of fragments that reabsorb on landing. Keeps the
# world's mass economy closed.

# FINAL ART HOOK: fragments are placeholders (spherical clods) and the puff uses
# throwaway particles. Assign `fragment_scene` / `puff_scene` to swap in the real
# pre-fractured model and effect; `_make_fragment()` and `_spawn_puff()` are the
# only two places that instantiate them, so mass, impulses and reabsorption stay
# untouched.

## Final fragment model (pre-fractured). Falls back to the placeholder clod.
static var fragment_scene: PackedScene = null
## Final powdered-snow puff effect. Falls back to placeholder particles.
static var puff_scene: PackedScene = null
## Fraction of the mass that returns straight to the snow field on impact.
static var terrain_mass_fraction: float = 0.55
## Fragment scatter impulse, in m/s per metre of radius.
static var scatter_speed: float = 3.2

const SnowChunkScript = preload("res://scripts/snow_chunk.gd")
const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

static var _puff_material: StandardMaterial3D

## Breaks a ball apart at `pos`. Returns the number of fragments launched.
static func spawn(parent: Node, pos: Vector3, radius: float, mass_kg: float,
		velocity: Vector3, snow_field: Node3D, fragments: int = 0) -> int:
	if parent == null or not is_instance_valid(parent):
		return 0
	var n: int = fragments if fragments > 0 else clampi(int(6.0 + radius * 24.0), 6, 20)
	var mass_terrain: float = mass_kg * clampf(terrain_mass_fraction, 0.0, 1.0)
	var mass_fragments: float = maxf(mass_kg - mass_terrain, 0.0)

	# 1) Most of the snow goes back to the snow field right where it hit
	if snow_field and snow_field.has_method("dump_snow") and mass_terrain > 0.01:
		snow_field.dump_snow(pos, mass_terrain, maxf(radius * 1.4, 0.24))

	# 2) Fragment burst carrying the remaining mass; each one reabsorbs on landing
	var per_fragment: float = mass_fragments / float(n) if n > 0 else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 1000.0) ^ int(pos.z * 7919.0) ^ n
	for i in range(n):
		var frag := _make_fragment(parent, pos, radius, per_fragment)
		if frag == null:
			continue
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.35, 1.1), rng.randf_range(-1.0, 1.0)).normalized()
		var speed: float = scatter_speed * (0.6 + rng.randf()) * clampf(radius / 0.2, 0.5, 2.5)
		frag.linear_velocity = velocity * 0.35 + dir * speed

	# 3) Powdered-snow puff
	_spawn_puff(parent, pos, radius)

	# 4) Impact sound
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_thud()
	sfx.volume_db = -2.0 + clampf(radius * 6.0, 0.0, 4.0)
	sfx.pitch_scale = rng.randf_range(0.8, 1.0)
	sfx.unit_size = 10.0
	parent.add_child(sfx)
	sfx.global_position = pos
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
	return n

## Creates ONE fragment. Single swap point for the final model; see the hook above.
static func _make_fragment(parent: Node, pos: Vector3, radius: float, mass_kg: float) -> RigidBody3D:
	if fragment_scene != null:
		var node := fragment_scene.instantiate()
		if node is RigidBody3D:
			parent.add_child(node)
			node.global_position = pos
			return node as RigidBody3D
		# Not a rigid body: it cannot be used, but a RigidBody3D must still be
		# returned for physics.
		node.queue_free()
	var chunk := SnowChunkScript.new() as RigidBody3D
	chunk.set("kg_weight", maxf(mass_kg, 0.05))
	chunk.set("is_toss", false)
	parent.add_child(chunk)
	chunk.global_position = pos + Vector3(
		randf_range(-radius, radius) * 0.5, randf_range(0.0, radius), randf_range(-radius, radius) * 0.5)
	return chunk

## Powdered-snow puff (placeholder for the final effect).
static func _spawn_puff(parent: Node, pos: Vector3, radius: float) -> void:
	if puff_scene != null:
		var fx := puff_scene.instantiate()
		parent.add_child(fx)
		if fx is Node3D:
			(fx as Node3D).global_position = pos
		if fx.has_method("emit"):
			fx.call("emit")
		var timer := parent.get_tree().create_timer(3.0) if parent.get_tree() else null
		if timer:
			timer.timeout.connect(fx.queue_free)
		return

	if _puff_material == null:
		_puff_material = StandardMaterial3D.new()
		_puff_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_puff_material.albedo_color = Color(0.96, 0.98, 1.0, 0.85)
		_puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.emitting = true
	puff.amount = clampi(int(18.0 + radius * 60.0), 18, 60)
	puff.lifetime = 0.7
	puff.explosiveness = 0.9
	puff.spread = 70.0
	puff.initial_velocity_min = 1.4
	puff.initial_velocity_max = 3.6
	puff.gravity = Vector3(0.0, -9.0, 0.0)
	puff.scale_amount_min = maxf(radius * 0.10, 0.03)
	puff.scale_amount_max = maxf(radius * 0.22, 0.06)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = _puff_material
	puff.mesh = mesh
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(puff)
	puff.global_position = pos
