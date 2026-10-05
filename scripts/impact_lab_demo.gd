extends Node

# ImpactLab: checks what a thrown snowball does to a player.
#
# The rules under test: a small ball only matters to the face, a medium one
# staggers and also blinds if it hits the face, a large one knocks you down and
# makes you drop what you carry. Face snow clears itself or is wiped off, and no
# hit can ever be chained into a lock.

const HIT_Z: float = 6.0
const FACE_HEIGHT: float = 1.62
const BODY_HEIGHT: float = 0.95
const THROW_DISTANCE: float = 0.9

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _i: int = 0
var _steps: Array = []
var _ok: int = 0
var _fail: int = 0
var _cam: Camera3D
var _dummy: Node3D

var _ball: SnowBall = null
var _carried: SnowBall = null
var _hits_before: int = 0
var _wipe_started_with: float = 0.0
var _last_ball_alive: bool = true

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[HIT] ==== BALL IMPACT LAB ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_camera()
	_steps = [
		[0.6, _s_prepare],
		[0.9, _s_check_tiers],
		# Small ball: only the face matters.
		[1.2, func(): _throw_at_player(true, 0.12, 7.0)],
		[1.5, _s_check_small_face],
		[1.8, _s_reset],
		[2.0, func(): _throw_at_player(false, 0.12, 7.0)],
		[2.4, _s_check_small_body],
		[2.6, _s_reset],
		# Medium ball: staggers, and blinds too if it is the face.
		[2.8, func(): _throw_at_player(false, 0.25, 6.0)],
		[3.1, _s_check_stagger],
		[4.4, _s_check_stagger_over],
		[4.6, _s_reset],
		[4.8, func(): _throw_at_player(true, 0.25, 6.0)],
		[5.1, _s_check_stagger_face],
		[5.4, _s_reset],
		# Large ball: knocked down, and the carried ball is dropped.
		[5.6, _s_carry_then_knock],
		[6.0, _s_check_knockdown],
		[6.3, _s_reset],
		# No chaining: blocked while a reaction is running, and while immune.
		[6.5, _s_immunity_setup],
		[6.8, func(): _throw_at_player(false, 0.25, 6.0)],
		[7.1, _s_check_blocked_during],
		[7.7, func(): _throw_at_player(false, 0.25, 6.0)],
		[8.0, _s_check_blocked_immune],
		[8.2, _s_reset],
		# A ball that is only rolling is not a hit.
		[8.4, func(): _throw_at_player(true, 0.25, 2.0)],
		[8.8, _s_check_too_slow],
		[9.0, _s_reset],
		# Wiping beats waiting.
		[9.2, _s_wipe_start],
		[9.5, _s_wipe_press],
		[10.4, _s_check_wipe],
		[10.6, _s_reset],
		# The dummy takes the same hits, which is how this is played solo.
		[10.8, _s_dummy_hit],
		[11.2, _s_check_dummy],
		[11.6, _s_report],
	]

func _process(delta: float) -> void:
	_t += delta
	while _i < _steps.size() and _t >= float(_steps[_i][0]):
		var fn: Callable = _steps[_i][1]
		fn.call()
		_i += 1
	# Deterministic: the player's facing is pinned, so throws and sweeps agree.
	if player:
		player.rotation.y = 0.0
		var cam = player.get_node_or_null("Camera3D")
		if cam:
			cam.rotation.x = deg_to_rad(-8.0)
	_update_camera()

func _check(label: String, ok: bool) -> void:
	print("[HIT] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _p(name: String, fallback: float) -> float:
	if player == null:
		return fallback
	return float(player.get(name))

func _speed() -> float:
	if player == null:
		return 0.0
	return Vector2(player.velocity.x, player.velocity.z).length()

## Places the player at a known spot and clears every reaction between tests.
func _s_reset() -> void:
	_stop_input()
	if _ball != null and is_instance_valid(_ball):
		_ball.queue_free()
	_ball = null
	if _carried != null and is_instance_valid(_carried):
		player._release_carried(Vector3.ZERO)
		_carried.queue_free()
	_carried = null
	if player:
		player.reset_hit_reactions()
		player.set("auto_bhop", false)
		player.velocity = Vector3.ZERO
	if _dummy and _dummy.has_method("reset_reactions"):
		_dummy.reset_reactions()

func _stop_input() -> void:
	for action in ["move_forward", "move_left", "move_right", "sprint", "jump", "interact"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)

func _s_prepare() -> void:
	if player == null:
		return
	var height := 0.32
	if snow_field and snow_field.has_method("get_support_snow_height"):
		height = maxf(snow_field.get_support_snow_height(Vector3(0.0, 0.0, HIT_Z), 0.35), 0.0)
	player.global_position = Vector3(0.0, height, HIT_Z)
	player.velocity = Vector3.ZERO
	player.set("current_ground_y", height)
	player.set("is_ground_initialized", true)
	player.reset_hit_reactions()
	_dummy = root.get_node_or_null("TrainingDummy")
	print("[HIT] player at %s, dummy=%s" % [str(player.global_position), str(_dummy != null)])

## Fires a ball at the player from just in front, at a chosen height and speed.
## Coming from behind is available because a carried ball sits in front and would
## otherwise be what the ball hits.
func _throw_at_player(head: bool, ball_radius: float, speed: float, behind: bool = false) -> void:
	if props == null or player == null:
		return
	var forward := -player.transform.basis.z
	if behind:
		forward = -forward
	var height := FACE_HEIGHT if head else BODY_HEIGHT
	var target := player.global_position + Vector3(0.0, height, 0.0)
	_ball = props.spawn_snowball(target + forward * THROW_DISTANCE, ball_radius)
	if _ball == null:
		return
	_ball.linear_velocity = -forward * speed

func _s_check_tiers() -> void:
	var small: int = SnowBall.tier_for_radius(0.12)
	var medium: int = SnowBall.tier_for_radius(0.25)
	var large: int = SnowBall.tier_for_radius(0.45)
	print("[HIT] tiers: r=0.12 -> %d, r=0.25 -> %d, r=0.45 -> %d" % [small, medium, large])
	_check("radii classify into the three tiers",
		small == SnowBall.BallTier.SMALL and medium == SnowBall.BallTier.MEDIUM and large == SnowBall.BallTier.LARGE)

func _s_check_small_face() -> void:
	print("[HIT] small to the face: state=%d head=%s face=%.1f" % [
		int(_p("hit_state", -1)), str(bool(player.get("last_hit_was_head"))), _p("face_snow_timer", 0.0)])
	_check("a small ball to the face fills it with snow", _p("face_snow_timer", 0.0) > 0.0)
	_check("a small ball does not destabilise", int(_p("hit_state", -1)) == 0)

func _s_check_small_body() -> void:
	print("[HIT] small to the body: state=%d face=%.1f" % [int(_p("hit_state", -1)), _p("face_snow_timer", 0.0)])
	_check("a small ball to the body does nothing", _p("face_snow_timer", 0.0) <= 0.0 and int(_p("hit_state", -1)) == 0)

func _s_check_stagger() -> void:
	print("[HIT] medium to the body: state=%d (1=staggered) face=%.1f" % [
		int(_p("hit_state", -1)), _p("face_snow_timer", 0.0)])
	_check("a medium ball destabilises", int(_p("hit_state", -1)) == 1)
	_check("a medium ball to the body does not blind", _p("face_snow_timer", 0.0) <= 0.0)

func _s_check_stagger_over() -> void:
	print("[HIT] 1.3 s later: state=%d immunity=%.2f" % [
		int(_p("hit_state", -1)), _p("hit_immunity", 0.0)])
	_check("being destabilised wears off", int(_p("hit_state", -1)) == 0)
	_check("and it leaves an immunity window", _p("hit_immunity", 0.0) > 0.0)

func _s_check_stagger_face() -> void:
	print("[HIT] medium to the face: state=%d face=%.1f" % [int(_p("hit_state", -1)), _p("face_snow_timer", 0.0)])
	_check("a medium ball to the face also blinds", _p("face_snow_timer", 0.0) > 0.0)
	_check("a medium ball to the face still destabilises", int(_p("hit_state", -1)) == 1)

## Carry something, then take a large ball on the body.
func _s_carry_then_knock() -> void:
	if props == null or player == null:
		return
	_carried = props.spawn_snowball(player.global_position + Vector3(0.0, 1.4, -0.4), 0.14)
	if _carried != null:
		player._begin_carry(_carried)
	_throw_at_player(false, 0.45, 5.0, true)

func _s_check_knockdown() -> void:
	print("[HIT] large to the body: state=%d (2=knocked down) carrying=%s" % [
		int(_p("hit_state", -1)), str(player.is_carrying())])
	_check("a large ball knocks the player down", int(_p("hit_state", -1)) == 2)
	_check("being knocked down makes you drop what you carried", not player.is_carrying())

func _s_immunity_setup() -> void:
	_throw_at_player(false, 0.25, 6.0)

func _s_check_blocked_during() -> void:
	_hits_before = int(_p("hits_taken", 0.0))
	print("[HIT] after one medium hit and one more ball in flight: hits=%d state=%d" % [
		_hits_before, int(_p("hit_state", -1))])
	_check("no hit lands while a reaction is running", _hits_before == 1)

func _s_check_blocked_immune() -> void:
	var now := int(_p("hits_taken", 0.0))
	print("[HIT] after a third ball, during the grace period: hits=%d immunity=%.2f" % [
		now, _p("hit_immunity", 0.0)])
	_check("nor inside the immunity window", now == _hits_before)

func _s_check_too_slow() -> void:
	print("[HIT] slow ball: hits=%d state=%d ball_alive=%s" % [
		int(_p("hits_taken", 0.0)), int(_p("hit_state", -1)), str(_ball != null and is_instance_valid(_ball))])
	_check("a ball that is only rolling is not a hit", int(_p("hits_taken", 0.0)) == 0)

## Face snow, then wipe it off by hand.
func _s_wipe_start() -> void:
	_throw_at_player(true, 0.12, 7.0)

func _s_wipe_press() -> void:
	_wipe_started_with = _p("face_snow_timer", 0.0)
	Input.action_press("interact")
	print("[HIT] snow on the face: %.2f s left, holding [E] to wipe" % _wipe_started_with)

func _s_check_wipe() -> void:
	Input.action_release("interact")
	var remaining := _p("face_snow_timer", 0.0)
	print("[HIT] after 0.9 s of wiping: started with %.2f s, %.2f s left" % [
		_wipe_started_with, remaining])
	# The snow lasts 3.5 s, so clearing it inside a second can only be the wipe.
	_check("holding [E] wipes the face faster than waiting",
		_wipe_started_with > 0.0 and remaining <= 0.0)

func _s_dummy_hit() -> void:
	if _dummy == null or props == null:
		return
	var forward := Vector3.FORWARD
	var target: Vector3 = _dummy.global_position + Vector3(0.0, 0.75, 0.0)
	_ball = props.spawn_snowball(target + forward * 1.0, 0.25)
	if _ball != null:
		_ball.linear_velocity = -forward * 6.0

func _s_check_dummy() -> void:
	if _dummy == null:
		_check("the training dummy takes hits", false)
		return
	var hits := int(_dummy.get("hits_taken"))
	var state := int(_dummy.get("state"))
	print("[HIT] dummy: hits=%d state=%d (1=staggered)" % [hits, state])
	_check("the training dummy takes hits", hits > 0)
	_check("the dummy reacts like a player does", state == 1)

func _s_report() -> void:
	print("[HIT] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	print("[HIT] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var v_tex := get_viewport().get_texture()
	if v_tex == null:
		return
	var img := v_tex.get_image()
	if img == null:
		return
	var err := img.save_png("res://hit_%s.png" % label)
	print("[HIT] screenshot hit_%s.png (err=%d)" % [label, err])

func _setup_camera() -> void:
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 60.0
	_cam.make_current()

func _update_camera() -> void:
	if _cam == null or player == null:
		return
	_cam.global_position = player.global_position + Vector3(2.6, 1.8, 2.6)
	_cam.look_at(player.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)
