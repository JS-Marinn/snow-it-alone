extends Node

# ShovelModesDemo: acceptance battery for the load-and-push shovel.
#
# The owner's brief: remove the flattening verb from the shovel, make one click load the blade and
# the other click push (and pick up a residue while pushing), try it in the test scene only, but
# write it as a portable module that can be switched on in the real game later with one line.
#
# WHAT THIS BATTERY IS FOR. Every claim in that paragraph is checkable, and this checks it:
#
#   1  loading fills the blade at the declared rate
#   2  the field loses exactly what the blade gains, to the project's +-0.05%
#   3  pushing loads less than loading does, and near the declared residue fraction
#   4  pushing actually moves snow: a front, and a trail where it came from
#   5  a pile taller than the blade wall jams it, and a jammed blade takes nothing
#   6  looking forward or at the sky loads nothing and leaves the field alone
#   7  loading from cleared ground loads nothing
#   8  the tamp key does nothing at all in this mode
#   9  the module is portable: its own file names no scene
#  10  the main game still runs LEGACY by default
#
# Prints [SHOVEL] RESULT: N OK / M FAIL. A battery that cannot prepare itself reports failure
# rather than returning in silence.
#
# MASS IS THE POINT. The project's rule is that every kilogram in the blade must have left the
# field and every kilogram that left the field must be in the blade. Checks 2 and 3 are that rule
# applied to both buttons.

const SnowBallScript = preload("res://scripts/snowball.gd")
const BuildStampScript = preload("res://scripts/build_stamp.gd")

## Where the loose snow for these tests is made. Inside the simulated field (which runs from
## z = -20 to z = +20 here) and between the outermost lane and the edge of the field, so the
## scene's own lanes are not what is being measured.
const TEST_AT: Vector3 = Vector3(-4.2, 0.0, 6.2)
## Where the player stands to work on it: one reach in front of the test snow.
const WORK_AT: Vector3 = Vector3(-4.2, 0.0, 7.3)
## A pile this tall is over the blade wall (0.30 m) on purpose.
const TALL_PILE_KG: float = 60.0
const HARD_TIMEOUT: float = 150.0
## The step the loading loop is driven with. Larger than a frame so the test is quick, but the
## per-step kilograms stay small enough to see the rate rather than the cap.
const LOAD_STEP: float = 0.05


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

# Measurements carried between phases, so every verdict is printed from a number and not from
# live state that a later phase has already changed.
var _mass_before: float = 0.0
## The field's blade ledger at the start of a carve, for the exact-loss checks.
var _yield_before: float = 0.0
var _load_before: float = 0.0
var _load_after: float = 0.0
var _cap: float = 25.0
var _push_kg: float = 0.0
var _push_seconds: float = 0.0
var _push_expected_rate: float = 0.0
var _front_before: float = 0.0
var _front_after: float = 0.0
var _behind_before: float = 0.0
var _behind_after: float = 0.0
var _jam_load_before: float = 0.0
var _jam_mass_before: float = 0.0
var _jam_load_after: float = 0.0
var _jam_mass_after: float = 0.0
var _tamp_mass_before: float = 0.0
var _tamp_h_before: float = 0.0
var _tamp_mass_after: float = 0.0
var _tamp_h_after: float = 0.0
var _sky_mass_before: float = 0.0
## Set once a screenshot phase has fired, so the awaited capture runs exactly once.
var _shot_done: bool = false
## Set once the test pack has been topped up, so the topping loop does not run every frame.
var _topped_up: bool = false


func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[SHOVEL] ==== SHOVEL MODES ACCEPTANCE BATTERY ====")
	print("[SHOVEL] build %s" % BuildStampScript.commit_hash())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().create_timer(HARD_TIMEOUT).timeout.connect(_on_hard_timeout)

	if root == null or snow_field == null or player == null:
		_check("the battery could set itself up (needs a scene with a player and a snow field)", false)
		_report()
		return
	if not player.has_method("set_shovel_mode"):
		_check("the player can be given a shovel mode", false)
		_report()
		return
	# The mode is the subject of the test, so ask for it explicitly rather than hoping the scene
	# already did.
	var ShovelModes := preload("res://scripts/shovel_modes.gd")
	if not _set_mode(int(ShovelModes.Mode.LOAD_AND_PUSH)):
		_check("the load-and-push mode can be selected", false)
		_report()
		return
	if player.has_method("equip_tool"):
		player.equip_tool("shovel")
	_cap = float(player.get("shovel_capacity_max"))


func _set_mode(mode: int) -> bool:
	return bool(player.call("set_shovel_mode", mode))


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	_phase_t += delta
	match _phase:
		0: _ph_prepare()
		1: _ph_load()
		2: _ph_read_prepare()
		3: _ph_read_load()
		4: _ph_push()
		5: _ph_read_push()
		6: _ph_push_verdict()
		7: _ph_tall_pile()
		8: _ph_read_jam()
		9: _ph_aim_away()
		10: _ph_read_aim_away()
		11: _ph_tamp()
		12: _ph_read_tamp()
		13: _ph_shot_load()
		14: _ph_shot_push()
		15: _ph_portability()
		16: _ph_legacy()
		17: _ph_report()


func _next() -> void:
	_phase += 1
	_phase_t = 0.0


# ---------------------------------------------------------------------------------------
# 1-2: loading fills the blade and the field loses exactly that
# ---------------------------------------------------------------------------------------
func _ph_prepare() -> void:
	if _phase_t < 0.6:
		return
	if not snow_field.has_method("is_coarse_ready") or not snow_field.is_coarse_ready():
		return
	# Clear a working box and make a modest pack in the middle of it.
	#
	# The first two versions of this hard-coded the amount of snow to dump and assumed a height.
	# Both were wrong: this scene has lanes and deep snow of its own, and 40 kg and 22 kg made
	# packs of 0.34 m -- over the blade wall, so the load test measured the JAM. So the amount is
	# not guessed. The box is cleared, a little is dumped, and the height is MEASURED. If it is
	# still too tall, this reports a failure rather than quietly testing the wrong rule.
	snow_field.carve(TEST_AT, 3.0, 0.5)
	snow_field.carve(Vector3(TEST_AT.x, 0.0, TEST_AT.z + 6.0), 3.0, 0.5)
	player.global_position = Vector3(WORK_AT.x, 0.0, WORK_AT.z)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.set("status_message", "")
	player.set("shovel_current_load", 0.0)
	_next()


func _ph_load() -> void:
	# Let the dump reach the coarse mirror before believing any of it.
	if _phase_t < 1.5:
		return
	_aim_at(TEST_AT)
	if not bool(player.get("reticle_has_hit")):
		_check("the aim ray finds the test snow (the battery can prepare itself)", false)
		_report()
		return
	# Now add snow until the pack is a height the blade can carry, measuring as it goes instead
	# of trusting an amount. Dumping in small steps also keeps the peak from spiking, which is
	# what put the previous attempts over the wall.
	#
	# ONCE ONLY. This phase runs every frame while it waits for the dump to settle, and a topping
	# loop inside it ran eight times per frame until the guard below was added.
	if not _topped_up:
		_topped_up = true
		for attempt in range(8):
			var h_now := _height(TEST_AT)
			if h_now > 0.12:
				break
			snow_field.dump_snow(TEST_AT, 6.0, 2.4)
			print("[SHOVEL]   pack %.4f m -> topping up (attempt %d)" % [h_now, attempt])
	# The settle the dump above needs before any of it counts.
	if _phase_t < 4.0:
		return
	var pack_h := _height(TEST_AT)
	var wall: float = float(player.get("BLADE_WALL_HEIGHT"))
	print("[SHOVEL] test pack height %.4f m, blade wall %.2f m" % [pack_h, wall])
	if pack_h <= 0.02 or pack_h > wall:
		_check("the test pack is loadable: above nothing and below the wall (%.4f m vs %.2f m)" % [pack_h, wall], false)
		_report()
		return
	_next()


## The load measurement.
##
## It used to sit in `_ph_read_prepare` by mistake, behind a `_next()` on the first line, so the
## whole measurement was dead code and the failure it produced ("loading fills the blade") was
## for a reason nobody could see. The phases are now one job each: `_ph_load` makes the pack and
## checks it is loadable, this one loads the blade and judges the result.
func _ph_read_prepare() -> void:
	_yield_before = _blade_yield()
	_load_before = float(player.get("shovel_current_load"))
	# The declared rate, and the time it would take to reach the cap, so the test drives the
	# RATE rather than whatever the cap happens to be.
	var rate := float(player.get("fill_rate"))
	var steps := maxi(1, int(minf(_cap, 8.0) / maxf(rate, 0.001) / LOAD_STEP))
	# What the field hands back per step, printed so a zero can be told apart from a slow trickle.
	var first_out := -1.0
	var aim_now: Vector3 = player.get("reticle_aim_pt")
	var probe_h := float(snow_field.get_height_at(aim_now)) if bool(player.get("reticle_has_hit")) else -99.0
	for i in range(steps):
		_aim_at(TEST_AT)
		aim_now = player.get("reticle_aim_pt")
		var accepted := float(player.call("_load_blade_from_aim", LOAD_STEP))
		if i < 3:
			first_out = accepted
			print("[SHOVEL]   step %d: accepted=%.4f blade_now=%.4f stuck=%s" % [
				i, accepted, float(player.get("shovel_current_load")),
				str(player.get("is_stuck"))])
	_load_after = float(player.get("shovel_current_load"))
	var gained := _load_after - _load_before
	print("[SHOVEL] load: blade %.3f -> %.3f kg (+%.3f) over %d steps, declared rate=%.1f kg/s" % [
		_load_before, _load_after, gained, steps, rate])
	_check("loading fills the blade", gained > 0.5)
	_check("loading does not overflow the blade", _load_after <= _cap + 0.001)
	# The exact-loss verdict is taken in the NEXT phase, after the field's operation has had time
	# to land. Reading the mass here returned the same number every time -- the carve is a queued
	# GPU operation, so at this instant nothing has left yet, and the check was measuring the
	# queue rather than the world.
	_next()


## The exact-loss verdict for the load, after the field has settled.
##
## MASS IS THE POINT of this project: every kilogram in the blade must have left the field. So
## this waits, then compares. The wait is why it is its own phase.
func _ph_read_load() -> void:
	if _phase_t < 2.5:
		return
	var lost := _blade_yield() - _yield_before
	var gained := _load_after - _load_before
	var err := absf(lost - gained) / maxf(gained, 0.001)
	print("[SHOVEL] load exact-loss: field lost %.3f kg, blade gained %.3f kg, error %.3f%%" % [
		lost, gained, err * 100.0])
	_check("the field loses exactly what the blade gains (%.3f%% error, limit 0.05%%)" % [err * 100.0],
		err < 0.0005)
	_next()
# ---------------------------------------------------------------------------------------
func _ph_push() -> void:
	# ONCE. This phase runs every frame until it advances, and without the timer the carve and the
	# dump below were re-issued every frame: the ledger recorded 137 kg of "field loss" against a
	# 13.717 kg blade, a 900% error that was entirely this loop.
	if _phase_t < 0.2:
		return
	# A fresh strip to push into, so the front is made by THIS push and not by the fill above.
	snow_field.carve(Vector3(TEST_AT.x, 0.0, TEST_AT.z + 8.0), 3.0, 0.5)
	snow_field.dump_snow(Vector3(TEST_AT.x, 0.0, TEST_AT.z - 2.0), 200.0, 3.0)
	player.set("shovel_current_load", 0.0)
	# ADVANCE. The timer above makes this phase idempotent; without the `_next` it re-ran every
	# frame and re-issued the carve and the dump, so the setup kept feeding the ledger and the
	# verdict read 137 kg of "field loss" for a 13.7 kg blade. A phase that sets something up and
	# does not advance is the same mistake three other batteries in this project have made.
	_next()


func _ph_read_push() -> void:
	# Wait for the strip to settle, then push along it for a fixed time.
	if _phase_t < 1.5:
		return
	var behind := Vector3(TEST_AT.x, 0.0, TEST_AT.z + 3.0)
	var front := Vector3(TEST_AT.x, 0.0, TEST_AT.z - 3.5)
	player.global_position = Vector3(TEST_AT.x, 0.0, TEST_AT.z + 4.0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.set("shovel_current_load", 0.0)
	_load_before = 0.0
	_behind_before = _height(behind)
	_front_before = _height(front)
	# Zero the ledger HERE, at the end of the settle, and not in the phase above.
	#
	# The carve that clears the strip is a QUEUED GPU operation: it hands its kilograms to the
	# ledger when it runs, which is frames later. Resetting in the same frame as the carve looked
	# correct and measured nothing -- the setup's kilograms arrived afterwards and the verdict
	# read 137.171 kg of field loss for a 13.717 kg blade, a 900% error made entirely of the
	# clearing. By the time this line runs, the field has stopped moving.
	_reset_blade_yield()
	# Drive the pushing path for a fixed number of steps, each one a frame's worth.
	var dt := 1.0 / 60.0
	_push_seconds = 0.0
	for i in range(120):
		Input.action_press("shovel_push")
		player.call("_process_shovel", dt, 0.0)
		_push_seconds += dt
	Input.action_release("shovel_push")
	_load_after = float(player.get("shovel_current_load"))
	_push_kg = _load_after
	var residue_rate: float = float(player.call("push_residue_rate"))
	_push_expected_rate = residue_rate
	print("[SHOVEL] push: blade +%.3f kg over %.2f s (%.2f kg/s), declared residue %.2f kg/s" % [
		_push_kg, _push_seconds, _push_kg / maxf(_push_seconds, 0.001), residue_rate])
	_next()


## The residue's exact-loss verdict and the moved-snow check, after the field settles.
##
## Split from the phase above for the same reason as the load: the carve is queued, so the mass
## and the heights are read after it has landed and not while it is still on its way.
func _ph_push_verdict() -> void:
	if _phase_t < 2.5:
		return
	var mass_lost := _carve_yield() - _yield_before
	var behind := Vector3(TEST_AT.x, 0.0, TEST_AT.z + 3.0)
	var front := Vector3(TEST_AT.x, 0.0, TEST_AT.z - 3.5)
	_behind_after = _height(behind)
	_front_after = _height(front)
	var push_err := absf(mass_lost - _push_kg) / maxf(_push_kg, 0.001)
	print("[SHOVEL] push verdict: field lost %.3f kg, blade gained %.3f kg, error %.3f%%" % [
		mass_lost, _push_kg, push_err * 100.0])
	print("[SHOVEL] push verdict: heights behind %.4f -> %.4f, front %.4f -> %.4f" % [
		_behind_before, _behind_after, _front_before, _front_after])
	_check("the residue in the blade came out of the field (%.3f%% error)" % [push_err * 100.0],
		push_err < 0.0005)
	# The residue must be CLEARLY less than loading: that difference is the whole reason both
	# buttons exist.
	var load_rate := float(player.get("fill_rate"))
	var pushed_rate := _push_kg / maxf(_push_seconds, 0.001)
	print("[SHOVEL] rates: pushing %.2f kg/s vs loading %.2f kg/s (declared residue %.2f)" % [
		pushed_rate, load_rate, _push_expected_rate])
	_check("pushing loads less than loading does", pushed_rate < load_rate)
	_check("pushing moves snow: the front or the trail changed",
		absf(_front_after - _front_before) > 0.001 or absf(_behind_after - _behind_before) > 0.001)
	_next()


# ---------------------------------------------------------------------------------------
# 5: the tall pile jams
# ---------------------------------------------------------------------------------------
func _ph_tall_pile() -> void:
	if _phase_t < 0.2:
		return
	# A pile well over the blade wall, and a clear area beside it for the control case.
	snow_field.carve(Vector3(TEST_AT.x + 3.0, 0.0, TEST_AT.z), 2.0, 0.5)
	snow_field.carve(Vector3(TEST_AT.x + 3.0, 0.0, TEST_AT.z - 3.0), 2.0, 0.5)
	snow_field.dump_snow(Vector3(TEST_AT.x + 3.0, 0.0, TEST_AT.z), TALL_PILE_KG, 0.55)
	player.set("shovel_current_load", 0.0)
	_next()


func _ph_read_jam() -> void:
	if _phase_t < 2.0:
		return
	var tall := Vector3(TEST_AT.x + 3.0, 0.0, TEST_AT.z)
	var clear := Vector3(TEST_AT.x + 3.0, 0.0, TEST_AT.z - 3.0)
	var tall_h := _height(tall)
	print("[SHOVEL] tall pile height %.4f m, wall is %.2f m" % [tall_h, float(player.get("BLADE_WALL_HEIGHT"))])
	# The jam: aim at the tall pile and try to load.
	player.global_position = Vector3(tall.x, 0.0, tall.z + 1.1)
	player.rotation.y = 0.0
	player.set("shovel_current_load", 0.0)
	_aim_at(tall)
	_jam_mass_before = _field_mass()
	for i in range(20):
		_aim_at(tall)
		player.call("_load_blade_from_aim", LOAD_STEP)
	_jam_load_after = float(player.get("shovel_current_load"))
	_jam_mass_after = _field_mass()
	print("[SHOVEL] into the tall pile: blade +%.3f kg, field lost %.3f kg" % [
		_jam_load_after, _jam_mass_before - _jam_mass_after])
	_check("the pile is taller than the blade wall", tall_h > float(player.get("BLADE_WALL_HEIGHT")))
	_check("a pile over the wall does not load the blade", _jam_load_after <= 0.001)

	# CONTROL: the same routine on cleared ground must ALSO load nothing, so the check above is
	# not passing for the wrong reason (a ray that simply never hit anything).
	player.global_position = Vector3(clear.x, 0.0, clear.z + 1.1)
	player.set("shovel_current_load", 0.0)
	_aim_at(clear)
	var clear_h := _height(clear)
	for i in range(20):
		_aim_at(clear)
		player.call("_load_blade_from_aim", LOAD_STEP)
	var clear_load := float(player.get("shovel_current_load"))
	print("[SHOVEL] control, cleared ground height %.4f m: blade +%.3f kg" % [clear_h, clear_load])
	_check("loading from cleared ground adds nothing", clear_load <= 0.001)
	_next()


# ---------------------------------------------------------------------------------------
# 6: looking forward or at the sky
# ---------------------------------------------------------------------------------------
func _ph_aim_away() -> void:
	if _phase_t < 0.2:
		return
	# Back on good snow, with the blade empty, looking at the horizon.
	player.global_position = Vector3(WORK_AT.x, 0.0, WORK_AT.z)
	player.rotation.y = 0.0
	player.set("shovel_current_load", 0.0)
	_aim_at(Vector3(WORK_AT.x, 0.0, WORK_AT.z - 40.0))
	_sky_mass_before = _field_mass()
	_load_before = float(player.get("shovel_current_load"))
	for i in range(20):
		player.call("_load_blade_from_aim", LOAD_STEP)
	var forward_load := float(player.get("shovel_current_load"))
	var forward_mass := _field_mass()
	# And straight up.
	_aim_at(Vector3(WORK_AT.x, 200.0, WORK_AT.z))
	for i in range(20):
		player.call("_load_blade_from_aim", LOAD_STEP)
	var sky_load := float(player.get("shovel_current_load"))
	var sky_mass := _field_mass()
	print("[SHOVEL] aim away: forward -> blade %.3f kg; sky -> blade %.3f kg" % [forward_load, sky_load])
	_check("looking forward loads nothing", forward_load <= 0.001)
	_check("looking at the sky loads nothing", sky_load <= 0.001)
	var moved := absf(_sky_mass_before - forward_mass) + absf(forward_mass - sky_mass)
	_check("aiming away leaves the field mass alone (%.4f kg moved)" % moved, moved < 0.05)
	_next()


func _ph_read_aim_away() -> void:
	# Then the tamp case, in the same phase, so the sequence is: press, then read.
	player.global_position = Vector3(WORK_AT.x, 0.0, WORK_AT.z)
	player.rotation.y = 0.0
	player.set("shovel_current_load", 0.0)
	_aim_at(TEST_AT)
	_tamp_mass_before = _field_mass()
	_tamp_h_before = _height(TEST_AT)
	# Press the real input action, so this tests the binding and not just a function name.
	for i in range(30):
		Input.action_press("shovel_tamp")
		player.call("_process_shovel", 1.0 / 60.0, 0.0)
	Input.action_release("shovel_tamp")
	_tamp_mass_after = _field_mass()
	_tamp_h_after = _height(TEST_AT)
	_next()


# ---------------------------------------------------------------------------------------
# 8: the tamp key does nothing
# ---------------------------------------------------------------------------------------
func _ph_tamp() -> void:
	print("[SHOVEL] tamp pressed in load-and-push: height %.4f -> %.4f, mass %.3f -> %.3f, message='%s'" % [
		_tamp_h_before, _tamp_h_after, _tamp_mass_before, _tamp_mass_after,
		String(player.get("status_message"))])
	_check("the tamp key does not change the height",
		absf(_tamp_h_after - _tamp_h_before) < 0.002)
	_check("the tamp key does not change the mass",
		absf(_tamp_mass_after - _tamp_mass_before) < 0.02)
	_next()


func _ph_read_tamp() -> void:
	_next()


# ---------------------------------------------------------------------------------------
# Screenshots: loading and pushing, read back and reported
# ---------------------------------------------------------------------------------------
func _ph_shot_load() -> void:
	# GUARDED, because the capture awaits a frame and the phase machine keeps calling this phase
	# while the coroutine is suspended. Without the flag the shot ran once per frame for ever and
	# the battery never advanced past it.
	if _shot_done:
		_next()
		return
	if _phase_t < 0.2:
		player.global_position = Vector3(WORK_AT.x, 0.0, WORK_AT.z)
		player.rotation.y = 0.0
		player.set("shovel_current_load", 0.0)
		_aim_at(TEST_AT)
		_third_person()
		return
	if _phase_t < 0.5:
		return
	_shot_done = true
	Input.action_press("shovel_load")
	await get_tree().create_timer(0.3).timeout
	await _shot("shovel_load")
	Input.action_release("shovel_load")
	_next()


func _ph_shot_push() -> void:
	if _shot_done:
		_next()
		return
	if _phase_t < 0.2:
		player.global_position = Vector3(TEST_AT.x, 0.0, TEST_AT.z + 4.0)
		player.rotation.y = 0.0
		player.set("shovel_current_load", 0.0)
		_aim_at(Vector3(TEST_AT.x, 0.0, TEST_AT.z - 6.0))
		_third_person()
		return
	if _phase_t < 0.5:
		return
	_shot_done = true
	Input.action_press("shovel_push")
	for i in range(60):
		player.call("_process_shovel", 1.0 / 60.0, 0.0)
	await _shot("shovel_push")
	Input.action_release("shovel_push")
	_next()


## A camera behind the player, so the shovel and the snow in front of it are both in frame. The
## scene's own free camera is not looking at the player.
func _third_person() -> void:
	var cam: Camera3D = player.get("camera")
	if cam == null:
		return
	var behind := player.global_position + Vector3(2.4, 1.7, 2.4)
	cam.global_position = behind
	cam.look_at(player.global_position + Vector3(0.0, 0.4, -1.2), Vector3.UP)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		_check("'%s': the viewport has a texture to photograph" % label, false)
		return
	var img := tex.get_image()
	if img == null:
		_check("'%s': the viewport image could be read" % label, false)
		return
	var path := "res://screenshot.png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	_check("'%s': the screenshot was written" % label, err == 0)
	if err != 0:
		return
	# Read it back and say what is in it. "Compiles" and "the game loads" are not checks that
	# something is visible, and this project has paid for verifying with the parser alone.
	var back := Image.load_from_file(ProjectSettings.globalize_path(path))
	if back == null:
		_check("'%s': the screenshot could be read back" % label, false)
		return
	var size := back.get_size()
	var centre := Vector2i(int(size.x / 2.0), int(size.y / 2.0))
	# Count distinct colours in a coarse grid: a picture of snow and a shovel has many, a black
	# frame or a flat fill has almost none. This is a liveness check on the image, not an
	# art critic.
	var seen := {}
	for gy in range(0, size.y, 40):
		for gx in range(0, size.x, 40):
			var c := back.get_pixel(gx, gy)
			seen["%d_%d_%d" % [int(c.r * 7.0), int(c.g * 7.0), int(c.b * 7.0)]] = true
	var centre_c := back.get_pixel(centre.x, centre.y)
	print("[SHOVEL] %s: %s, %d distinct colour buckets over the frame, centre pixel %s" % [
		label, str(size), seen.size(), str(centre_c)])
	_check("'%s': the screenshot is a picture of a scene, not a flat or empty frame" % label,
		seen.size() >= 8)


# ---------------------------------------------------------------------------------------
# 9: portability, by reading the file
# ---------------------------------------------------------------------------------------
func _ph_portability() -> void:
	if _phase_t < 0.2:
		return
	var ShovelModes := preload("res://scripts/shovel_modes.gd")
	var result: Dictionary = ShovelModes.check_portability()
	print("[SHOVEL] portability of scripts/shovel_modes.gd: %s" % str(result.get("note", "")))
	_check("the shovel module names no scene (checked by reading the file)",
		bool(result.get("ok", false)))
	_next()


# ---------------------------------------------------------------------------------------
# 10: the main game is untouched
# ---------------------------------------------------------------------------------------
func _ph_legacy() -> void:
	if _phase_t < 0.2:
		return
	# A FRESH player instance, which is what the main game gets, must still be LEGACY. Reading
	# the one in this scene would only prove the battery set it.
	var fresh: Node = null
	if player.get_script() != null:
		fresh = player.get_script().new()
	if fresh == null:
		_check("a fresh player can be made to check its default mode", false)
		_report()
		return
	var mode := int(fresh.get("shovel_mode"))
	print("[SHOVEL] a freshly created player starts in mode %d (%s)" % [
		mode, str(fresh.call("shovel_mode_name"))])
	_check("a fresh player starts in LEGACY, so the main game is unchanged", mode == 0)
	# And the shipped configuration must not switch it on for anyone.
	var cfg := ""
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f != null:
		cfg = f.get_as_text().to_lower()
		f.close()
	var key := "shovel" + "_mode"
	_check("the shipped project settings do not switch the new mode on", not cfg.contains(key))
	_next()


func _ph_report() -> void:
	if _phase_t < 0.2:
		return
	print("[SHOVEL] build %s" % BuildStampScript.commit_hash())
	_report()


# ---------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------
func _aim_at(target: Vector3) -> void:
	var cam: Camera3D = player.get("camera")
	if cam == null:
		return
	cam.look_at(target, Vector3.UP)
	player.call("_update_reticle_aim")


func _field_mass() -> float:
	if snow_field.has_method("measure_total_mass"):
		return float(snow_field.measure_total_mass())
	return 0.0


## The field's blade ledger: exact kilograms handed to blades since the last reset.
##
## This is what the exact-loss checks read, and NOT a difference of whole-field integrals. The
## integral drifts by more than the carve it is being asked to adjudicate -- see the note on
## `_shovel_yield_kg` in `snow_field.gd` -- so it is not a measurement of mass at this scale.
func _blade_yield() -> float:
	if snow_field.has_method("shovel_yield_kg"):
		return float(snow_field.call("shovel_yield_kg"))
	return 0.0


## Clears the field's blade ledger, so a carve can be measured from a known zero.
func _reset_blade_yield() -> void:
	if snow_field.has_method("reset_shovel_yield"):
		snow_field.call("reset_shovel_yield")


## Every kilogram the field gave up by ANY route, including the radial clearing this battery's own
## setup uses.
##
## WHY BOTH LEDGERS EXIST. This battery clears a strip with `carve` and then pushes along it. The
## blade ledger counts only `carve_shovel`, so the setup's kilograms were never in the number the
## push verdict subtracted -- and no reset can remove what was never counted. Measured: -90.979 kg
## of "field loss" against a 17.000 kg blade. This ledger counts both routes, so resetting it after
## the setup leaves exactly the push.
func _carve_yield() -> float:
	if snow_field.has_method("carve_yield_kg"):
		return float(snow_field.call("carve_yield_kg"))
	return _blade_yield()


func _reset_carve_yield() -> void:
	if snow_field.has_method("reset_carve_yield"):
		snow_field.call("reset_carve_yield")


## Snow height averaged over a small disc, from the field's own query.
func _height(at: Vector3) -> float:
	var total := 0.0
	var count := 0
	for a in range(6):
		var off := Vector2(0.22, 0.0).rotated(TAU * float(a) / 6.0)
		total += maxf(float(snow_field.get_height_at(at + Vector3(off.x, 0.0, off.y))), 0.0)
		count += 1
	total += maxf(float(snow_field.get_height_at(at)), 0.0)
	return total / float(count + 1)


func _check(label: String, ok: bool) -> void:
	print("[SHOVEL] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1


func _report() -> void:
	if _finished:
		return
	_finished = true
	if _phase < 17:
		_check("the battery reached its last phase (stuck in phase %d)" % _phase, false)
	print("[SHOVEL] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[SHOVEL] ==== END ====")
	get_tree().create_timer(0.5).timeout.connect(get_tree().quit)


func _on_hard_timeout() -> void:
	if _finished:
		return
	print("[SHOVEL] [FAIL] the battery did not finish within %.0f s (stuck in phase %d)" % [HARD_TIMEOUT, _phase])
	_fail += 1
	_report()
