extends Node

# PackProbeDemo: Diagnostic tool to measure ray hit, aim point, snow height,
# available snow kg estimate, threshold and packing decision across a grid
# of points around the player, especially sunken/shallow snow areas.

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _step: int = 0
var _step_time: float = 0.0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[PACK_PROBE] ==== PACK PROBE DIAGNOSTIC ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	_t += delta
	_step_time += delta

	match _step:
		0:
			# Wait for simulation
			if _step_time >= 0.5 and snow_field != null and snow_field.has_method("is_coarse_ready") and snow_field.is_coarse_ready():
				print("[PACK_PROBE] Preparing terrain zones...")
				# Zone A: Bare ground at (0, 0, 2.0)
				snow_field.clear_for_diagnostics(Vector3(0.0, 0.0, 2.0), 1.2)
				# Zone B: Shallow snow at (-1.5, 0.0, 1.5): dump 1.8 kg (leaves ~3.5 cm)
				snow_field.clear_for_diagnostics(Vector3(-1.5, 0.0, 1.5), 1.0)
				snow_field.dump_snow(Vector3(-1.5, 0.0, 1.5), 1.8, 0.5)
				# Zone C: Sunken shallow snow at (1.5, 0.0, 1.5): dump 1.2 kg (leaves ~2.5 cm)
				snow_field.clear_for_diagnostics(Vector3(1.5, 0.0, 1.5), 1.0)
				snow_field.dump_snow(Vector3(1.5, 0.0, 1.5), 1.2, 0.5)
				_step = 1
				_step_time = 0.0
		1:
			# Wait for carves and dumps to settle in coarse mirror
			if _step_time >= 0.8:
				_run_grid_probe()
				_step = 2

func _run_grid_probe() -> void:
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.rotation.y = 0.0
	player.equip_tool(player.ToolType.HANDS)

	# Grid of test points relative to player
	var test_targets: Array[Dictionary] = [
		{"name": "Deep snow ahead", "pos": Vector3(0.0, 0.1, -1.8)},
		{"name": "Bare ground ahead", "pos": Vector3(0.0, 0.0, 2.0)},
		{"name": "Shallow snow (left 3.5cm)", "pos": Vector3(-1.5, 0.0, 1.5)},
		{"name": "Shallow snow (right 2.5cm)", "pos": Vector3(1.5, 0.0, 1.5)},
		{"name": "Close ground at feet (0.5m)", "pos": Vector3(0.0, 0.0, -0.5)},
		{"name": "Max reach boundary (2.3m)", "pos": Vector3(0.0, 0.1, -2.3)},
		{"name": "Beyond max reach (3.0m)", "pos": Vector3(0.0, 0.1, -3.0)},
		{"name": "Looking at sky", "pos": Vector3(0.0, 5.0, 2.0)},
	]

	print("\n[PACK_PROBE] Running probe on %d target scenarios:" % test_targets.size())
	for item in test_targets:
		var target: Vector3 = item["pos"]
		var label: String = item["name"]
		player.camera.look_at(target, Vector3.UP)
		player._update_reticle_aim()

		var hit: bool = player.reticle_has_hit
		var aim: Vector3 = player.reticle_aim_pt
		var h: float = snow_field.get_height_at(aim) if (hit and aim != Vector3.INF) else 0.0
		var avail: float = player._estimate_available_snow_kg(aim) if (hit and aim != Vector3.INF) else 0.0
		var thresh: float = player.pack_min_kg
		var state: int = int(player.get_reticle_state())
		var state_str := "OFF"
		if state == player.ReticleState.CAN_PACK:
			state_str = "CAN_PACK"
		elif state == player.ReticleState.CAN_CARVE:
			state_str = "CAN_CARVE"

		print("[PACK_PROBE] Target '%-24s' (%s): hit=%s, aim=%s, h=%.4f m, avail_kg=%.4f, thresh=%.4f -> decision=%s" % [
			label, str(target), str(hit), str(aim), h, avail, thresh, state_str
		])

	print("\n[PACK_PROBE] ==== PROBE COMPLETE ====\n")
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
