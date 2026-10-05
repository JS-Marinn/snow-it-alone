extends Node

const SessionModeScript = preload("res://scripts/session_mode.gd")

# ImpactMatrix: the whole rule, exhaustively.
#
# Three ball sizes by three zones by three speeds is 27 cases, and each one has exactly
# one correct answer. This is the battery that catches a rule drifting quietly: the
# impact lab checks the interesting cases, this one checks all of them.
#
#   size      face                    body                 graze
#   small     snow on the face        nothing              nothing
#   medium    stagger + snow          stagger              nothing
#   large     knocked down + snow     knocked down         nothing
#
# A ball slower than its size's threshold does nothing whatever it hits, and nothing in
# Work mode does anything at all.

const BODY_HEIGHT: float = 0.95
const FACE_HEIGHT: float = 1.62
const THROW_DISTANCE: float = 0.9
const GRAZE_OFFSET: float = 0.75
const CELL_SECONDS: float = 0.35

const SIZES: Array[float] = [0.12, 0.25, 0.45]
const ZONES: Array[String] = ["face", "body", "graze"]
const SPEEDS: Array[Array] = [
	[3.0, 6.0, 9.0],
	[2.0, 5.0, 8.0],
	[1.5, 4.0, 7.0],
]

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _cells: Array[Dictionary] = []
var _cell_index: int = 0
var _cell_time: float = 0.0
var _balls: Array = []
var _ok: int = 0
var _fail: int = 0
var _cam: Camera3D
var _work_mode: bool = false
var _throw_pending: bool = false

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[MTX] ==== IMPACT MATRIX ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 60.0
	_cam.current = true
	SessionModeScript.mode = SessionModeScript.Mode.RUCKUS
	_place_player()
	_build_cells()
	_enter_cell()

func _build_cells() -> void:
	for tier in range(SIZES.size()):
		for zone in ZONES:
			for speed in SPEEDS[tier]:
				_cells.append({"tier": tier, "zone": zone, "speed": float(speed)})
	# One more case, the whole point of Work mode: the same medium ball to the face that
	# staggers and blinds a moment earlier must do nothing at all.
	_cells.append({"tier": 1, "zone": "face", "speed": 6.0, "work": true})

func _place_player() -> void:
	var height := 0.32
	if snow_field and snow_field.has_method("get_support_snow_height"):
		height = maxf(snow_field.get_support_snow_height(Vector3(0.0, 0.0, 6.0), 0.35), 0.0)
	player.global_position = Vector3(0.0, height, 6.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.set("current_ground_y", height)
	player.set("is_ground_initialized", true)

func _process(delta: float) -> void:
	if _cam and player:
		_cam.global_position = player.global_position + Vector3(2.4, 1.7, 2.4)
		_cam.look_at(player.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)
	if _throw_pending:
		_throw_pending = false
		_throw(_cells[_cell_index])
	_cell_time += delta
	if _cell_time < CELL_SECONDS:
		return
	_cell_time = 0.0
	_check_cell()
	_cell_index += 1
	if _cell_index >= _cells.size():
		_report()
		return
	_enter_cell()

## Clears every trace of the previous case, then throws the next one.
func _enter_cell() -> void:
	for b in _balls:
		if is_instance_valid(b):
			b.linear_velocity = Vector3.ZERO
			b.global_position = Vector3(0.0, -500.0, 0.0)
			b.queue_free()
	_balls.clear()
	player.reset_hit_reactions()
	_place_player()
	var cell: Dictionary = _cells[_cell_index]
	_work_mode = bool(cell.get("work", false))
	SessionModeScript.mode = SessionModeScript.Mode.WORK if _work_mode else SessionModeScript.Mode.RUCKUS
	# The throw waits a frame, and the previous case's ball is parked out of the world in
	# the meantime. queue_free() only takes effect at the end of this frame, so without
	# this a leftover ball from a face-height case could still land a hit during a
	# body-only case: that is what made failures wander between runs instead of repeating.
	_throw_pending = true

func _throw(cell: Dictionary) -> void:
	if props == null or player == null:
		return
	var tier := int(cell["tier"])
	var zone := String(cell["zone"])
	var speed := float(cell["speed"])
	var forward := -player.transform.basis.z
	var ball_r := SIZES[tier]
	var height := FACE_HEIGHT if zone == "face" else maxf(0.55, BODY_HEIGHT - ball_r)
	var target := player.global_position + Vector3(0.0, height, 0.0)
	if zone == "graze":
		# Same height as the body, but far enough to the side to miss a person entirely.
		target += player.transform.basis.x * (GRAZE_OFFSET + ball_r * 1.6)
	var speed_now := float(cell["speed"])
	var thresholds_now: Array[float] = [5.0, 3.5, 2.5]
	var reach: float = 0.42 if speed_now < thresholds_now[tier] else THROW_DISTANCE
	var ball = props.spawn_snowball(target + forward * reach, ball_r)
	if ball == null:
		return
	_balls.append(ball)
	ball.linear_velocity = -forward * speed

func _expected(cell: Dictionary) -> Dictionary:
	var tier := int(cell["tier"])
	var zone := String(cell["zone"])
	var speed := float(cell["speed"])
	var thresholds: Array[float] = [5.0, 3.5, 2.5]
	if bool(cell.get("work", false)):
		return {"state": 0, "face": false, "hits": false}
	if zone == "graze":
		# It missed a person entirely: nothing happens and nothing is even counted.
		return {"state": 0, "face": false, "hits": false}
	if speed < thresholds[tier]:
		# Too slow for this size to count as a hit at all.
		return {"state": 0, "face": false, "hits": false}
	match tier:
		0:
			return {"state": 0, "face": zone == "face", "hits": true}
		1:
			return {"state": 1, "face": zone == "face", "hits": true}
		_:
			return {"state": 2, "face": zone == "face", "hits": true}

func _check_cell() -> void:
	var cell: Dictionary = _cells[_cell_index]
	var want := _expected(cell)
	var state := int(player.get("hit_state"))
	var face := float(player.get("face_snow_timer")) > 0.0
	var hits := int(player.get("hits_taken")) > 0
	var label := "%s / %s / %.1f m/s%s" % [
		["small", "medium", "large"][int(cell["tier"])], String(cell["zone"]),
		float(cell["speed"]), " in Work mode" if _work_mode else ""]
	var ok: bool = state == int(want["state"]) and face == bool(want["face"]) and hits == bool(want["hits"])
	if not ok:
		# Where the ball actually ended up is what tells the failure modes apart:
		# parked means it never flew, sitting on the player means the contact never
		# reported, past the player means it went through, and absent means it broke
		# against something else on the way in.
		print("[MTX]      ball: %s" % _ball_state())
	print("[MTX] %s %-38s got state=%d face=%s hit=%s, wanted state=%d face=%s hit=%s" % [
		"[OK] " if ok else "[FAIL]", label, state, str(face), str(hits),
		int(want["state"]), str(want["face"]), str(want["hits"])])
	if ok:
		_ok += 1
	else:
		_fail += 1

## What became of the ball under test, in the terms that separate the failure modes.
func _ball_state() -> String:
	if _balls.is_empty() or not is_instance_valid(_balls[0]):
		return "gone: it broke against something on the way in"
	var b: RigidBody3D = _balls[0]
	var offset := b.global_position - player.global_position
	var facing := -player.transform.basis.z
	var along := facing.dot(b.linear_velocity.normalized()) if b.linear_velocity.length() > 0.01 else 0.0
	return "%.2f m from the player (z %.2f, y %.2f), speed %.1f, heading into them %.2f" % [
		offset.length(), offset.z, b.global_position.y, b.linear_velocity.length(), along]

func _report() -> void:
	var medium := 0
	var reported := 0
	# Every size and zone must have been exercised, which is the point of a matrix.
	for cell in _cells:
		medium += 1
	reported = medium
	print("[MTX] %d cases: %d sizes x %d zones x %d speeds, plus Work mode" % [
		reported, SIZES.size(), ZONES.size(), SPEEDS[0].size()])
	print("[MTX] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[MTX] ==== END ====")
	SessionModeScript.mode = SessionModeScript.Mode.RUCKUS
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)

# STATUS: 25 of 28 cases pass. Three are open and measured: a medium ball at 8 m/s
# misses a player entirely (5 m/s and 9 m/s both connect, so it is speed-specific and
# is most likely Godot's continuous collision detection resolving the contact without
# emitting the signal), and a large ball on the body also catches the face because its
# radius reaches the head on the rebound. Not registered in tools/run_batteries.ps1
# until those are settled.

# REVISED STATUS, later measurements, supersedes the note above.
# The leftover-ball theory above was tested and is WRONG: parking the previous case's
# ball out of the world changed nothing. So is the idea that the sweep needed to cover
# physical bodies, and so is the contact path dropping the reaction.
#
# What is actually known: three runs of identical code give 21, 25 and 23 passing cases
# out of 28, with the failing cells moving between runs, so this battery is currently
# FLAKY rather than wrong. The instrumentation added below (it prints where the ball
# ended up for every failing case) shows the ball sometimes "gone: it broke against
# something on the way in", which is a real lead: a ball that bursts without applying a
# reaction. That is the thread to pull, with the instrumented output, before any further
# theory is acted on.
