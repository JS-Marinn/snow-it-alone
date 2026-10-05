extends Node

# CarveQualityDemo: visual quality check of the terrain left by shovelling (--carve-quality).

var root: Node3D
var snow_field: Node3D
var player: Node3D
var props: Node3D

var _t: float = 0.0
var _steps: Array = []
var _i: int = 0
var _cam: Camera3D
var _frames: int = 0
var _accum: float = 0.0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[CARVE] ==== TERRAIN QUALITY DIAGNOSTIC ====")
	# Move the player aside to clear the diagnostic camera framing
	if ply:
		ply.global_position = Vector3(0.0, 0.32, 9.5)
	_setup_camera()
	_steps = [
		[0.8, _s_report_initial],
		[1.0, _s_trench],
		[1.6, _s_trench_report],
		[1.9, _s_crater],
		[2.6, _s_crater_report],
		[3.0, _s_tamp],
		[3.6, _s_tamp_report],
		[4.0, _s_first_person],
		[4.6, _s_no_shovel],
		[5.2, _s_no_shadow],
		[5.8, _s_quit],
	]

## Find out whether the bright "spike" comes from the shovel model or its shadow.
func _s_no_shovel() -> void:
	if player == null:
		return
	var shovel = player.get_node_or_null("Camera3D/HandRoot/Shovel")
	if shovel:
		shovel.visible = false
	print("[CARVE] shovel hidden: the model is isolated as the source of the artifact")
	_shot("no_shovel")

func _s_no_shadow() -> void:
	# Show the shovel again: this tells its geometry apart (the "spike" would
	# stay) from its shadow cast on the snow (it goes away).
	if player:
		var shovel = player.get_node_or_null("Camera3D/HandRoot/Shovel")
		if shovel:
			shovel.visible = true
	var light := root.get_node_or_null("DirectionalLight3D") if root else null
	if light:
		light.shadow_enabled = false
	print("[CARVE] shovel visible again, directional shadows disabled")
	_shot("no_shadow")

## First-person view of the crater: reproduces the player framing to check that
## the shovel model causes no artifacts on screen.
func _s_first_person() -> void:
	if player == null:
		return
	if _cam:
		_cam.clear_current()
	player.global_position = Vector3(0.2, 0.30, 3.5)
	player.rotation.y = 0.0
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.rotation.x = deg_to_rad(-40.0)
		cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[CARVE] first-person view over the cleared terrain")
	_shot("first_person")

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.position = Vector3(0.9, 1.55, 4.35)
	_cam.look_at(Vector3(0.0, 0.12, 2.4), Vector3.UP)
	_cam.fov = 70.0
	_cam.make_current()

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	_accum += delta
	while _i < _steps.size() and _t >= float(_steps[_i][0]):
		var fn: Callable = _steps[_i][1]
		fn.call()
		_i += 1

# Steps
func _s_report_initial() -> void:
	print("[CARVE] initial height at the trench centre: %.3f m" % _height(Vector3(0.0, 0.0, 2.4)))

## Shovel trench: several continuous straight passes, as when walking.
func _s_trench() -> void:
	var dir := Vector3(0.0, 0.0, -1.0)
	for i in range(14):
		var z := 3.2 - float(i) * 0.09
		snow_field.carve_shovel(Vector3(0.0, 0.0, z), dir, 0.76, 0.30)
	print("[CARVE] shovel trench cut (14 passes)")

func _s_trench_report() -> void:
	_shot("trench")
	_profile("shovel trench", Vector3(0.0, 0.0, 2.4), Vector3(1.0, 0.0, 0.0), -0.55, 0.55, 0.02)

## Turbine/salt crater: radial clearing with a bevel.
func _s_crater() -> void:
	snow_field.carve(Vector3(1.7, 0.0, 2.0), 1.05, 0.40, Vector3.ZERO)
	print("[CARVE] radial crater cut (turbine)")

func _s_crater_report() -> void:
	_shot("crater")
	_profile("radial crater", Vector3(1.7, 0.0, 2.0), Vector3(1.0, 0.0, 0.0), -1.5, 1.5, 0.05)

func _s_tamp() -> void:
	snow_field.tamp(Vector3(0.0, 0.0, 2.0), 0.45, 1.0)
	print("[CARVE] tamping applied along the trench edge")

func _s_tamp_report() -> void:
	_shot("tamp")
	_profile("after tamping", Vector3(0.0, 0.0, 2.4), Vector3(1.0, 0.0, 0.0), -0.55, 0.55, 0.02)

func _s_quit() -> void:
	print("[CARVE] field peak height: %.3f m (%.4f normalized)" % [
		snow_field.get_peak_snow_height(Vector3.ZERO), _raw_peak()])
	print("[CARVE] mean performance: %.1f FPS (%d frames, mesh %dx%d)" % [
		float(_frames) / maxf(_accum, 0.001), _frames,
		snow_field.mesh_subdiv_x, snow_field.mesh_subdiv_z])
	print("[CARVE] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)

# Utilities
func _height(pos: Vector3) -> float:
	if snow_field and snow_field.has_method("get_height_at"):
		return maxf(snow_field.get_height_at(pos), 0.0)
	return 0.0

## True mirror peak (max height per block), in normalized units.
func _raw_peak() -> float:
	var coarse: PackedFloat32Array = snow_field.get("_coarse")
	if coarse.is_empty():
		return 0.0
	var peak := 0.0
	for i in range(64 * 64):
		peak = maxf(peak, coarse[i * 4 + 3])
	return peak

## Dump the height profile along an axis, to measure the wall slope and detect
## texel-to-texel discontinuities.
func _profile(label: String, origin: Vector3, axis: Vector3, from: float, to: float, step: float) -> void:
	var line := ""
	var prev := -1.0
	var max_jump := 0.0
	var x := from
	while x <= to:
		var h := _height(origin + axis * x)
		line += "%.3f " % h
		if prev >= 0.0:
			max_jump = maxf(max_jump, absf(h - prev))
		prev = h
		x += step
	print("[CARVE] profile %s (step %.2f m, max jump %.3f m):" % [label, step, max_jump])
	print("[CARVE]   " + line)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var v_tex := get_viewport().get_texture()
	if v_tex == null:
		return
	var img := v_tex.get_image()
	if img == null:
		return
	var err := img.save_png("res://carve_%s.png" % label)
	print("[CARVE] screenshot carve_%s.png (err=%d)" % [label, err])
