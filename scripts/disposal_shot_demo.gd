extends Node

# DisposalShotDemo: Verification screenshot showing the disposal machine and the HUD counter.
# Runs in main.tscn with --disposal-shot.

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _captured: bool = false

func setup(p_root: Node3D, p_field: Node3D, p_player: CharacterBody3D, p_props: Node3D) -> void:
	root = p_root
	snow_field = p_field
	player = p_player
	props = p_props

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= 0.5 and not _captured:
		_captured = true
		_run_shot()

func _run_shot() -> void:
	var machine = root.get_node_or_null("DisposalMachine")
	if machine != null and machine.has_method("accept"):
		# Send a 14.8 kg delivery into the machine so the HUD counter shows real snow sent
		machine.accept(14.8, machine.global_position)
		print("[DISP-SHOT] Delivered 14.8 kg to disposal machine")

	# Position player in the snow yard to view the disposal machine in front of the cottage
	if player != null:
		player.global_position = Vector3(1.8, 0.45, -2.5)
		player.rotation = Vector3.ZERO
		if player.get("camera") != null:
			var target = Vector3(0.0, 0.95, -7.6)
			player.camera.look_at(target, Vector3.UP)

	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw

	var v_tex := get_viewport().get_texture()
	if v_tex != null:
		var img := v_tex.get_image()
		if img != null:
			var out_path := ProjectSettings.globalize_path("res://disposal_machine_hud.png")
			var err := img.save_png(out_path)
			print("[DISP-SHOT] Screenshot saved (err=%d) to %s (size=%s)" % [err, out_path, str(img.get_size())])

			# Also save directly to artifact directory if accessible
			var artifact_path := "C:/Users/MrSeb/.gemini/antigravity/brain/f7cb66a3-0042-4510-8835-ef2f6f222b15/disposal_machine_hud.png"
			img.save_png(artifact_path)

	get_tree().quit()
