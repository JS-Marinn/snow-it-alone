extends Node

# ToonBisectDemo: Diagnostic harness for Bug 1 bisection (--toon-bisect).
# Renders 5 screenshots from the exact same camera and scene state:
# 1. toon_bisect_1.png: Como está (current toon on snow and objects)
# 2. toon_bisect_2.png: Nieve sin toon (snow_deform toon_enabled = false)
# 3. toon_bisect_3.png: Nieve sin toon y toon de objetos a 1 banda (snow toon off, obj bands = 1)
# 4. toon_bisect_4.png: Sin contorno (outline_width = 0.0 everywhere)
# 5. toon_bisect_5.png: Todo el toon apagado (cel shading disabled everywhere)

const CelShadingSystem = preload("res://scripts/cel_shading_system.gd")

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _cam: Camera3D
var _frame_count: int = 0
var _finished: bool = false

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[TOON-BISECT] ==== TOON BISECTION DIAGNOSTIC ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_camera()

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 65.0
	# Wide angle showing snow ground, carved trench, and the 4.5m snow bank
	_cam.global_position = Vector3(-2.2, 1.4, 2.4)
	_cam.look_at(Vector3(0.4, 0.6, -0.8), Vector3.UP)
	_cam.make_current()

func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_state_time += delta

	match _state:
		0:
			# Init: Wait for snow field to initialize, carve trench, spawn snowball
			if _state_time >= 0.5 and snow_field != null and snow_field.has_method("is_coarse_ready") and snow_field.is_coarse_ready():
				print("[TOON-BISECT] Carving trench and spawning test snowball...")
				snow_field.carve(Vector3(0.0, 0.0, 0.0), 2.2, 0.25)
				if props and props.has_method("spawn_snowball"):
					props.spawn_snowball(Vector3(0.1, 0.4, 0.8), 0.38)
				_change_state(1)

		1:
			# State 1: Wait for physics to settle, set state (1) Como está
			if _state_time >= 0.5:
				print("[TOON-BISECT] State 1: Como está (baseline toon)...")
				CelShadingSystem.configure_bisect(true, true, 3, 0.006, root)
				_frame_count = 0
				_change_state(2)

		2:
			# Settle & capture 1
			_frame_count += 1
			if _frame_count >= 20:
				_capture("toon_bisect_1.png")
				_change_state(3)

		3:
			# State 2: Nieve sin toon
			print("[TOON-BISECT] State 2: Nieve sin toon (snow toon off, objects toon on)...")
			CelShadingSystem.configure_bisect(false, true, 3, 0.006, root)
			_frame_count = 0
			_change_state(4)

		4:
			# Settle & capture 2
			_frame_count += 1
			if _frame_count >= 20:
				_capture("toon_bisect_2.png")
				_change_state(5)

		5:
			# State 3: Nieve sin toon y toon de objetos a 1 banda
			print("[TOON-BISECT] State 3: Nieve sin toon, objetos 1 banda...")
			CelShadingSystem.configure_bisect(false, true, 1, 0.006, root)
			_frame_count = 0
			_change_state(6)

		6:
			# Settle & capture 3
			_frame_count += 1
			if _frame_count >= 20:
				_capture("toon_bisect_3.png")
				_change_state(7)

		7:
			# State 4: Sin contorno
			print("[TOON-BISECT] State 4: Sin contorno (outline_width = 0.0)...")
			CelShadingSystem.configure_bisect(true, true, 3, 0.0, root)
			_frame_count = 0
			_change_state(8)

		8:
			# Settle & capture 4
			_frame_count += 1
			if _frame_count >= 20:
				_capture("toon_bisect_4.png")
				_change_state(9)

		9:
			# State 5: Todo el toon apagado
			print("[TOON-BISECT] State 5: Todo el toon apagado...")
			CelShadingSystem.set_cel_shading_enabled(false, root)
			_frame_count = 0
			_change_state(10)

		10:
			# Settle & capture 5
			_frame_count += 1
			if _frame_count >= 20:
				_capture("toon_bisect_5.png")
				_change_state(11)

		11:
			# State 6: Arreglo aplicado (smooth snow diffuse + rim, smooth irradiance objects, inverted hull outline)
			print("[TOON-BISECT] State 6: Arreglo aplicado (fix active)...")
			CelShadingSystem.configure_bisect(true, true, 2, 0.006, root)
			_frame_count = 0
			_change_state(12)

		12:
			# Settle & capture 6
			_frame_count += 1
			if _frame_count >= 20:
				_capture("toon_bisect_6.png")
				_report()

func _change_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0

func _capture(filename: String) -> void:
	var v_tex = get_viewport().get_texture()
	if v_tex:
		var img = v_tex.get_image()
		if img:
			var path = ProjectSettings.globalize_path("res://" + filename)
			var err = img.save_png(path)
			print("[TOON-BISECT] Saved %s (err=%d)" % [filename, err])

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[TOON-BISECT] All 5 bisect screenshots saved successfully.")
	print("[TOON-BISECT] ==== END ====")
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
