extends RigidBody3D
## A stand-in container, used ONLY by `--disposal-machine`.
##
## The machine's rules are about containers, not about the bucket and the wheelbarrow: it must
## ignore a container that touches it, and accept a container that is tipped into it. Testing
## that against a real container would make this battery fail whenever the containers change,
## and the two are separate work. So this is the smallest object that is a container in the
## sense the machine cares about: it holds snow and it says how much room it has.
##
## The method names are the contract (`free_space_kg`, `fill`, `take`, `empty_all`,
## `contents_kg`), and they are the same names `scripts/snow_bucket.gd` uses.

signal contents_changed(contents_kg: float, capacity_kg: float)

@export var capacity_kg: float = 12.0
var contents_kg: float = 0.0


func free_space_kg() -> float:
	return maxf(capacity_kg - contents_kg, 0.0)


func fill(kg: float) -> float:
	var accepted := minf(maxf(kg, 0.0), free_space_kg())
	contents_kg += accepted
	mass = 2.0 + contents_kg
	contents_changed.emit(contents_kg, capacity_kg)
	return accepted


func take(kg: float) -> float:
	var given := minf(maxf(kg, 0.0), contents_kg)
	contents_kg -= given
	mass = 2.0 + contents_kg
	contents_changed.emit(contents_kg, capacity_kg)
	return given


func empty_all() -> float:
	return take(contents_kg)
