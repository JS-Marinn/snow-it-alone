extends RefCounted

## Hand-packing workflow: aim validation, measured field harvest, and payload creation. The player
## controller keeps movement/input state and delegates this asynchronous tool transaction here.

const SnowBallScript = preload("res://scripts/snowball.gd")
const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

const PACK_HARVEST_RADIUS: float = 0.22
const PACK_HARVEST_DEPTH: float = 0.10
const BARE_SNOW_HEIGHT: float = 0.018
const HARVEST_AREA_FACTOR: float = 1.76

var _player: CharacterBody3D
var _snow_field: Node3D
var _pending: bool = false
var _harvest_point: Vector3 = Vector3.INF


func setup(player: CharacterBody3D, snow_field: Node3D) -> void:
	if _snow_field != null and _snow_field.has_signal("op_volume_ready"):
		var old_callback := Callable(self, "_on_op_volume_ready")
		if _snow_field.is_connected("op_volume_ready", old_callback):
			_snow_field.disconnect("op_volume_ready", old_callback)
	_player = player
	_snow_field = snow_field
	if _snow_field != null and _snow_field.has_signal("op_volume_ready"):
		var callback := Callable(self, "_on_op_volume_ready")
		if not _snow_field.is_connected("op_volume_ready", callback):
			_snow_field.connect("op_volume_ready", callback)


func sample_area_snow_height(pos: Vector3, sample_radius: float = PACK_HARVEST_RADIUS) -> float:
	if _snow_field == null or not _snow_field.has_method("get_height_at"):
		return 0.0
	var h0 := maxf(float(_snow_field.get_height_at(pos)), 0.0)
	var total := h0 * 2.0
	var count := 2.0
	var radius := sample_radius * 0.7
	for index in range(8):
		var angle := float(index) * TAU / 8.0
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		total += maxf(float(_snow_field.get_height_at(pos + offset)), 0.0)
		count += 1.0
	return total / count


func harvest_radius_for_depth(depth: float) -> float:
	if depth <= 0.0 or depth >= 0.06:
		return PACK_HARVEST_RADIUS
	# In shallow snow, expand up to 0.31 m so a reachable skim can still make a ball.
	return clampf(sqrt(0.48 / (150.0 * HARVEST_AREA_FACTOR * maxf(depth, 0.018))),
		PACK_HARVEST_RADIUS, 0.31)


func estimate_available_snow_kg(pos: Vector3, harvest_radius: float = PACK_HARVEST_RADIUS) -> float:
	if _snow_field == null or not _snow_field.has_method("get_height_at"):
		return 0.0
	var average_height := sample_area_snow_height(pos, harvest_radius)
	if average_height < BARE_SNOW_HEIGHT:
		return 0.0
	var radius := harvest_radius_for_depth(average_height)
	var cut_depth := minf(PACK_HARVEST_DEPTH, maxf(average_height, 0.02))
	var density_value = _snow_field.get("snow_density")
	var density := float(density_value) if density_value != null else 150.0
	return cut_depth * HARVEST_AREA_FACTOR * radius * radius * density


func is_pending() -> bool:
	return _pending


## Returns false when the target is invalid or the bounded field queue rejects the request.
func request_pack() -> bool:
	if _pending or _player == null or not is_instance_valid(_player):
		return false
	if _snow_field == null or not _snow_field.has_method("request_harvest"):
		return false
	var target: Vector3 = _player.call("_find_pack_target")
	if target == Vector3.INF:
		_player.set("status_message", tr("STATUS_NOT_ENOUGH_SNOW"))
		return false
	_harvest_point = target
	var average_height := sample_area_snow_height(target)
	var radius := harvest_radius_for_depth(average_height)
	var depth := minf(PACK_HARVEST_DEPTH, maxf(average_height, 0.02))
	var owner_id := int(_player.get_instance_id())
	var accepted: bool = bool(_snow_field.request_harvest(
		owner_id, target, target + Vector3(0.02, 0.0, 0.02), radius, depth))
	if not accepted:
		_player.set("status_message", tr("STATUS_SNOW_QUEUE_BUSY"))
		return false
	_set_pending(true)
	_player.set("_pack_harvest_pt", target)
	_player.set("status_message", tr("STATUS_PACKING_SNOW"))
	return true


func _on_op_volume_ready(role: String, owner: int, kg: float) -> void:
	if role != "harvest" or _player == null or not is_instance_valid(_player):
		return
	if owner != int(_player.get_instance_id()) or not _pending:
		return
	_set_pending(false)
	_player.set("last_pack_harvest_kg", kg)
	if kg <= 0.001:
		_player.set("status_message", tr("STATUS_NOT_ENOUGH_SNOW"))
		return
	var max_ball_kg := SnowBallScript.mass_for_radius(SnowBallScript.MAX_RADIUS)
	var ball_kg := minf(kg, max_ball_kg)
	var spill_kg := maxf(kg - ball_kg, 0.0)
	var radius := SnowBallScript.radius_for_packed_mass(ball_kg)
	var props = _player.get("props_system")
	if props == null or not props.has_method("spawn_snowball"):
		_player.call("_spawn_return_chunk", kg, _harvest_point)
		_player.set("status_message", tr("STATUS_SNOW_QUEUE_BUSY"))
		return
	# The packed snow is born in the player's hands; PropsSystem moves the ledger ownership from
	# the player account into the new ball account before returning it.
	var anchor: Vector3 = _player.call("_carry_anchor", radius)
	var ball = props.spawn_snowball(anchor, radius, owner)
	if ball == null:
		_player.call("_spawn_return_chunk", kg, _harvest_point)
		_player.set("status_message", tr("STATUS_SNOW_QUEUE_BUSY"))
		return
	if spill_kg > 0.000001:
		_player.call("_spawn_return_chunk", spill_kg, _harvest_point)
	if bool(_player.call("is_carrying")):
		ball.global_position = _player.global_position + _player.call("_forward_flat") * 0.7 \
			+ Vector3.UP * (radius + 0.05)
		_player.set("status_message", tr("STATUS_BALL_ON_GROUND") % ball.packed_mass())
	else:
		_player.call("_begin_carry", ball)
		_player.set("status_message", tr("STATUS_BALL_IN_HANDS") % ball.packed_mass())
	_play_pack_sound()


func _set_pending(value: bool) -> void:
	_pending = value
	if _player != null and is_instance_valid(_player):
		_player.set("_pending_pack", value)


func _play_pack_sound() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = SoundEffectsScript.get_snow_thud()
	sfx.volume_db = -6.0
	sfx.pitch_scale = 1.2
	_player.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
