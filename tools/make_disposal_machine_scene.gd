extends SceneTree
## Builds the disposal machine's provisional scene and saves it as `scenes/disposal_machine.tscn`.
##
## Generated rather than hand-written for the same reason the container scenes are: the
## reception mouth, the chute and the box are numbers that have to agree with each other and
## with `scripts/disposal_machine.gd`. A hand-typed transform that puts the mouth where the
## chute is not is a machine that looks broken and works fine, or the other way round.
##
## There is no model on purpose. A flat-coloured box with a collision shape and a visible
## chute is what the brief asks for: obviously provisional, enough to test the mechanic.
##
## Run it with:
##     godot --headless --path . --script tools/make_disposal_machine_scene.gd

const MACHINE_SCRIPT := "res://scripts/disposal_machine.gd"

## The box the player sees. Big enough to read as a machine, small enough to see over.
const BODY_SIZE := Vector3(1.70, 1.50, 1.20)
const BODY_CENTRE_Y := 0.75
## The mouth, on the -Z face (the front). A funnel lip so it reads as something you feed.
const MOUTH_SIZE := Vector3(1.10, 0.55, 0.10)
const MOUTH_CENTRE := Vector3(0.0, 1.05, -BODY_SIZE.z * 0.5 - 0.05)
## The chute the snow comes OUT of: a stub on the +Z face, angled up and back, because the
## whole point of the visible spout is to explain where the snow goes.
const CHUTE_SIZE := Vector3(0.45, 0.45, 0.70)
const CHUTE_CENTRE := Vector3(0.0, 1.55, 0.55)
const CHUTE_TILT_DEG := -22.0
## The trailer the chute throws into. It is scenery: no collision, no script, nothing moves it.
const TRAILER_SIZE := Vector3(2.20, 1.30, 3.40)
const TRAILER_CENTRE := Vector3(0.0, 0.65, 2.60)


func _init() -> void:
	_save(_build(), "res://scenes/disposal_machine.tscn")
	quit()


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("could not pack %s (error %d)" % [path, err])
		print("[SCENEGEN] FAILED: could not pack %s (error %d)" % [path, err])
		root.free()
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s (error %d)" % [path, err])
		print("[SCENEGEN] FAILED: could not save %s (error %d)" % [path, err])
	else:
		print("[SCENEGEN] wrote %s (%d nodes)" % [path, _count(root)])
	root.free()


func _count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count(child)
	return n


func _flat_colour(r: float, g: float, b: float, roughness: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(r, g, b)
	mat.roughness = roughness
	return mat


func _build() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "DisposalMachine"
	root.set_script(load(MACHINE_SCRIPT))

	# The body. Provisional, flat, and clearly not art.
	var body_mat := _flat_colour(0.55, 0.30, 0.14, 0.85)
	_add_box(root, "Body", BODY_SIZE, Vector3(0.0, BODY_CENTRE_Y, 0.0), body_mat)

	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyCollision"
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	body_shape.shape = box
	body_shape.position = Vector3(0.0, BODY_CENTRE_Y, 0.0)
	root.add_child(body_shape)

	# The mouth: darker, recessed, so the front reads as an opening.
	var mouth_mat := _flat_colour(0.09, 0.09, 0.11, 0.95)
	_add_box(root, "Mouth", MOUTH_SIZE, MOUTH_CENTRE, mouth_mat)

	# The chute, angled up and back over the shoulder of the machine.
	var chute := MeshInstance3D.new()
	chute.name = "Chute"
	var chute_box := BoxMesh.new()
	chute_box.size = CHUTE_SIZE
	chute.mesh = chute_box
	chute.position = CHUTE_CENTRE
	chute.rotation = Vector3(deg_to_rad(CHUTE_TILT_DEG), 0.0, 0.0)
	chute.material_override = _flat_colour(0.38, 0.40, 0.44, 0.7)
	root.add_child(chute)

	# A hood over the chute's end, so the snow is seen to be thrown downwards into the trailer
	# rather than into the sky.
	var hood := MeshInstance3D.new()
	hood.name = "ChuteHood"
	var hood_box := BoxMesh.new()
	hood_box.size = Vector3(0.50, 0.18, 0.34)
	hood.mesh = hood_box
	hood.position = CHUTE_CENTRE + Vector3(0.0, 0.32, 0.42)
	hood.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	hood.material_override = _flat_colour(0.30, 0.32, 0.35, 0.7)
	root.add_child(hood)

	# Legs, so the box is not sitting flat on the snow like a crate.
	for side in [-1.0, 1.0]:
		_add_box(root, "Leg%s" % ("R" if side > 0.0 else "L"),
			Vector3(0.16, 0.30, 0.16),
			Vector3(side * 0.62, 0.15, 0.0),
			_flat_colour(0.24, 0.22, 0.20, 0.9))

	# The trailer the chute feeds. Scenery only: no collision shape, no script. It is there so
	# the visible output means something, and it is the one piece that is expected to be
	# replaced by art.
	var trailer := MeshInstance3D.new()
	trailer.name = "Trailer"
	var trailer_box := BoxMesh.new()
	trailer_box.size = TRAILER_SIZE
	trailer.mesh = trailer_box
	trailer.position = TRAILER_CENTRE
	trailer.material_override = _flat_colour(0.30, 0.26, 0.20, 0.9)
	root.add_child(trailer)

	_own_all(root)
	return root


func _add_box(parent: Node, name: String, size: Vector3, centre: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = centre
	mesh.material_override = mat
	parent.add_child(mesh)


func _own_all(node: Node) -> void:
	for child in node.get_children():
		child.owner = node
		_own_all(child)
