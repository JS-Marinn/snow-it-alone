extends Node3D

const AUTOSAVE_INTERVAL: float = 60.0

@onready var snow_field: Node3D = $SnowField
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD

var _session_time: float = 0.0
var _save_timer: float = 0.0

func _ready() -> void:
	if player and snow_field:
		player.snow_field = snow_field
		if snow_field.has_method("get_snow_height"):
			var init_h = snow_field.get_snow_height(player.global_position)
			var init_y = maxf(init_h - 0.035, 0.0)
			player.global_position.y = init_y
			if "current_ground_y" in player:
				player.current_ground_y = init_y
				player.is_ground_initialized = true
	
	if hud and player and snow_field:
		hud.init_hud(player, snow_field)

	_setup_props_system()
	_build_cozy_environment()
	_spawn_training_dummy()
	_print_tree_recursive(self)
	_restore_session()

	var args := OS.get_cmdline_user_args()
	var is_demo := args.has("--plow-demo")
	var is_phys_demo := args.has("--phys-demo")
	var is_scripted := is_demo or is_phys_demo or args.has("--carve-quality") \
		or args.has("--ball-shape") or args.has("--movement-lab") or args.has("--impact-lab")
	# Screenshots belong to diagnostics only; a normal session must not write files.
	if is_scripted:
		get_tree().create_timer(9.5 if is_demo else 1.8).timeout.connect(capture_screenshot)
	if is_demo:
		get_tree().create_timer(11.0).timeout.connect(get_tree().quit)
	if is_phys_demo:
		_start_physics_demo()
	if args.has("--carve-quality"):
		_start_demo_script("res://scripts/carve_quality_demo.gd")
	if args.has("--ball-shape"):
		_start_demo_script("res://scripts/ball_shape_demo.gd")
	if args.has("--movement-lab"):
		_start_demo_script("res://scripts/movement_lab_demo.gd")
	if args.has("--impact-lab"):
		_start_demo_script("res://scripts/impact_lab_demo.gd")

## Picks up the session started from the main menu: restores the money counter and
## starts tracking playtime for the save slot.
func _restore_session() -> void:
	if hud and hud.has_signal("level_completed"):
		hud.level_completed.connect(_on_level_completed)
	if SaveSystem.current_slot < 0:
		return
	if hud and hud.has_method("set_coins"):
		hud.set_coins(int(SaveSystem.data.get("coins", 0)))

func _on_level_completed(cleared_pct: float) -> void:
	if SaveSystem.current_slot < 0:
		return
	SaveSystem.record_result(cleared_pct, hud.coins if hud else 0)
	print("[Save] slot %d updated: %.1f%% cleared, $%d total" % [
		SaveSystem.current_slot, cleared_pct, SaveSystem.data.get("coins", 0)])

func _process(delta: float) -> void:
	if SaveSystem.current_slot >= 0:
		_session_time += delta
		_save_timer += delta
		if _save_timer >= AUTOSAVE_INTERVAL:
			_save_timer = 0.0
			SaveSystem.add_playtime(_session_time)
			_session_time = 0.0
			SaveSystem.save_current()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_save()
		get_tree().quit()

func _exit_tree() -> void:
	_flush_save()

func _flush_save() -> void:
	if SaveSystem.current_slot < 0:
		return
	SaveSystem.add_playtime(_session_time)
	_session_time = 0.0
	SaveSystem.save_current()

func _setup_props_system() -> void:
	var props := Node3D.new()
	props.name = "PropsSystem"
	props.set_script(load("res://scripts/props_system.gd"))
	add_child(props)
	if props.has_method("setup"):
		props.setup(snow_field)
	if player and "props_system" in player:
		player.props_system = props

## One dummy beside the path, so the hit reactions are playable without a second
## person. The level proper will place them deliberately.
func _spawn_training_dummy() -> void:
	var dummy := Node3D.new()
	dummy.name = "TrainingDummy"
	dummy.set_script(load("res://scripts/training_dummy.gd"))
	dummy.position = Vector3(3.0, 0.0, 4.5)
	add_child(dummy)

func _start_physics_demo() -> void:
	_start_demo_script("res://scripts/physics_demo.gd")

## Runs a scripted diagnostic. The exit timer is armed before loading, so a battery
## with a parse error still closes the window instead of hanging forever.
func _start_demo_script(path: String) -> void:
	get_tree().create_timer(45.0).timeout.connect(get_tree().quit)
	var demo_script = load(path)
	if demo_script == null:
		push_error("Could not load %s" % path)
		get_tree().create_timer(2.0).timeout.connect(get_tree().quit)
		return
	var demo = demo_script.new()
	if demo == null:
		push_error("Could not instantiate %s" % path)
		get_tree().create_timer(2.0).timeout.connect(get_tree().quit)
		return
	add_child(demo)
	if demo.has_method("setup"):
		demo.setup(self, snow_field, player, get_node_or_null("PropsSystem"))
	
func _print_tree_recursive(n: Node, depth: int = 0) -> void:
	var prefix = "  ".repeat(depth)
	if n is Node3D:
		print("%s- %s (%s) pos=%s scale=%s vis=%s" % [prefix, n.name, n.get_class(), str(n.global_position), str(n.scale), str(n.visible)])
	for child in n.get_children():
		_print_tree_recursive(child, depth + 1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		capture_screenshot()

func capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var v_tex = get_viewport().get_texture()
	if v_tex:
		var img = v_tex.get_image()
		if img:
			var path = ProjectSettings.globalize_path("res://screenshot.png")
			var err = img.save_png(path)
			print("[Visual] Screenshot saved (err=%d) to %s (size=%s)" % [err, path, str(img.get_size())])

func _build_cozy_environment() -> void:
	var field_len = 12.0
	var field_w = 8.0
	if "field_length" in snow_field: field_len = snow_field.field_length
	if "field_width" in snow_field: field_w = snow_field.field_width
	
	var house_z = -field_len * 0.5 - 2.8
	
	# 1. Nordic cottage with a snow covered roof and chimney
	var cottage_scene = load("res://assets/models/cozy_cottage.glb")
	if cottage_scene:
		var cottage = cottage_scene.instantiate()
		cottage.position = Vector3(0.0, 0.0, house_z)
		cottage.scale = Vector3(1.65, 1.65, 1.65)
		cottage.rotation.y = PI
		add_child(cottage)
		
		# Warm window and porch light
		var porch_light = OmniLight3D.new()
		porch_light.light_color = Color(1.0, 0.82, 0.52)
		porch_light.light_energy = 3.0
		porch_light.omni_range = 9.0
		porch_light.shadow_enabled = true
		porch_light.position = Vector3(0.0, 2.7, house_z + 1.2)
		add_child(porch_light)
		
		for wx in [-3.2, 3.2]:
			var win_light = OmniLight3D.new()
			win_light.light_color = Color(1.0, 0.84, 0.48)
			win_light.light_energy = 2.2
			win_light.omni_range = 8.0
			win_light.position = Vector3(wx, 2.1, house_z + 0.8)
			add_child(win_light)
	
	# 2. Rustic fences flanking the driveway
	var fence_scene = load("res://assets/models/cabin_fence.glb")
	if fence_scene:
		var z_start = -field_len * 0.5 - 1.0
		var z_end = field_len * 0.5 + 1.0
		var step_z = 2.2
		var cur_z = z_start
		while cur_z <= z_end:
			for side in [-1, 1]:
				var fence = fence_scene.instantiate()
				fence.position = Vector3(side * (field_w * 0.5 + 0.45), 0.0, cur_z)
				fence.scale = Vector3(1.5, 1.5, 1.5)
				fence.rotation.y = deg_to_rad(90.0 if side == 1 else -90.0)
				add_child(fence)
			cur_z += step_z
	
	# 3. Snow banks along both sides of the path
	var pile_scene = load("res://assets/models/snow_pile.glb")
	if pile_scene:
		var pile_positions = [
			Vector3(-field_w * 0.5 - 1.2, 0, -4.0),
			Vector3(-field_w * 0.5 - 1.4, 0, 1.5),
			Vector3(-field_w * 0.5 - 1.1, 0, 5.0),
			Vector3(field_w * 0.5 + 1.3, 0, -3.5),
			Vector3(field_w * 0.5 + 1.2, 0, 2.0),
			Vector3(field_w * 0.5 + 1.4, 0, 5.5),
			Vector3(-3.8, 0, house_z + 1.0),
			Vector3(3.8, 0, house_z + 1.0)
		]
		for p in pile_positions:
			var pile = pile_scene.instantiate()
			pile.position = p
			var s = randf_range(1.4, 2.2)
			pile.scale = Vector3(s, s * 0.8, s)
			pile.rotation.y = randf_range(0, TAU)
			add_child(pile)
	
	# 4. Decorative snowman in the yard
	var snowman_scene = load("res://assets/models/snowman.glb")
	if snowman_scene:
		var snowman = snowman_scene.instantiate()
		snowman.position = Vector3(field_w * 0.5 + 1.8, 0.0, house_z + 1.5)
		snowman.scale = Vector3(1.3, 1.3, 1.3)
		snowman.rotation.y = deg_to_rad(-140.0)
		add_child(snowman)
	
	# 5. Snowy wooden bench by the porch
	var bench_scene = load("res://assets/models/bench.glb")
	if bench_scene:
		var bench = bench_scene.instantiate()
		bench.position = Vector3(-field_w * 0.5 - 1.2, 0.0, house_z + 2.0)
		bench.scale = Vector3(1.4, 1.4, 1.4)
		bench.rotation.y = deg_to_rad(45.0)
		add_child(bench)
	
	# 6. Outdoor ground plane and matching collision
	var snow_mat = StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.93, 0.96, 1.0)
	snow_mat.roughness = 0.65
	snow_mat.rim_enabled = true
	snow_mat.rim = 0.55
	snow_mat.rim_tint = 0.40
	
	var static_ground = StaticBody3D.new()
	var ground_col = CollisionShape3D.new()
	var ground_box = BoxShape3D.new()
	ground_box.size = Vector3(140.0, 0.4, 140.0)
	ground_col.shape = ground_box
	ground_col.position = Vector3(0, -0.22, 0)
	static_ground.add_child(ground_col)
	add_child(static_ground)

	var terrain = MeshInstance3D.new()
	var ground_plane = PlaneMesh.new()
	ground_plane.size = Vector2(140.0, 140.0)
	terrain.mesh = ground_plane
	terrain.material_override = snow_mat
	terrain.position = Vector3(0, -0.01, 0)
	add_child(terrain)
	
	# 7. Pine forest around the field
	_plant_pine_forest()

func _plant_pine_forest() -> void:
	var tree_scenes = [
		load("res://assets/models/tree_snow_a.glb"),
		load("res://assets/models/tree_snow_b.glb"),
		load("res://assets/models/tree_snow_c.glb")
	]
	
	var valid_trees = []
	for s in tree_scenes:
		if s: valid_trees.append(s)
	
	if valid_trees.is_empty():
		return
	
	var tree_mat = StandardMaterial3D.new()
	var colormap_tex = load("res://assets/models/colormap.png")
	if colormap_tex:
		tree_mat.albedo_texture = colormap_tex
		tree_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tree_mat.roughness = 0.8
	tree_mat.rim_enabled = true
	tree_mat.rim = 0.35
	
	var tree_placements = [
		# Left side of the path
		{"pos": Vector3(-7.5, 0, -6.5), "scale": 2.4, "rot": 0.5},
		{"pos": Vector3(-9.5, 0, -2.0), "scale": 2.8, "rot": 1.7},
		{"pos": Vector3(-7.8, 0, 3.0), "scale": 2.2, "rot": 2.9},
		{"pos": Vector3(-10.2, 0, 7.5), "scale": 3.0, "rot": 0.8},
		{"pos": Vector3(-13.0, 0, -0.5), "scale": 3.2, "rot": 1.2},
		{"pos": Vector3(-12.5, 0, 5.0), "scale": 2.6, "rot": 2.1},
		
		# Right side of the path
		{"pos": Vector3(7.5, 0, -6.0), "scale": 2.5, "rot": 2.4},
		{"pos": Vector3(9.8, 0, -1.5), "scale": 2.9, "rot": 0.3},
		{"pos": Vector3(8.0, 0, 3.5), "scale": 2.3, "rot": 1.5},
		{"pos": Vector3(10.5, 0, 8.0), "scale": 3.1, "rot": 3.0},
		{"pos": Vector3(13.2, 0, 1.0), "scale": 2.7, "rot": 0.9},
		{"pos": Vector3(12.8, 0, 6.0), "scale": 3.2, "rot": 2.2},
		
		# Background forest behind the cottage
		{"pos": Vector3(-6.5, 0, -12.5), "scale": 3.4, "rot": 0.4},
		{"pos": Vector3(-2.5, 0, -13.5), "scale": 3.6, "rot": 1.9},
		{"pos": Vector3(2.5, 0, -13.8), "scale": 3.5, "rot": 2.7},
		{"pos": Vector3(7.0, 0, -12.8), "scale": 3.3, "rot": 1.1},
		{"pos": Vector3(0.0, 0, -15.0), "scale": 3.8, "rot": 0.6}
	]
	
	for idx in range(tree_placements.size()):
		var data = tree_placements[idx]
		var scene = valid_trees[idx % valid_trees.size()]
		var tree = scene.instantiate()
		tree.position = data["pos"]
		var s = data["scale"]
		tree.scale = Vector3(s, s, s)
		tree.rotation.y = data["rot"]
		_apply_material_recursive(tree, tree_mat)
		add_child(tree)

func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)
