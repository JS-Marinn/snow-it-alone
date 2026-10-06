extends Node

# PgReticleProbe: measures whether the reticle is actually drawn IN THE PLAYGROUND.
#
# The owner reported "snow works here but the reticle does not appear", and the Playground had no
# HUD at all, so there was nothing to appear. This proves the fix in pixels rather than in code:
# it aims at the snow, writes the viewport to a PNG, and reads the PNG back to compare the centre
# of the screen against the snow around it.
#
#   --pg-reticle-probe
#
# Not a battery: it asserts nothing and only prints. The battery for this scene would live with
# the others; this exists to answer one question with a number.

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0
var _cam: Camera3D
## Set once the capture has been STARTED, so the awaited coroutine runs once and not once per
## physics frame. Without it this probe reported its verdict twenty times over twenty PNGs.
var _shot_done: bool = false


func setup(scene_root: Node3D, field: Node3D, ply: Node3D, _props: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	print("[PGRET] ==== PLAYGROUND RETICLE PROBE ====")
	_cache_camera()


## The Playground has a free camera of its own; this probe needs its own view of the player, so it
## makes one and switches back before the screenshot.
func _cache_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 65.0
	root.add_child(_cam)
	_cam.make_current()


func _physics_process(delta: float) -> void:
	_t += delta
	_state_time += delta
	if _cam != null and player != null:
		_cam.global_position = player.global_position + Vector3(2.6, 1.9, 2.6)
		_cam.look_at(player.global_position + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	match _state:
		0: _ph_wait()
		1: _ph_aim()
		2: _ph_shot()


func _ph_wait() -> void:
	if _state_time < 0.6:
		return
	if snow_field == null or not snow_field.has_method("is_coarse_ready") or not snow_field.is_coarse_ready():
		return
	if player == null:
		print("[PGRET] no player in the Playground; cannot test the reticle")
		_done()
		return
	# Does this scene actually have a HUD now?
	var hud := root.get_node_or_null("HUD")
	print("[PGRET] HUD node present: %s" % str(hud != null))
	if hud != null:
		var dot = hud.get("_reticle_dot")
		var ring = hud.get("_reticle_dot_ring")
		print("[PGRET] HUD built its reticle: dot=%s ring=%s" % [
			str(dot != null), str(ring != null)])
		if dot != null and ring != null:
			print("[PGRET] vis=%s rect=%s | ring vis=%s rect=%s" % [
				str(dot.visible), str(dot.get_global_rect()),
				str(ring.visible), str(ring.get_global_rect())])
	_change(1)


func _ph_aim() -> void:
	if _state_time < 0.4:
		return
	if player.camera == null:
		print("[PGRET] the player has no camera; cannot aim")
		_done()
		return
	# Look down at the snow just in front of the feet, which is the case that must read CAN_PACK.
	var feet := Vector3(player.global_position.x, 0.0, player.global_position.z + 0.7)
	player.camera.look_at(feet, Vector3.UP)
	player._update_reticle_aim()
	print("[PGRET] aim=%s reticle=%d" % [
		str(player.get_reticle_aim_point()), int(player.get_reticle_state())])
	_change(2)


func _ph_shot() -> void:
	if _shot_done:
		return
	if _state_time < 0.5:
		return
	# ONCE. `_shot()` contains an `await`, so calling it without one starts a NEW coroutine every
	# time this phase runs -- and this phase runs every physics frame. The probe reported its
	# verdict twenty times in a row and captured twenty PNGs, which is a measuring instrument
	# lying about how many measurements it took.
	_shot_done = true
	_shot()
	_done()


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[PGRET] the viewport has no texture")
		return
	var img := tex.get_image()
	if img == null:
		print("[PGRET] the viewport image could not be read")
		return
	var path := ProjectSettings.globalize_path("res://playground_reticle.png")
	var err := img.save_png(path)
	print("[PGRET] wrote %s (err=%d, size=%s)" % [path, err, str(img.get_size())])
	if err != 0:
		return
	var size := img.get_size()
	var c := Vector2i(int(size.x / 2.0), int(size.y / 2.0))
	# The dot: the darkest pixel within 2 px of the centre. The snow beside it: the brightest
	# sample 6 px out. The difference is what decides whether a person can see it.
	var dot := Color(1.0, 1.0, 1.0)
	var dot_luma := 2.0
	var dot_at := c
	for y in range(c.y - 2, c.y + 3):
		for x in range(c.x - 2, c.x + 3):
			var p := img.get_pixel(clampi(x, 0, size.x - 1), clampi(y, 0, size.y - 1))
			var l := (p.r + p.g + p.b) / 3.0
			if l < dot_luma:
				dot_luma = l
				dot = p
				dot_at = Vector2i(x, y)
	var snow := 0.0
	for a in range(12):
		var off := Vector2(6.0, 0.0).rotated(TAU * float(a) / 12.0)
		var p := img.get_pixel(clampi(c.x + int(off.x), 0, size.x - 1), clampi(c.y + int(off.y), 0, size.y - 1))
		snow = maxf(snow, (p.r + p.g + p.b) / 3.0)
	var redness := dot.r - (dot.g + dot.b) * 0.5
	print("[PGRET] PLAYGROUND: dot at (%d, %d) rgb %s luma %.3f | snow %.3f | contrast %.3f | redness %.3f | offset (%.1f, %.1f) px" % [
		dot_at.x, dot_at.y, str(dot), dot_luma, snow, snow - dot_luma, redness,
		float(dot_at.x - c.x), float(dot_at.y - c.y)])
	if snow - dot_luma < 0.10:
		print("[PGRET] VERDICT: the reticle is NOT visible in the Playground (contrast %.3f)" % (snow - dot_luma))
	else:
		print("[PGRET] VERDICT: the reticle IS visible in the Playground (contrast %.3f)" % (snow - dot_luma))


func _change(s: int) -> void:
	_state = s
	_state_time = 0.0


func _done() -> void:
	print("[PGRET] ==== PROBE COMPLETE ====")
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
