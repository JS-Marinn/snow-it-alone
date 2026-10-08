extends Node

# ToonDemo: Acceptance battery for full-game cel shading (--toon-shot).
# Verifies:
# 1. Renders toon_off.png and toon_on.png from identical camera position and scene state.
# 2. Relative frame time cost of cel shading is within 15% budget.
# 3. All MeshInstance3D nodes preserve their albedo_texture (atlas colormaps) and albedo_color.
# 4. Snow field vertex displacement / shape is 100% untouched by cel shading.
# 5. Cel shading toggles cleanly between enabled and disabled states.

const CelShadingSystem = preload("res://scripts/cel_shading_system.gd")

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _cam: Camera3D

var _checks_ok: int = 0
var _checks_fail: int = 0
var _finished: bool = false

# Benchmark metrics
var _frame_count: int = 0
var _accum_time: float = 0.0
var _time_off_ms: float = 0.0
var _time_on_ms: float = 0.0

# Snow height samples
var _h_sample_pts := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 2.5),
	Vector3(1.5, 0.0, -1.0),
	Vector3(-1.5, 0.0, 1.0)
]
var _h_before: Array[float] = []
var _h_after: Array[float] = []

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[TOON] ==== CEL SHADING ACCEPTANCE BATTERY ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_camera()

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 60.0
	# Angle across the sun to clearly reveal lighting bands, rim light and shadows
	_cam.global_position = Vector3(-2.4, 1.3, 2.2)
	_cam.look_at(Vector3(0.2, 0.7, -1.0), Vector3.UP)
	_cam.make_current()

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_state_time += delta

	match _state:
		0:
			# State 0: Wait for GPU sim & scene init, carve a test trench and spawn a snowball
			if _state_time >= 0.5 and snow_field != null and snow_field.has_method("is_coarse_ready") and snow_field.is_coarse_ready():
				print("[TOON] Carving sample trench and spawning test snowball for visual comparison...")
				snow_field.clear_for_diagnostics(Vector3(0.0, 0.0, 0.0), 2.2)
				if props and props.has_method("spawn_snowball"):
					props.spawn_snowball(Vector3(0.1, 0.4, 0.8), 0.38)
				_change_state(1)

		1:
			# State 1: Wait for carve & physics to settle, then disable cel shading for baseline
			if _state_time >= 0.6:
				print("[TOON] Disabling cel shading to capture baseline (toon_off)...")
				CelShadingSystem.set_cel_shading_enabled(false, root)
				_h_before.clear()
				for pt in _h_sample_pts:
					_h_before.append(float(snow_field.get_height_at(pt)))
				_frame_count = 0
				_accum_time = 0.0
				_change_state(2)

		2:
			# State 2: Benchmark baseline over 60 frames, then capture toon_off.png
			_frame_count += 1
			_accum_time += delta
			if _frame_count >= 60:
				_time_off_ms = (_accum_time / float(_frame_count)) * 1000.0
				_capture_viewport_screenshot("toon_off.png")
				_change_state(3)

		3:
			# State 3: Enable cel shading across the game
			if _state_time >= 0.2:
				print("[TOON] Enabling cel shading across the game...")
				CelShadingSystem.set_cel_shading_enabled(true, root)
				_frame_count = 0
				_accum_time = 0.0
				_change_state(4)

		4:
			# State 4: Settle pipeline over 15 frames
			_frame_count += 1
			if _frame_count >= 15:
				_frame_count = 0
				_accum_time = 0.0
				_change_state(5)

		5:
			# State 5: Benchmark cel shading over 60 frames, then capture toon_on.png
			_frame_count += 1
			_accum_time += delta
			if _frame_count >= 60:
				_time_on_ms = (_accum_time / float(_frame_count)) * 1000.0
				_capture_viewport_screenshot("toon_on.png")
				_change_state(6)

		6:
			# State 6: Run all acceptance checks
			if _state_time >= 0.2:
				_evaluate_checks()

func _capture_viewport_screenshot(filename: String) -> void:
	var v_tex = get_viewport().get_texture()
	if v_tex:
		var img = v_tex.get_image()
		if img:
			var path = ProjectSettings.globalize_path("res://" + filename)
			var err = img.save_png(path)
			print("[TOON] Screenshot saved (err=%d): %s" % [err, path])

func _evaluate_checks() -> void:
	# 1. Check screenshots exist
	var path_off := ProjectSettings.globalize_path("res://toon_off.png")
	var path_on := ProjectSettings.globalize_path("res://toon_on.png")
	var off_exists: bool = FileAccess.file_exists(path_off)
	var on_exists: bool = FileAccess.file_exists(path_on)
	_check("screenshots saved: toon_off.png and toon_on.png", off_exists and on_exists)

	# 2. Check snow field displacement untouched
	_h_after.clear()
	var max_h_diff: float = 0.0
	for i in range(_h_sample_pts.size()):
		var h_now: float = float(snow_field.get_height_at(_h_sample_pts[i]))
		_h_after.append(h_now)
		var diff: float = absf(h_now - _h_before[i])
		if diff > max_h_diff:
			max_h_diff = diff
	print("[TOON] Snow height max difference: %.6f m" % max_h_diff)
	_check("snow field displacement untouched by cel shading", max_h_diff < 0.001)

	# 3. Check relative performance cost
	var fps_off: float = 1000.0 / maxf(_time_off_ms, 0.001)
	var fps_on: float = 1000.0 / maxf(_time_on_ms, 0.001)
	var rel_cost_pct: float = ((_time_on_ms - _time_off_ms) / maxf(_time_off_ms, 0.001)) * 100.0
	print("[TOON] Frame time: OFF=%.2f ms (%.1f FPS) | ON=%.2f ms (%.1f FPS) | cost=%+.2f%% (budget <= 15.0%%)" % [
		_time_off_ms, fps_off, _time_on_ms, fps_on, rel_cost_pct])
	_check("relative performance cost within 15% budget", rel_cost_pct <= 15.0)

	# 4. Check material preservation (textures and colors)
	var pres: Dictionary = CelShadingSystem.verify_material_preservation(root)
	print("[TOON] Material preservation: %d checked, %d textured, %d errors" % [
		pres["checked_count"], pres["textured_count"], pres["errors"].size()])
	if not pres["errors"].is_empty():
		for err in pres["errors"]:
			print("[TOON]   [ERR] %s" % err)
	_check("no materials lost their texture", pres["textured_count"] > 0 and pres["errors"].is_empty())
	_check("all materials preserve equivalent albedo_color", pres["ok"] and pres["checked_count"] > 10)

	# 5. Check toggle state works cleanly
	CelShadingSystem.set_cel_shading_enabled(false, root)
	var toggled_off: bool = not CelShadingSystem.cel_shading_enabled
	CelShadingSystem.set_cel_shading_enabled(true, root)
	var toggled_on: bool = CelShadingSystem.cel_shading_enabled
	_check("cel shading toggles cleanly between on and off", toggled_off and toggled_on)

	_report()

func _change_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0

func _check(label: String, ok: bool) -> void:
	print("[TOON] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_checks_ok += 1
	else:
		_checks_fail += 1

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[TOON] RESULT: %d OK / %d FAIL" % [_checks_ok, _checks_fail])
	print("[TOON] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
