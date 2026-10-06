extends Node3D

# Playground: the measuring bench, not content.
#
# The level's snow field is 8 x 12 m, which is why bunny-hop chains currently run off
# the end of the simulation and why slopes cannot be studied at all. This scene trades
# texel density for length: the simulation grid is a fixed 512 squared whatever the
# field measures, so 10 x 40 m gives 12.8 texels/m along the runway against 42.7 in the
# level. A development scene can afford that, and the coarse mirror that the movement
# code actually reads is unaffected.
#
# What it offers:
#   four surfaces side by side (virgin, packed, cleared, deep), manufactured with the
#   same operations the game uses, so they cannot drift away from the real thing
#   ramps at 10 and 20 degrees, as plain geometry: a slope cannot carry simulated snow
#   yet, because the field is a horizontal plane
#   training dummies, a ball spawner, a ledger readout, a free camera
#
# Run it with the game's --playground flag, or run its own battery with
# --playground-check, which performs a scripted sequence and reports a verdict.

const DummyScript = preload("res://scripts/training_dummy.gd")
const DisposalMachineScript = preload("res://scripts/disposal_machine.gd")
const DISPOSAL_SCENE: String = "res://scenes/disposal_machine.tscn"
const BUCKET_SCENE: String = "res://scenes/snow_bucket.tscn"
const BARROW_SCENE: String = "res://scenes/wheelbarrow.tscn"

const LANE_X: Array[float] = [-3.75, -1.25, 1.25, 3.75]
const LANE_NAMES: Array[String] = ["virgin", "packed", "shovelled", "deep"]
const RUN_START: float = -18.0
const RUN_END: float = 18.0
const BALL_RADII: Array[float] = [0.10, 0.24, 0.45]

@onready var snow_field: Node3D = $SnowField
@onready var player: CharacterBody3D = $Player

var props: Node3D
var free_cam: Camera3D
var free_cam_on: bool = false
var ball_radius_index: int = 0
var _ledger_label: Label
var _hint_label: Label
var _measured_before: float = 0.0
var _measured_after: float = 0.0
## Mass this scene created out of nothing, which the balance check subtracts again.
var _free_injected: float = 0.0
var _spawned_ball: Node = null
var _checks_ok: int = 0
var _checks_fail: int = 0
var _check_mode: bool = false
var _t: float = 0.0
var _steps: Array = []
var _step_index: int = 0
var _empty_since: float = 0.0
## The on-screen line that names the new shovel buttons, when that mode is on.
var _shovel_hint: String = ""

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_check_mode = OS.get_cmdline_user_args().has("--playground-check") \
		or OS.get_cmdline_args().has("--playground-check")
	_wire_player()
	_build_props()
	_build_dummies()
	_build_ramps()
	_place_disposal_machine()
	_place_containers()
	_init_hud()
	_build_overlay()
	_build_free_camera()

	const CelShadingSystem = preload("res://scripts/cel_shading_system.gd")
	# Cel shading is off: the owner tried it in game and did not like the result. The shaders
	# and this system are intact in materials/_future/ and here, so bringing it back is a matter of
	# uncommenting the next line and switching toon_enabled back to true in the snow shader.
	#CelShadingSystem.apply_cel_shading(self)
	# The lanes need the simulation alive, but they must not wait for a signal that
	# only fires once an operation has already happened: polling the flag is honest and
	# immediate. Operations are then drained a few per frame, because the simulation's
	# operation buffer is bounded and a burst of 180 would be dropped.
	if snow_field.has_signal("op_volume_ready"):
		snow_field.op_volume_ready.connect(_on_op_volume_ready)
	if OS.get_cmdline_user_args().has("--beetle-roll"):
		var script = load("res://scripts/beetle_roll_demo.gd")
		var demo = Node.new()
		demo.set_script(script)
		add_child(demo)
		if demo.has_method("setup"):
			demo.setup(self, snow_field, player, props)
		return
	if OS.get_cmdline_user_args().has("--shovel-modes"):
		var sm_script = load("res://scripts/shovel_modes_demo.gd")
		var sm = Node.new()
		sm.set_script(sm_script)
		add_child(sm)
		if sm.has_method("setup"):
			sm.setup(self, snow_field, player, props)
		return
	if OS.get_cmdline_user_args().has("--pg-reticle-probe"):
		var pgr_script = load("res://scripts/pg_reticle_probe.gd")
		var pgr = Node.new()
		pgr.set_script(pgr_script)
		add_child(pgr)
		if pgr.has_method("setup"):
			pgr.setup(self, snow_field, player, props)
		return
	if OS.get_cmdline_user_args().has("--aim-probe"):
		# Measuring instrument, not a battery: it asserts nothing and only prints what the
		# reticle decides for each aim case. See `scripts/aim_probe_demo.gd`.
		var probe_script = load("res://scripts/aim_probe_demo.gd")
		var probe = Node.new()
		probe.set_script(probe_script)
		add_child(probe)
		if probe.has_method("setup"):
			probe.setup(self, snow_field, player, props)
		return
	if OS.get_cmdline_user_args().has("--disposal-machine"):
		# The disposal machine battery lives here for the same reason the rest do: this is the
		# measuring bench, and the machine is placed here first.
		var script = load("res://scripts/disposal_machine_demo.gd")
		var lab = Node.new()
		lab.set_script(script)
		add_child(lab)
		if lab.has_method("setup"):
			lab.setup(self, snow_field, player, props)
		return
	if _check_mode:
		_start_check()
	else:
		print("[PG] playground ready: %.0f x %.0f m field, %.0f kg of snow" % [
			float(snow_field.get("field_width")), float(snow_field.get("field_length")),
			float(snow_field.get("total_snow_kg"))])

## The player expects the field and the props system to be handed to it: the level scene
## does this in main.gd, so the Playground has to do the same.
func _wire_player() -> void:
	if player == null or snow_field == null:
		return
	var ground := _support_height(Vector3(0.0, 0.0, RUN_START))
	player.global_position = Vector3(0.0, ground, RUN_START)
	if "snow_field" in player:
		player.snow_field = snow_field
	if player.has_method("set_snow_field"):
		player.set_snow_field(snow_field)
	# THE ONE LINE. The test scene is the only place that asks for the load-and-push shovel; the
	# main game never does, so it keeps the legacy behaviour. The mode value comes from the module
	# rather than a bare number, so this line stays honest if the enum ever changes.
	var ShovelModes = load("res://scripts/shovel_modes.gd")
	if ShovelModes != null and player.has_method("set_shovel_mode"):
		var mode: int = int(ShovelModes.Mode.LOAD_AND_PUSH)
		player.set_shovel_mode(mode)
		print("[PG] shovel mode: %s" % str(ShovelModes.mode_name(mode)))
		# Say on screen what the buttons do, because this mode reuses two bindings whose meaning
		# changed. A player who has played the level will otherwise press the right button
		# expecting a throw and get a release.
		_shovel_hint = "Shovel (new mode):  LEFT = push and pick up a little   |   RIGHT = release what you are carrying"
		print("[PG] %s" % _shovel_hint)
	player.set("current_ground_y", ground)
	player.set("is_ground_initialized", true)
	if player.has_method("grant_all_tools"):
		player.grant_all_tools()
	if player.has_method("equip_tool"):
		player.equip_tool("shovel")

func _build_props() -> void:
	props = Node3D.new()
	props.name = "PropsSystem"
	props.set_script(load("res://scripts/props_system.gd"))
	add_child(props)
	if props.has_method("setup"):
		props.setup(snow_field)
	if player and "props_system" in player:
		player.props_system = props

func _build_dummies() -> void:
	for i in range(3):
		var dummy := Node3D.new()
		dummy.name = "TrainingDummy%d" % i
		dummy.set_script(DummyScript)
		dummy.position = Vector3(2.5, 0.0, 2.0 + float(i) * 6.5)
		add_child(dummy)


## The snow disposal machine: the first place snow actually leaves the world. It lives here
## first because this is the measuring bench, and everything is tried here before the level.
##
## PLACEHOLDER PLACEMENT: near the end of the runway (z = 17 is within simulated snow), so
## chunks, balls and containers have simulated terrain under them and a clear path in front.
func _place_disposal_machine() -> void:
	var scene := load(DISPOSAL_SCENE)
	if scene == null:
		push_warning("Disposal machine scene missing; the Playground will have no sink.")
		return
	var machine: Node = scene.instantiate()
	machine.name = "DisposalMachine"
	machine.position = Vector3(0.0, 0.0, RUN_END - 1.0)
	add_child(machine)
	if machine.has_signal("snow_received") and player != null:
		machine.snow_received.connect(_on_snow_sent)
	print("[PG] disposal machine placed at %s (placeholder placement, near the end of the runway)" % [
		str(machine.position)])


## A delivery arrived at the machine: the player is paid, exactly as the bank used to pay.
##
## The Playground has no HUD, but the player still holds the purse, so a battery can read the
## balance. The fallback pays nobody and says so rather than failing silently.
func _on_snow_sent(kg: float, world_pos: Vector3) -> void:
	var coins := int(ceil(kg * DisposalMachineScript.PAYOUT_PER_KG))
	if player != null:
		player.add_coins(coins)
	print("[DISP] %.2f kg sent at %s, paid %d coins" % [kg, str(world_pos), coins])


## Places the bucket and the wheelbarrow in the playground near player spawn.
func _place_containers() -> void:
	var bucket_res := load(BUCKET_SCENE)
	if bucket_res != null:
		var bucket: Node = bucket_res.instantiate()
		bucket.name = "SnowBucket"
		bucket.set("snow_field", snow_field)
		var b_pos := Vector3(-1.8, 0.0, RUN_START + 2.5)
		b_pos.y = _support_height(b_pos) + 0.22
		(bucket as Node3D).position = b_pos
		add_child(bucket)
		print("[PG] bucket placed at %s" % str(b_pos))

	var barrow_res := load(BARROW_SCENE)
	if barrow_res != null:
		var barrow: Node = barrow_res.instantiate()
		barrow.name = "Wheelbarrow"
		barrow.set("snow_field", snow_field)
		var w_pos := Vector3(1.8, 0.0, RUN_START + 2.5)
		w_pos.y = _support_height(w_pos) + 0.22
		(barrow as Node3D).position = w_pos
		add_child(barrow)
		print("[PG] wheelbarrow placed at %s" % str(w_pos))


## Ramps are geometry only. Simulated snow needs a field, and a field is a horizontal
## plane, so giving a slope real snow means a rotated field instance: that is H4 work.
func _build_ramps() -> void:
	for i in range(2):
		var degrees := 10.0 + float(i) * 10.0
		var ramp := StaticBody3D.new()
		ramp.name = "Ramp%02d" % int(degrees)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.0, 0.2, 6.0)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.58, 0.62)
		mesh.material_override = mat
		ramp.add_child(mesh)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(4.0, 0.2, 6.0)
		shape.shape = box_shape
		ramp.add_child(shape)
		var radians := deg_to_rad(degrees)
		ramp.position = Vector3(-6.5 - float(i) * 3.0, 1.2, 4.0 + float(i) * 8.0)
		ramp.rotation = Vector3(radians, 0.0, 0.0)
		add_child(ramp)

## Initialises the HUD, which this scene declares as a node (`scenes/playground.tscn`).
##
## WHY THIS EXISTS: the reticle is drawn by the HUD, and this scene had none -- `_build_overlay`
## builds a debug ledger and nothing else. So the reticle could not appear here at all, and the
## owner reported exactly that: snow works, the reticle is missing.
##
## The HUD is DECLARED IN THE SCENE and not built here on purpose. `hud.gd` reaches for a dozen
## child nodes by path in its `@onready` block (title, progress bar, coin label, tool label...),
## so a bare `CanvasLayer` with that script attached fails on every one of them. The level
## declares the node in `main.tscn` and so does this scene now, which keeps the two in step: if
## the HUD grows a node, the scene file that is missing it says so at load.
func _init_hud() -> void:
	if player == null or snow_field == null:
		return
	var hud := get_node_or_null("HUD")
	if hud == null:
		push_warning("The Playground has no HUD node; the reticle will not draw.")
		return
	if hud.has_method("init_hud"):
		hud.init_hud(player, snow_field)
	else:
		push_warning("The Playground's HUD has no init_hud; the reticle will not draw.")


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PlaygroundOverlay"
	add_child(layer)

	_ledger_label = Label.new()
	_ledger_label.position = Vector2(24.0, 18.0)
	_ledger_label.add_theme_font_size_override("font_size", 15)
	_ledger_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_ledger_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_ledger_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_ledger_label)

	_hint_label = Label.new()
	_hint_label.position = Vector2(24.0, 210.0)
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.text = _shovel_hint
	layer.add_child(_hint_label)

	_hint_label = Label.new()
	_hint_label.position = Vector2(24.0, 190.0)
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.text = """PLAYGROUND   (development scene)
[B] spawn ball      [N] ball size 0.10 / 0.24 / 0.45 m
[V] free camera     [L] measure field mass now
[R] restart         [C] run the scripted battery
Lanes, left to right: virgin snow, packed, shovelled, deep
Ramps on the right are geometry only: a slope has no simulated snow yet"""
	layer.add_child(_hint_label)

func _build_free_camera() -> void:
	free_cam = Camera3D.new()
	free_cam.name = "FreeCamera"
	free_cam.fov = 70.0
	free_cam.current = false
	add_child(free_cam)
	free_cam.global_position = Vector3(0.0, 6.0, -24.0)
	free_cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

# Reactions to the simulation

func _on_op_volume_ready(_role: String, _owner: int, _kg: float) -> void:
	pass

var _surfaces_built: bool = false
## Operations waiting for their turn: the simulation's per-frame operation buffer is
## bounded, so they are fed in small batches instead of all at once.
var _pending_ops: Array[Callable] = []

## Manufactures the four lanes with the game's own operations, so a lane cannot come to
## mean something the real tools would not produce.
func _build_surfaces() -> void:
	var z := RUN_START + 1.0
	while z < RUN_END - 1.0:
		var at := z
		_pending_ops.append(func() -> void: snow_field.tamp(Vector3(LANE_X[1], 0.0, at), 0.5, 1.0))
		_pending_ops.append(func() -> void: snow_field.dump_snow(Vector3(LANE_X[3], 0.0, at), 70.0, 0.45))
		_pending_ops.append(func() -> void: snow_field.carve_shovel(Vector3(LANE_X[2], 0.0, at), Vector3(0.0, 0.0, 1.0), 0.9, 1.2, 0.4))
		z += 0.6
	print("[PG] %d operations queued to manufacture four lanes over %.0f m" % [
		_pending_ops.size(), RUN_END - RUN_START])

# Loop

## The simulation's operation buffer is small. Feeding it too fast silently drops
## operations, and the ones dropped are always the last of each batch: this was measured
## by watching carves disappear while the tamps and dumps around them survived.
const OPS_PER_FRAME: int = 2

func _process(delta: float) -> void:
	_t += delta
	if not _surfaces_built and bool(snow_field.get("sim_ready")):
		_surfaces_built = true
		_build_surfaces()
	_drain_ops()
	if not _pending_ops.is_empty():
		_empty_since = _t
	if _check_mode:
		while _step_index < _steps.size() and _t >= float(_steps[_step_index][0]):
			if (_step_index == 1 or _step_index == 4) and (_t - _empty_since < 1.2):
				break
			var fn: Callable = _steps[_step_index][1]
			fn.call()
			_step_index += 1
	_update_free_camera(delta)
	_update_ledger()

func _drain_ops() -> void:
	for i in range(mini(OPS_PER_FRAME, _pending_ops.size())):
		var op: Callable = _pending_ops.pop_front()
		op.call()

func _update_ledger() -> void:
	if _ledger_label == null or snow_field == null:
		return
	var total := float(snow_field.get("total_snow_kg"))
	var cleared := float(snow_field.get("kg_cleared_cumulative"))
	var balls := _ball_mass()
	_ledger_label.text = """PLAYGROUND LEDGER
field total      %8.1f kg
cleared          %8.1f kg
remaining        %8.1f kg
in balls         %8.1f kg
balance          %8.3f kg  (residual)
measured mass    %8.1f kg  [L to refresh]
measured drift   %8.3f %%""" % [
		total, cleared, total - cleared, balls, (cleared + (total - cleared)) - total,
		_measured_after, absf(_measured_after - _measured_before) / maxf(_measured_before, 1.0) * 100.0]

func _update_free_camera(delta: float) -> void:
	if not free_cam_on:
		return
	var speed := 14.0
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): dir.z -= 1.0
	if Input.is_action_pressed("move_backward"): dir.z += 1.0
	if Input.is_action_pressed("move_left"): dir.x -= 1.0
	if Input.is_action_pressed("move_right"): dir.x += 1.0
	if Input.is_action_pressed("jump"): dir.y += 1.0
	if Input.is_action_pressed("sprint"): dir.y -= 1.0
	free_cam.global_position += (free_cam.global_transform.basis * dir).normalized() * speed * delta

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_B:
			_spawn_ball()
		KEY_N:
			ball_radius_index = (ball_radius_index + 1) % BALL_RADII.size()
			print("[PG] ball size %.2f m" % BALL_RADII[ball_radius_index])
		KEY_V:
			_toggle_free_camera()
		KEY_L:
			_measured_after = _measure_field_mass()
			print("[PG] measured field mass: %.1f kg (drift %.3f %% from %.1f kg)" % [
				_measured_after, absf(_measured_after - _measured_before) / maxf(_measured_before, 1.0) * 100.0,
				_measured_before])
		KEY_C:
			_start_check()
		KEY_R:
			get_tree().reload_current_scene()

func _toggle_free_camera() -> void:
	free_cam_on = not free_cam_on
	free_cam.current = free_cam_on
	if player:
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.current = not free_cam_on
		player.set_process_unhandled_input(not free_cam_on)
		print("[PG] free camera %s" % ("on" if free_cam_on else "off"))

func _spawn_ball() -> void:
	if props == null:
		return
	var cam := free_cam if free_cam_on else (player.get_node_or_null("Camera3D") as Camera3D)
	if cam == null:
		return
	var from := cam.global_position - cam.global_transform.basis.z * 2.0
	_spawned_ball = props.spawn_snowball(from, BALL_RADII[ball_radius_index])
	if _spawned_ball != null:
		var ball := _spawned_ball as RigidBody3D
		if ball:
			ball.linear_velocity = -cam.global_transform.basis.z * 6.0
		print("[PG] ball r=%.2f m at %s" % [BALL_RADII[ball_radius_index], str(from)])

# Measurement

func _support_height(pos: Vector3) -> float:
	if snow_field and snow_field.has_method("get_support_snow_height"):
		return maxf(snow_field.get_support_snow_height(pos, 0.35), 0.0)
	return 0.32

## Integrates the snow actually present in the field. This is the honest number: the
## cleared-pixel counter the HUD shows is derived from the same total it is compared
## against, so on its own it can only ever agree with itself.
func _measure_field_mass() -> float:
	if snow_field == null or not snow_field.has_method("get_height_at"):
		return 0.0
	var width := float(snow_field.get("field_width"))
	var length := float(snow_field.get("field_length"))
	var density := float(snow_field.get("snow_density"))
	var step := 0.25
	# Mass = height x area x density. The snow depth is already in the height, so
	# multiplying by it again would report a third of the real figure.
	var cell := step * step * density
	var mass := 0.0
	var z := -length * 0.5
	while z <= length * 0.5:
		var x := -width * 0.5
		while x <= width * 0.5:
			var h: float = snow_field.get_height_at(Vector3(x, 0.0, z))
			if h > 0.0:
				mass += h * cell
			x += step
		z += step
	return mass

func _ball_mass() -> float:
	if props == null:
		return 0.0
	var total := 0.0
	for child in props.get_children():
		if child is SnowBall and not child.is_carried:
			total += child.packed_mass()
	return total

func surface_of(pos: Vector3) -> String:
	if snow_field == null:
		return "unknown"
	var h := float(snow_field.get("snow_depth"))
	if snow_field.has_method("get_support_snow_height"):
		h = float(snow_field.get_support_snow_height(pos, 0.35))
	if h < 0.03:
		return "cleared"
	var cohesion := 1.0
	if snow_field.has_method("get_cohesion_at"):
		cohesion = float(snow_field.get_cohesion_at(pos))
	if cohesion >= 0.45:
		return "packed"
	if cohesion >= 0.35:
		return "snow"
	return "powder"

# Battery

func _check(label: String, ok: bool) -> void:
	print("[PG] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_checks_ok += 1
	else:
		_checks_fail += 1

## A scripted run: measure, disturb the field with every operation the game has, then
## measure again. Guards against a system that quietly creates or destroys snow.
func _start_check() -> void:
	_t = 0.0
	_step_index = 0
	_checks_ok = 0
	_checks_fail = 0
	_steps = [
		[1.5, _c_geometry],
		[3.2, _c_surfaces],
		[3.7, _c_measure_before],
		[4.2, _c_disturb],
		[7.5, _c_measure_after],
		[8.0, _c_ball],
		[8.5, _c_dummy],
		[9.0, _c_free_cam],
		[9.5, _c_report],
	]
	print("[PG] ==== PLAYGROUND CHECK ====")

func _c_geometry() -> void:
	var w := float(snow_field.get("field_width"))
	var l := float(snow_field.get("field_length"))
	print("[PG] field %.1f x %.1f m, grid 512 squared, %.1f texels/m along the runway" % [
		w, l, 512.0 / l])
	_check("the runway is long enough for a hop chain", l >= 30.0)
	_check("the field is wide enough for four lanes", w >= 8.0)

## A lane is not uniform: a shovel leaves a trench and pushes the snow into a berm, so a
## single probe can land on either. Sampling along the lane is what actually describes it.
func _lane_profile(x: float) -> Dictionary:
	var counts := {"cleared": 0, "packed": 0, "snow": 0, "powder": 0}
	var samples := 0
	var lowest := 99.0
	var highest := -99.0
	var z := RUN_START + 4.0
	while z < RUN_END - 4.0:
		var pos := Vector3(x, 0.0, z)
		counts[surface_of(pos)] += 1
		var h := _support_height(pos)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
		samples += 1
		z += 0.5
	return {"samples": samples, "counts": counts, "low": lowest, "high": highest}

func _c_surfaces() -> void:
	var profiles: Array[Dictionary] = []
	for i in range(LANE_X.size()):
		profiles.append(_lane_profile(LANE_X[i]))
	for i in range(profiles.size()):
		var p := profiles[i]
		print("[PG] lane %-9s depth %.3f to %.3f m  %s" % [
			LANE_NAMES[i], p["low"], p["high"], str(p["counts"])])
	var virgin: Dictionary = profiles[0]["counts"]
	var packed: Dictionary = profiles[1]["counts"]
	var shovelled: Dictionary = profiles[2]["counts"]
	_check("the untouched lane is almost all powder", virgin["powder"] > profiles[0]["samples"] * 0.6)
	_check("the tamped lane is almost all packed", packed["packed"] > profiles[1]["samples"] * 0.6)
	# A shovelled lane is a trench and a berm, not a flat cleared strip: the blade shaves
	# thin sheets and pushes what it takes into a pile ahead of itself. A fully cleared
	# strip needs the blower or the harvest path, which belongs with H4's surface work.
	_check("the shovelled lane is thinner than the virgin one somewhere",
		float(profiles[2]["low"]) < float(profiles[0]["low"]) - 0.03)
	_check("the shovel pushed snow into a berm", float(profiles[2]["high"]) > float(profiles[0]["high"]) + 0.05)
	_check("the dumped lane is deeper than the untouched one", float(profiles[3]["high"]) > float(profiles[0]["high"]) + 0.2)

func _c_measure_before() -> void:
	_measured_before = _measure_field_mass()
	print("[PG] field mass before: %.1f kg" % _measured_before)

## Every mass-moving operation the game has, plus a ball thrown into the field.
##
## `dump_snow` is how the shovel lays down a load it harvested earlier, so calling it
## directly creates snow from nothing. That injected mass is tracked here and subtracted
## again in the check, which is the only way the balance means anything.
func _c_disturb() -> void:
	for i in range(12):
		var z := RUN_START + 4.0 + float(i) * 2.5
		_pending_ops.append(func() -> void: snow_field.dump_snow(Vector3(LANE_X[3], 0.0, z), 120.0, 0.5))
		_free_injected += 120.0
		_pending_ops.append(func() -> void: snow_field.carve_shovel(Vector3(LANE_X[2], 0.0, z), Vector3(0.0, 0.0, 1.0), 0.9, 1.2, 0.4))
		_pending_ops.append(func() -> void: snow_field.tamp(Vector3(LANE_X[1], 0.0, z), 0.5, 1.0))
	_spawn_ball()
	print("[PG] disturbing the field: 12 dumps (%.0f kg injected), 12 carves, 12 tamps" % _free_injected)

func _c_measure_after() -> void:
	_measured_after = _measure_field_mass()
	var drift := absf((_measured_after - _free_injected) - _measured_before) / maxf(_measured_before, 1.0) * 100.0
	# Carving and tamping move snow around; they must not create or destroy it. The
	# operations are quantised to texels, so the bar is the simulation's own tolerance
	# rather than exact arithmetic.
	print("[PG] field mass after: %.1f kg, minus %.0f kg injected = %.1f kg (drift %.3f %%)" % [
		_measured_after, _free_injected, _measured_after - _free_injected, drift])
	_check("moving snow around does not create or destroy it (<0.5%)", drift < 0.5)

func _c_ball() -> void:
	_check("the ball spawner produces a ball", _spawned_ball != null and is_instance_valid(_spawned_ball))

func _c_dummy() -> void:
	var mine := 0
	for child in get_children():
		if child.name.begins_with("TrainingDummy"):
			mine += 1
	print("[PG] dummies in the scene: %d" % mine)
	_check("the Playground has dummies to throw at", mine >= 3)

func _c_free_cam() -> void:
	_toggle_free_camera()
	var on := free_cam_on and free_cam.current
	_toggle_free_camera()
	_check("the free camera takes over and hands back", on and not free_cam_on)

func _c_report() -> void:
	print("[PG] RESULT: %d OK / %d FAIL" % [_checks_ok, _checks_fail])
	print("[PG] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
