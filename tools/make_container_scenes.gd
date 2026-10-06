extends SceneTree
## Builds the two container scenes from code and saves them as `.tscn`.
##
## The scenes are generated rather than hand-written because every transform in them is a
## number that has to agree with the physics in `scripts/snow_bucket.gd` and
## `scripts/wheelbarrow.gd`: the bucket's collision is a cylinder of its own
## `footprint_radius`, and the barrow's tray has to clear the snow its wheels sink into. A
## hand-typed `Transform3D` that disagrees with those constants is a container that floats or
## buries itself, and it is the kind of mistake that reads as a physics bug for a week.
##
## Run it with:
##     godot --headless --path . --script tools/make_container_scenes.gd
##
## It rewrites `scenes/snow_bucket.tscn` and `scenes/wheelbarrow.tscn`. The wheels are NOT in
## the barrow scene on purpose: they are bodies on hinge joints and `wheelbarrow.gd` builds
## them in `_ready`, from the same exported constants this file uses.

const BUCKET_SCRIPT := "res://scripts/snow_bucket.gd"
const BARROW_SCRIPT := "res://scripts/wheelbarrow.gd"

# Must match the exports in scripts/snow_bucket.gd
const BUCKET_CAPACITY_KG := 12.0
const BUCKET_OWN_MASS_KG := 1.8
const BUCKET_FOOTPRINT_RADIUS := 0.22
# The body of the bucket: a drum as tall as it is wide, so it stands on its own.
const BUCKET_BODY_HEIGHT := 0.42

# Must match the exports in scripts/wheelbarrow.gd
const BARROW_CAPACITY_KG := 60.0
const BARROW_OWN_MASS_KG := 14.0
const BARROW_FOOTPRINT_RADIUS := 0.42
const BARROW_WHEEL_RADIUS := 0.22
const BARROW_WHEEL_OFFSET := 0.55

# Tray geometry. The underside of the tray sits above the wheels' contact line, so the tray
# itself never touches the snow: the wheels are what carries the barrow.
const TRAY_SIZE := Vector3(0.66, 0.45, 1.40)
const TRAY_CENTRE_Y := 0.40
const TRAY_DEPTH := 0.28
# The rear leg: a prop that stops the barrow tipping backwards when a load is dropped in.
const LEG_SIZE := Vector3(0.50, 0.32, 0.07)
const LEG_CENTRE := Vector3(0.0, 0.16, -0.52)

func _init() -> void:
	_save(_build_bucket(), "res://scenes/snow_bucket.tscn")
	_save(_build_barrow(), "res://scenes/wheelbarrow.tscn")
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


func _build_bucket() -> RigidBody3D:
	var root := RigidBody3D.new()
	root.name = "SnowBucket"
	root.set_script(load(BUCKET_SCRIPT))
	root.set("capacity_kg", BUCKET_CAPACITY_KG)
	root.set("own_mass_kg", BUCKET_OWN_MASS_KG)
	root.set("footprint_radius", BUCKET_FOOTPRINT_RADIUS)
	root.set("mass", BUCKET_OWN_MASS_KG)

	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var cyl := CylinderMesh.new()
	cyl.top_radius = BUCKET_FOOTPRINT_RADIUS
	cyl.bottom_radius = BUCKET_FOOTPRINT_RADIUS
	cyl.height = BUCKET_BODY_HEIGHT
	cyl.radial_segments = 16
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.42, 0.50)
	mat.roughness = 0.72
	mat.metallic = 0.25
	mesh.material_override = mat
	root.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = BUCKET_FOOTPRINT_RADIUS
	cyl_shape.height = BUCKET_BODY_HEIGHT
	shape.shape = cyl_shape
	root.add_child(shape)

	# A handle, so it reads as a bucket and not as a tin can.
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var torus := TorusMesh.new()
	torus.inner_radius = BUCKET_FOOTPRINT_RADIUS * 0.75
	torus.outer_radius = BUCKET_FOOTPRINT_RADIUS * 0.85
	handle.mesh = torus
	handle.position = Vector3(0.0, BUCKET_BODY_HEIGHT * 0.5, 0.0)
	handle.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.28, 0.30, 0.33)
	handle_mat.roughness = 0.6
	handle.material_override = handle_mat
	root.add_child(handle)

	_own_all(root)
	return root


func _build_barrow() -> RigidBody3D:
	var root := RigidBody3D.new()
	root.name = "Wheelbarrow"
	root.set_script(load(BARROW_SCRIPT))
	root.set("capacity_kg", BARROW_CAPACITY_KG)
	root.set("own_mass_kg", BARROW_OWN_MASS_KG)
	root.set("footprint_radius", BARROW_FOOTPRINT_RADIUS)
	root.set("wheel_radius", BARROW_WHEEL_RADIUS)
	root.set("wheel_offset", BARROW_WHEEL_OFFSET)
	root.set("mass", BARROW_OWN_MASS_KG)

	var tray_mat := StandardMaterial3D.new()
	tray_mat.albedo_color = Color(0.30, 0.52, 0.62)
	tray_mat.roughness = 0.70
	tray_mat.metallic = 0.20

	# A tray made of a floor and four low walls, so it is open at the top and looks like
	# something you can put snow *into*.
	_add_box(root, "Floor", Vector3(TRAY_SIZE.x, 0.06, TRAY_SIZE.z),
		Vector3(0.0, TRAY_CENTRE_Y - TRAY_SIZE.y * 0.5 + 0.03, 0.0), tray_mat)
	_add_box(root, "WallLeft", Vector3(0.05, TRAY_SIZE.y, TRAY_SIZE.z),
		Vector3(-TRAY_SIZE.x * 0.5 + 0.025, TRAY_CENTRE_Y, 0.0), tray_mat)
	_add_box(root, "WallRight", Vector3(0.05, TRAY_SIZE.y, TRAY_SIZE.z),
		Vector3(TRAY_SIZE.x * 0.5 - 0.025, TRAY_CENTRE_Y, 0.0), tray_mat)
	_add_box(root, "WallBack", Vector3(TRAY_SIZE.x, TRAY_SIZE.y, 0.05),
		Vector3(0.0, TRAY_CENTRE_Y, -TRAY_SIZE.z * 0.5 + 0.025), tray_mat)
	_add_box(root, "WallFront", Vector3(TRAY_SIZE.x, TRAY_SIZE.y * 0.55, 0.05),
		Vector3(0.0, TRAY_CENTRE_Y - TRAY_SIZE.y * 0.22, TRAY_SIZE.z * 0.5 - 0.025), tray_mat)

	# The tray volume as ONE collision box, slightly inside the visual so it does not catch on
	# things it is not touching. The underside clears the wheel contact line by design.
	var tray_shape := CollisionShape3D.new()
	tray_shape.name = "TrayCollision"
	var tray_box := BoxShape3D.new()
	tray_box.size = Vector3(TRAY_SIZE.x - 0.04, TRAY_SIZE.y, TRAY_SIZE.z - 0.04)
	tray_shape.shape = tray_box
	tray_shape.position = Vector3(0.0, TRAY_CENTRE_Y, 0.0)
	root.add_child(tray_shape)

	# The leg: it reaches the ground and takes the load off the wheels when the barrow rests.
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.34, 0.26, 0.18)
	leg_mat.roughness = 0.85
	_add_box(root, "LegLeft", LEG_SIZE, LEG_CENTRE + Vector3(-0.17, 0.0, 0.0), leg_mat)
	_add_box(root, "LegRight", LEG_SIZE, LEG_CENTRE + Vector3(0.17, 0.0, 0.0), leg_mat)

	var leg_shape := CollisionShape3D.new()
	leg_shape.name = "LegCollision"
	var leg_box := BoxShape3D.new()
	leg_box.size = Vector3(TRAY_SIZE.x, LEG_SIZE.y, LEG_SIZE.z)
	leg_shape.shape = leg_box
	leg_shape.position = LEG_CENTRE
	root.add_child(leg_shape)

	# Handles: the two grips the player actually holds, angled back from the tray.
	for side in [-1.0, 1.0]:
		var grip := MeshInstance3D.new()
		grip.name = "Handle%s" % ("R" if side > 0.0 else "L")
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.06, 0.62)
		grip.mesh = box
		grip.position = Vector3(side * 0.26, 0.62, -0.86)
		grip.rotation = Vector3(deg_to_rad(-16.0), 0.0, 0.0)
		var grip_mat := StandardMaterial3D.new()
		grip_mat.albedo_color = Color(0.34, 0.26, 0.18)
		grip_mat.roughness = 0.85
		grip.material_override = grip_mat
		root.add_child(grip)

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
