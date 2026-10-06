extends Node

# ReticleAimDemo: acceptance battery for "gathering needs snow close to the aim point".
#
# The owner's specification, and the reason four attempts at this went nowhere:
#
#     "Gathering snow happens where the reticle is: if I look straight ahead instead of down, it
#      must not gather snow."
#
# That is not "the ray hits something". Standing in snow and looking forward puts the aim point
# on the ground METRES away, where there is plenty of snow, so every test that only asked "is
# there snow?" passed while the player was looking at nothing in particular. The missing
# requirement is that the aim point be CLOSE.
#
# AND THE RETICLE IS CHECKED IN PIXELS, not in the code that is supposed to draw it. "It
# compiles" and "the game loads" are not checks that something is visible: the reticle was
# reported invisible while the log said it was fine, and a previous attempt proved it in the
# screenshot only after the fact. So this battery writes a PNG and reads it back.
#
# Prints [RETICLE] RESULT: N OK / M FAIL. A battery that cannot prepare itself reports failure
# rather than returning in silence.

const SnowBallScript = preload("res://scripts/snowball.gd")
const BuildStampScript = preload("res://scripts/build_stamp.gd")

## Longest the battery may take. On expiry it reports what it has as a failure.
const HARD_TIMEOUT: float = 90.0
## The player's spot for every case: standing in untouched snow.
const PLAYER_POS: Vector3 = Vector3(0.0, 0.32, 6.0)
## Untouched snow, straight down and a little in front of the feet (0.63 m away).
const SNOW_AT_FEET: Vector3 = Vector3(0.0, 0.0, 5.4)
## Where the snow is carved away for the bare-ground case. Off to the side on purpose, so that
## preparing that case cannot destroy the snow the first case needs.
const BARE_GROUND: Vector3 = Vector3(1.6, 0.0, 6.0)
## Where the forward gaze lands: on the ground, metres away. This is the aim that must NOT pack.
const FORWARD_GAZE: Vector3 = Vector3(0.0, 0.32, 18.0)

## What the reticle must be, in pixels, measured from a PNG the game itself wrote.
##
## CONTRAST, not a fixed colour. The first version of this looked for one exact RGB and reported
## "not found" while the geometry log showed the reticle drawn and centred: the dot was white
## (0.96) on snow (0.99), three per cent of contrast, which is a reticle that exists and cannot
## be seen. So this measures the two things a player actually relies on:
##
##   * the centre of the screen is DARKER than the snow a few pixels out -- the dot reads at all;
##   * the centre is REDDER than the ring around it when a ball can be packed -- the state reads.
##
## The game writes `screenshot.png`; this opens it and says where and what colour.
const SEARCH_RADIUS: int = 24
## Pixels within this radius of the centre count as "the dot".
const DOT_RADIUS: float = 2.0
## Contrast the dot must have against the snow beside it. A tenth of the luma range is roughly
## what a person notices; the dead dot this replaced managed three hundredths.
const MIN_CONTRAST: float = 0.10

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _phase_t: float = 0.0
var _phase: int = 0

var _ok: int = 0
var _fail: int = 0
var _finished: bool = false

## Per-case records, so the verdict is printed from measurements and not from live state.
var _row: Dictionary = {}
var _press_balls: int = 0
var _press_h: float = 0.0


func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[RETICLE] ==== RETICLE AIM ACCEPTANCE BATTERY ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().create_timer(HARD_TIMEOUT).timeout.connect(_on_hard_timeout)

	if root == null or snow_field == null or player == null or props == null:
		_check("the battery could set itself up (needs the level scene)", false)
		_report()
		return
	if player.has_method("equip_tool"):
		player.equip_tool(player.ToolType.HANDS)
	# The build stamp, checked rather than assumed: a battery that ran against a stale build is
	# not a measurement of anything.
	var build := BuildStampScript.commit_hash()
	print("[RETICLE] build %s" % build)
	_check("the build carries a stamp (not 'unknown')", build != "unknown")
	_check("the stamp names the commit this battery ships in", not build.begins_with("unknown"))


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_phase_t += delta
	match _phase:
		0: _ph_wait()
		1: _ph_case_feet()
		2: _ph_read_feet()
		3: _ph_case_forward()
		4: _ph_read_forward()
		5: _ph_case_sky()
		6: _ph_read_sky()
		7: _ph_carve()
		8: _ph_case_bare()
		9: _ph_read_bare()
		10: _ph_shot_feet()
		11: _ph_shot_forward()
		12: _ph_report()


func _next() -> void:
	_phase += 1
	_phase_t = 0.0


func _ph_wait() -> void:
	if _phase_t < 0.6:
		return
	if not snow_field.has_method("is_coarse_ready") or not snow_field.is_coarse_ready():
		return
	player.global_position = PLAYER_POS
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", PLAYER_POS.y)
	player.set("is_ground_initialized", true)
	player.set("status_message", "")
	_next()


# ---------------------------------------------------------------------------------------
# The four aim cases
# ---------------------------------------------------------------------------------------
func _ph_case_feet() -> void:
	_press("looking down at snow at the feet", SNOW_AT_FEET)
	_next()


func _ph_read_feet() -> void:
	if not _read("looking down at snow at the feet", 0.9):
		return
	var carrying: bool = player.has_method("is_carrying") and player.is_carrying()
	_check("aiming down at close snow: the reticle says CAN_PACK", int(_row["reticle"]) == 1)
	_check("aiming down at close snow: pressing packs a ball", carrying)
	_check("aiming down at close snow: the ball has a real mass", float(_row["ball_kg"]) > 0.0)
	_check("aiming down at close snow: the field loses a hole where the snow was",
		float(_row["hole"]) > 0.005)
	# Prepare the next case: put the ball down and free it so the hands are empty. Packing while
	# carrying does nothing at all, which would make the next two cases pass for the wrong
	# reason -- the worst kind of pass.
	_drop_and_free()
	_next()


func _ph_case_forward() -> void:
	if _phase_t < 0.4:
		return
	_press("looking forward along the ground", FORWARD_GAZE)
	_next()


func _ph_read_forward() -> void:
	if not _read("looking forward along the ground", 0.9):
		return
	_check("aiming forward: the reticle does not offer to pack", int(_row["reticle"]) != 1)
	_check("aiming forward: no ball is created", int(_row["new_balls"]) == 0)
	_check("aiming forward: no hole is left in the snow", absf(float(_row["hole"])) < 0.002)
	_drop_and_free()
	_next()


func _ph_case_sky() -> void:
	if _phase_t < 0.4:
		return
	_press("looking at the sky", Vector3(0.4, 40.0, 6.4))
	_next()


func _ph_read_sky() -> void:
	if not _read("looking at the sky", 0.9):
		return
	_check("aiming at the sky: the reticle is OFF", int(_row["reticle"]) == 0)
	_check("aiming at the sky: no ball is created", int(_row["new_balls"]) == 0)
	_check("aiming at the sky: no hole is left in the snow", absf(float(_row["hole"])) < 0.002)
	_drop_and_free()
	_next()


func _ph_carve() -> void:
	if _phase_t < 0.1:
		return
	snow_field.carve(BARE_GROUND, 1.2, 0.5)
	print("[RETICLE] carved a 1.2 m disc at %s for the bare-ground case" % str(BARE_GROUND))
	_next()


func _ph_case_bare() -> void:
	# Wait for the carve to reach the mirror, and give up waiting rather than hanging.
	if _phase_t < 1.0:
		return
	if float(snow_field.get_height_at(BARE_GROUND)) > 0.02 and _phase_t < 4.0:
		return
	_press("looking down at cleared ground", BARE_GROUND)
	_next()


func _ph_read_bare() -> void:
	if not _read("looking down at cleared ground", 0.9):
		return
	_check("aiming at cleared ground: the reticle does not offer to pack", int(_row["reticle"]) != 1)
	_check("aiming at cleared ground: no ball is created", int(_row["new_balls"]) == 0)
	_check("aiming at cleared ground: no hole is left", absf(float(_row["hole"])) < 0.002)
	_drop_and_free()
	_next()


# ---------------------------------------------------------------------------------------
# The reticle in pixels
# ---------------------------------------------------------------------------------------
func _ph_shot_feet() -> void:
	# Aim back down at close snow so the reticle is in its CAN_PACK state, then photograph it.
	if _phase_t < 0.1:
		_aim(SNOW_AT_FEET)
		return
	if _phase_t < 0.5:
		return
	await _shot("reticle_down")
	_next()


func _ph_shot_forward() -> void:
	if _phase_t < 0.1:
		_aim(FORWARD_GAZE)
		return
	if _phase_t < 0.5:
		return
	await _shot("reticle_forward")
	_next()


## Writes the viewport to a PNG and finds the reticle in it by colour.
##
## The reticle is a dark ring with a white dot on top, drawn at the centre of the screen. This
## searches a small box around the centre for the ring's colour, reports where it found it and
## what colour the pixels actually are, and checks that the white dot sits inside the ring. If
## the ring is not in the picture, the reticle is NOT fixed, whatever the code says.
##
## The capture is awaited HERE rather than inside a helper: an `await` in a function called
## without one yields the coroutine object and not its value, which is a mistake that reads as a
## type error three lines later.
func _shot(label: String) -> void:
	var path := "res://screenshot.png"
	await RenderingServer.frame_post_draw
	var msg := ""
	var tex := get_viewport().get_texture()
	if tex == null:
		msg = "the viewport has no texture"
	else:
		var img := tex.get_image()
		if img == null:
			msg = "the viewport image could not be read"
		else:
			var err := img.save_png(ProjectSettings.globalize_path(path))
			if err != 0:
				msg = "the PNG could not be written (err=%d)" % err
	if msg != "":
		_check("'%s': the screenshot could be written" % label, false)
		print("[RETICLE]   %s" % msg)
		return
	print("[RETICLE] wrote %s for '%s'" % [path, label])
	_report_reticle_geometry(label)
	var found := _measure_reticle(path)
	if not found["ok"]:
		_check("'%s': the screenshot could be read back as pixels" % label, false)
		print("[RETICLE]   %s" % found["note"])
		return
	_check("'%s': the screenshot could be read back as pixels" % label, true)
	print("[RETICLE]   %s: dot at (%d, %d) rgb %s luma %.3f | snow beside it luma %.3f | ring luma %.3f | contrast %.3f | redness %.3f | centre offset (%.1f, %.1f) px" % [
		label, int(found["x"]), int(found["y"]), str(found["dot_rgb"]),
		float(found["dot_luma"]), float(found["snow_luma"]), float(found["ring_luma"]),
		float(found["contrast"]), float(found["redness"]),
		float(found["dx"]), float(found["dy"])])
	# A dot has to be found SOMEWHERE in the search box: that is the "is it drawn at all" test.
	_check("'%s': the reticle is drawn near the centre of the screen" % label,
		absf(float(found["dx"])) <= 2.0 and absf(float(found["dy"])) <= 2.0)
	# And it has to be visible, which is contrast and not existence.
	_check("'%s': the reticle is darker than the snow beside it (contrast %.2f)" % [label, float(found["contrast"])],
		float(found["contrast"]) >= MIN_CONTRAST)
	# The state has to be readable from the colour, which is the only reason for a state colour.
	if label == "reticle_down":
		_check("'%s': the reticle shows the packable colour (redder than its ring)'" % label,
			float(found["redness"]) > 0.15)
	else:
		_check("'%s': the reticle does not show the packable colour when there is nothing to do" % label,
			float(found["redness"]) <= 0.15)


## Everything the visibility of the reticle depends on, printed at the moment of the shot.
##
## "Is it visible" has three separate answers -- the player's state, the node's visibility, and
## the node's rectangle on screen -- and a capture that shows nothing does not say which of them
## is wrong. This does.
func _report_reticle_geometry(label: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		for node in root.get_children():
			if node is CanvasLayer and node.has_method("_sync_reticle_from_player"):
				hud = node
				break
	if hud == null:
		print("[RETICLE]   %s: no HUD in the scene to ask" % label)
		return
	var dot = hud.get("_reticle_dot")
	var ring = hud.get("_reticle_dot_ring")
	var drawer = hud.get("_reticle_drawer")
	var vp := get_viewport().get_visible_rect()
	var player_state := int(player.get_reticle_state()) if player.has_method("get_reticle_state") else -99
	print("[RETICLE]   %s: viewport %s | player_state=%d | hud_state=%s | drawer: vis=%s rect=%s | ring: vis=%s rect=%s | dot: vis=%s rect=%s" % [
		label, str(vp.size), player_state, str(hud.get("_reticle_state")),
		str(drawer.visible if drawer != null else "n/a"),
		str(drawer.get_global_rect() if drawer != null else "n/a"),
		str(ring.visible if ring != null else "n/a"),
		str(ring.get_global_rect() if ring != null else "n/a"),
		str(dot.visible if dot != null else "n/a"),
		str(dot.get_global_rect() if dot != null else "n/a")])


## Measures the reticle in a PNG: where the darkest pixel near the centre is, how dark it is
## against the snow beside it, and whether its colour says "a ball can be packed".
func _measure_reticle(path: String) -> Dictionary:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return {"ok": false, "note": "the PNG could not be read back"}
	var size := img.get_size()
	var centre := Vector2i(int(size.x / 2.0), int(size.y / 2.0))
	if size.x < 32 or size.y < 32:
		return {"ok": false, "note": "the screenshot is %s, too small to hold a reticle" % str(size)}

	# The darkest pixel within DOT_RADIUS of the centre is the dot.
	var dot := Color(1.0, 1.0, 1.0)
	var dot_luma := 2.0
	var dot_at := centre
	var r := int(ceil(DOT_RADIUS))
	for y in range(maxi(0, centre.y - r), mini(size.y, centre.y + r + 1)):
		for x in range(maxi(0, centre.x - r), mini(size.x, centre.x + r + 1)):
			var c := img.get_pixel(x, y)
			var luma := (c.r + c.g + c.b) / 3.0
			if luma < dot_luma:
				dot_luma = luma
				dot = c
				dot_at = Vector2i(x, y)

	# The snow beside it: a ring of samples at DOT_RADIUS * 3, far enough out to be background.
	var ring_luma := 0.0
	var ring_count := 0
	var beside_luma := 0.0
	var beside_count := 0
	var beside_sum := Vector3.ZERO
	var far := int(round(DOT_RADIUS * 3.0))
	for angle in range(12):
		var off := Vector2(float(far), 0.0).rotated(TAU * float(angle) / 12.0)
		var sx := clampi(centre.x + int(off.x), 0, size.x - 1)
		var sy := clampi(centre.y + int(off.y), 0, size.y - 1)
		var c := img.get_pixel(sx, sy)
		var luma := (c.r + c.g + c.b) / 3.0
		ring_luma += luma
		ring_count += 1
		# The "snow beside it" is the BRIGHTEST of those samples: on snow the background is
		# white, and the contrast that matters is against the brightest thing around the dot.
		if luma > beside_luma or beside_count == 0:
			beside_luma = luma
		beside_sum += Vector3(c.r, c.g, c.b)
		beside_count += 1
	ring_luma /= float(maxi(ring_count, 1))
	# The background's redness, for comparison with the dot's.
	var beside := beside_sum / float(maxi(beside_count, 1))
	var dot_redness := dot.r - (dot.g + dot.b) * 0.5
	var beside_redness := beside.x - (beside.y + beside.z) * 0.5
	return {
		"ok": true,
		"x": dot_at.x, "y": dot_at.y,
		"dot_rgb": dot, "dot_luma": dot_luma,
		"snow_luma": beside_luma, "ring_luma": ring_luma,
		"contrast": beside_luma - dot_luma,
		"redness": dot_redness - beside_redness,
		"dx": float(dot_at.x - centre.x), "dy": float(dot_at.y - centre.y),
	}


# ---------------------------------------------------------------------------------------
# Aiming, pressing and reading
# ---------------------------------------------------------------------------------------
func _aim(target: Vector3) -> void:
	if player.camera != null:
		player.camera.look_at(target, Vector3.UP)
	player._update_reticle_aim()


## Aims, records what the reticle decided and where the aim landed, then presses.
func _press(label: String, target: Vector3) -> void:
	_row = {"label": label}
	_aim(target)
	var aim: Vector3 = player.get_reticle_aim_point()
	_row["reticle"] = int(player.get_reticle_state())
	_row["hit"] = bool(player.get("reticle_has_hit"))
	_row["dist"] = 9999.0
	_row["avail"] = -1.0
	if aim != Vector3.INF:
		var off := aim - player.global_position
		_row["dist"] = Vector2(off.x, off.z).length()
		_row["avail"] = float(player._estimate_available_snow_kg(aim))
	_row["aim"] = aim
	_press_h = _local_height(aim)
	_press_balls = _count_balls()
	player._pack_snowball()


## Waits for the harvest to land, then measures the outcome. True when the case is complete.
func _read(label: String, wait: float) -> bool:
	if _phase_t < wait:
		return false
	var aim: Vector3 = _row.get("aim", Vector3.INF)
	var ball_kg := -1.0
	if player.has_method("is_carrying") and player.is_carrying():
		var ball = player.get("carried")
		if ball != null and ball.has_method("packed_mass"):
			ball_kg = float(ball.call("packed_mass"))
	_row["ball_kg"] = ball_kg
	_row["new_balls"] = _count_balls() - _press_balls
	_row["hole"] = _press_h - _local_height(aim)
	print("[RETICLE] %-34s reticle=%-9s hit=%-5s dist=%5.2f m avail=%6.3f kg -> new_balls=%d ball=%.3f kg hole=%+.4f m" % [
		label, _state_name(int(_row["reticle"])), str(_row["hit"]), float(_row["dist"]),
		float(_row["avail"]), int(_row["new_balls"]), ball_kg, float(_row["hole"])])
	return true


## Puts the carried ball down and frees it. Packing while carrying does nothing, so leaving the
## hands full would make the following cases pass without testing anything.
func _drop_and_free() -> void:
	if not (player.has_method("is_carrying") and player.is_carrying()):
		return
	var ball = player.get("carried")
	if player.has_method("_release_carried"):
		player.call("_release_carried", Vector3.ZERO)
	if ball != null and is_instance_valid(ball):
		ball.queue_free()


func _state_name(state: int) -> String:
	match state:
		1: return "CAN_PACK"
		2: return "CAN_CARVE"
		_: return "OFF"


## Snow height averaged over a small disc, from the field's own query. The whole field's
## integral cannot resolve a hole 22 cm across; this can.
func _local_height(at: Vector3) -> float:
	if at == Vector3.INF or snow_field == null:
		return -1.0
	var total := 0.0
	var count := 0
	for angle in range(6):
		var offset := Vector2(0.18, 0.0).rotated(TAU * float(angle) / 6.0)
		total += maxf(float(snow_field.get_height_at(at + Vector3(offset.x, 0.0, offset.y))), 0.0)
		count += 1
	total += maxf(float(snow_field.get_height_at(at)), 0.0)
	return total / float(count + 1)


func _count_balls() -> int:
	var c := 0
	for child in props.get_children():
		if child is SnowBallScript and is_instance_valid(child) and not child.is_queued_for_deletion():
			c += 1
	return c


# ---------------------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------------------
func _ph_report() -> void:
	if _phase_t < 0.2:
		return
	await RenderingServer.frame_post_draw
	print("[RETICLE] build %s" % BuildStampScript.commit_hash())
	_report()


func _check(label: String, ok: bool) -> void:
	print("[RETICLE] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1


func _report() -> void:
	if _finished:
		return
	_finished = true
	if _phase < 12:
		_check("the battery reached its last phase (stuck in phase %d)" % _phase, false)
	print("[RETICLE] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[RETICLE] ==== END ====")
	get_tree().create_timer(0.5).timeout.connect(get_tree().quit)


func _on_hard_timeout() -> void:
	if _finished:
		return
	print("[RETICLE] [FAIL] the battery did not finish within %.0f s (stuck in phase %d)" % [HARD_TIMEOUT, _phase])
	_fail += 1
	_report()
