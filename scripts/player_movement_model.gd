extends RefCounted

## Pure Quake-style horizontal movement math. PlayerController owns state and timing; this module
## owns the reusable friction, acceleration, and horizontal speed-cap equations.


static func apply_ground_friction(velocity: Vector3, ground_friction: float,
		surface_friction: float, stop_speed: float, delta: float) -> Vector3:
	var result := velocity
	var flat := Vector2(result.x, result.z)
	var speed := flat.length()
	if speed < 0.1:
		result.x = 0.0
		result.z = 0.0
		return result
	var control := maxf(speed, stop_speed)
	var drop := control * ground_friction * surface_friction * delta
	var new_speed := maxf(speed - drop, 0.0) / speed
	result.x *= new_speed
	result.z *= new_speed
	return result


static func accelerate(velocity: Vector3, wish_dir: Vector3, wish_speed: float,
		acceleration: float, delta: float, speed_for_accel: float = -1.0) -> Vector3:
	var result := velocity
	var current := result.x * wish_dir.x + result.z * wish_dir.z
	var add := wish_speed - current
	if add <= 0.0:
		return result
	var scale_speed := speed_for_accel if speed_for_accel > 0.0 else wish_speed
	var accel_speed := minf(acceleration * delta * scale_speed, add)
	result.x += accel_speed * wish_dir.x
	result.z += accel_speed * wish_dir.z
	return result


static func cap_horizontal_speed(velocity: Vector3, max_speed: float) -> Vector3:
	var result := velocity
	var flat := Vector2(result.x, result.z)
	var cap := maxf(max_speed, 0.0)
	if flat.length() > cap:
		flat = flat.normalized() * cap
		result.x = flat.x
		result.z = flat.y
	return result
