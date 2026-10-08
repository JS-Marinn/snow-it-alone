extends RefCounted

## Pure aim predicates shared by gameplay actions and the reticle.
##
## Keep ray construction and surface sampling in the player; this module receives the resulting
## sample so range policy can be tested without a camera, scene tree, or GPU.


static func close_snow_target_valid(has_hit: bool, aim_point: Vector3, horizontal_distance: float,
		max_reach: float, snow_height: float, min_snow_height: float = 0.015) -> bool:
	if not has_hit or aim_point == Vector3.INF:
		return false
	if not is_finite(horizontal_distance) or horizontal_distance < 0.0 or horizontal_distance > max_reach:
		return false
	return is_finite(snow_height) and snow_height > min_snow_height


static func pack_target_valid(has_hit: bool, aim_point: Vector3, horizontal_distance: float,
		max_reach: float, snow_height: float, available_kg: float, min_kg: float,
		min_snow_height: float = 0.015) -> bool:
	return close_snow_target_valid(
		has_hit, aim_point, horizontal_distance, max_reach, snow_height, min_snow_height) \
		and is_finite(available_kg) and available_kg >= min_kg
