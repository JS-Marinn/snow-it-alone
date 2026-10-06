extends RigidBody3D
## A bucket: a rigid body that holds a measured amount of snow.
##
## It is the small end of the same idea as the wheelbarrow: snow that is not in the field and
## not in a ball, but in a container, with the mass accounted for. Everything here is
## accounting and limits; the part that makes it feel like it is sitting in snow is the one
## marked as an integration point below, and it must not be faked.
##
## Mass is always own_mass + contents_kg, so a full bucket is heavier than an empty one and
## the physics engine does the rest. Nothing here creates or destroys snow: `fill` refuses
## what does not fit and `take` never returns more than it holds, which is what keeps the
## project's mass invariant true.

signal contents_changed(contents_kg: float, capacity_kg: float)

@export var capacity_kg: float = 12.0
## Mass of the bucket itself, without snow. A full bucket should feel heavier than the snow
## in it alone, or carrying an empty one costs nothing.
@export var own_mass_kg: float = 1.8
## Radius used for the snow support query, in metres. Roughly the footprint.
@export var footprint_radius: float = 0.22

var contents_kg: float = 0.0

## True while a player is holding it, so the carrying code and the throw can find it.
var is_carried: bool = false


func _ready() -> void:
	add_to_group("snow_containers")
	_sync_mass()


## Room left, in kg.
func free_space_kg() -> float:
	return maxf(capacity_kg - contents_kg, 0.0)


## How full it is, 0 to 1. For the HUD and for tests.
func fill_ratio() -> float:
	if capacity_kg <= 0.0:
		return 0.0
	return contents_kg / capacity_kg


## Puts snow in. Returns how much actually went in, which is never more than there was room
## for. The caller is responsible for having taken that snow out of the field first: this
## function does not know where snow comes from, and pretending it did would create mass.
func fill(kg: float) -> float:
	var accepted := minf(maxf(kg, 0.0), free_space_kg())
	if accepted <= 0.0:
		return 0.0
	contents_kg += accepted
	_sync_mass()
	contents_changed.emit(contents_kg, capacity_kg)
	return accepted


## Takes snow out, up to what is held. Returns how much came out.
func take(kg: float) -> float:
	var given := minf(maxf(kg, 0.0), contents_kg)
	if given <= 0.0:
		return 0.0
	contents_kg -= given
	_sync_mass()
	contents_changed.emit(contents_kg, capacity_kg)
	return given


## Empties it completely and reports the amount, so the caller can put that snow somewhere
## that accounts for it: a bank, a wheelbarrow, or back into the field.
func empty_all() -> float:
	return take(contents_kg)


func _sync_mass() -> void:
	mass = maxf(own_mass_kg + contents_kg, 0.1)


# ---------------------------------------------------------------------------------------
# INTEGRATION POINT, not written yet, and deliberately not guessed at:
#
# This body has no snow support yet. A bucket resting on snow should sink into it and be held
# up by it exactly as a snowball is, and that behaviour already exists in `scripts/snowball.gd`:
# the support spring and contact friction inside `_integrate_forces`, driven by the field's
# height query at the body's position with `footprint_radius`.
#
# Copy that block rather than re-deriving it, and keep the same damping values, or the bucket
# will behave differently from a ball of the same weight standing in the same snow, which
# players will feel immediately. Until it is copied, treat this as a container that works and
# a physical object that does not.
# ---------------------------------------------------------------------------------------
