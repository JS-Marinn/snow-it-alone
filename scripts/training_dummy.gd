extends Node3D

# Training dummy: something to throw snowballs at, on your own.
#
# It implements the same impact contract as the player (`impact_spheres` +
# `receive_ball_hit`), which is what lets the whole hit system be played and
# tested without a second person.
#
# It has no collision body on purpose: hits are resolved by the ball's sweep, so
# the reaction never depends on the physics solver's contact order.

enum DummyState { NORMAL = 0, STAGGERED = 1, KNOCKED_DOWN = 2 }

signal hit_taken(tier: int, head_hit: bool)

@export var reactions_enabled: bool = true
@export var stagger_time: float = 1.0
@export var knockdown_time: float = 2.0
@export var face_snow_time: float = 3.5
@export var hit_immunity_time: float = 1.5

const SessionModeScript = preload("res://scripts/session_mode.gd")
var state: int = DummyState.NORMAL
var state_timer: float = 0.0
var hit_immunity: float = 0.0
var face_snow_timer: float = 0.0
var hits_taken: int = 0
var last_hit_tier: int = -1
var last_hit_was_head: bool = false

var _body_node: Node3D
var _face_blob: MeshInstance3D
var _time: float = 0.0

func _ready() -> void:
	add_to_group(SnowBall.IMPACT_GROUP)
	_build_visual()

func _build_visual() -> void:
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.95, 0.97, 1.0)
	snow_mat.roughness = 0.6

	_body_node = Node3D.new()
	add_child(_body_node)

	var post := MeshInstance3D.new()
	var post_mesh := CapsuleMesh.new()
	post_mesh.radius = 0.28
	post_mesh.height = 1.5
	post.mesh = post_mesh
	post.material_override = snow_mat
	post.position = Vector3(0.0, 0.75, 0.0)
	_body_node.add_child(post)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head.mesh = head_mesh
	head.material_override = snow_mat
	head.position = Vector3(0.0, 1.62, 0.0)
	_body_node.add_child(head)

	# Snow on the face, shown only while the dummy is "blinded".
	var blob := MeshInstance3D.new()
	var blob_mesh := SphereMesh.new()
	blob_mesh.radius = 0.19
	blob_mesh.height = 0.38
	blob.mesh = blob_mesh
	var blob_mat := StandardMaterial3D.new()
	blob_mat.albedo_color = Color(1.0, 1.0, 1.0)
	blob_mat.roughness = 0.45
	blob.material_override = blob_mat
	blob.position = Vector3(0.0, 0.0, -0.10)
	blob.visible = false
	_face_blob = blob
	_body_node.get_child(1).add_child(blob)

func _physics_process(delta: float) -> void:
	_time += delta
	hit_immunity = maxf(hit_immunity - delta, 0.0)
	if state != DummyState.NORMAL:
		state_timer = maxf(state_timer - delta, 0.0)
		if state_timer <= 0.0:
			state = DummyState.NORMAL
			hit_immunity = hit_immunity_time
	if face_snow_timer > 0.0:
		face_snow_timer = maxf(face_snow_timer - delta, 0.0)
	_update_pose()
	_face_blob.visible = face_snow_timer > 0.0

## Same shape as the player: a head sphere and a torso sphere.
func impact_spheres() -> Array:
	return [
		{"center": global_position + Vector3(0.0, 1.62, 0.0), "radius": 0.22, "head": true},
		{"center": global_position + Vector3(0.0, 0.75, 0.0), "radius": 0.30, "head": false},
	]

func receive_ball_hit(tier: int, _speed: float, head_hit: bool, _point: Vector3, _dir: Vector3) -> bool:
	if not reactions_enabled or not SessionModeScript.reactions_enabled():
		return false
	if hit_immunity > 0.0 or state != DummyState.NORMAL:
		return false
	hits_taken += 1
	last_hit_tier = tier
	last_hit_was_head = head_hit
	match tier:
		SnowBall.BallTier.SMALL:
			if head_hit:
				face_snow_timer = face_snow_time
		SnowBall.BallTier.MEDIUM:
			state = DummyState.STAGGERED
			state_timer = stagger_time
			if head_hit:
				face_snow_timer = face_snow_time
		SnowBall.BallTier.LARGE:
			state = DummyState.KNOCKED_DOWN
			state_timer = knockdown_time
			if head_hit:
				face_snow_timer = face_snow_time
	hit_taken.emit(tier, head_hit)
	return true

## Staggered dummies sway, knocked down ones lie flat and get back up.
func _update_pose() -> void:
	var lean := 0.0
	if state == DummyState.STAGGERED:
		lean = sin(_time * 9.0) * 0.28
	elif state == DummyState.KNOCKED_DOWN:
		var fall := clampf(state_timer / maxf(knockdown_time, 0.01), 0.0, 1.0)
		lean = sin(fall * PI) * 1.35
	_body_node.rotation.z = lean
	_body_node.rotation.x = 0.0

func reset_reactions() -> void:
	state = DummyState.NORMAL
	state_timer = 0.0
	hit_immunity = 0.0
	face_snow_timer = 0.0
	hits_taken = 0
	last_hit_tier = -1
	last_hit_was_head = false
	_update_pose()