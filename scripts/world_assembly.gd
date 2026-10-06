extends Object
##
## WorldAssembly: the jobs the level and the test scene both have to do, written once.
##
## WHY THIS EXISTS. `main.gd` and `playground.gd` are two scenes that each build a world, and nine
## of those jobs were done twice in both files. Duplication is not a style complaint here: it has
## already cost this project real time.
##
##   * The disposal machine's payout lived in both files. When the rounding was wrong -- `ceil` per
##     emission, so a shattered ball earned a coin per fragment, measured at 8 coins for 0.546 kg
##     against a declared 2 -- it had to be found and fixed in two places, and the two copies had
##     already drifted apart (the test scene's copy had a null guard the level's did not).
##   * The HUD subtree existed twice, byte for byte, and a reticle fix reached the level and not the
##     test scene because of it. The owner reported that as a bug.
##
## A job that has to be done in two places is a job that will be done differently in one of them.
## This module is where the shared ones live; the scenes keep only what is genuinely theirs.
##
## DELIBERATELY NOT HERE: anything that needs to know which scene it is in. The machine's position,
## the payout guard, the level's decoration and the test scene's lanes all stay in their scenes,
## passed in as arguments where a shared function needs them.

## The payout ledger: everything a machine has taken, and what has been paid for it.
##
## A small object rather than two loose floats because the two numbers are only meaningful together,
## and because a scene holding one without the other is a scene that will get it wrong.
class PayoutLedger:
	var sent_kg: float = 0.0
	var paid_coins: int = 0

	## Records a delivery and returns the coins it is worth, given the running total.
	##
	## PAID ON THE TOTAL, not on the delivery. A machine emits once per body it swallows, and a
	## thrown ball that breaks on arrival is many small bodies; paying `ceil(kg * rate)` per
	## emission gives every fragment at least one coin, which is right for a bucket and wrong for a
	## crumb. Rounding once, on everything taken so far, keeps the rate exact and removes the floor.
	##
	## Returns 0 when this delivery has not yet completed a coin, which is a normal outcome and not
	## a failure: eight fragments of 0.068 kg owe two coins between them, and the first few owe none.
	func add(kg: float, rate_per_kg: float) -> int:
		sent_kg += kg
		var owed := int(ceil(sent_kg * rate_per_kg))
		var coins := owed - paid_coins
		if coins <= 0:
			return 0
		paid_coins = owed
		return coins

	## What the declared formula owes for the whole ledger. `paid_coins` always equals this.
	func owed(rate_per_kg: float) -> int:
		return int(ceil(sent_kg * rate_per_kg))


## Builds the props system both scenes need: the node, its script, and the wiring to the field and
## the player. Returns the node, or null when it could not be made.
##
## The script path is passed in rather than declared here so this module does not need to know the
## project's file layout, and so a scene could substitute its own.
static func build_props_system(parent: Node, script_path: String, snow_field: Node, player: Node) -> Node3D:
	if parent == null or snow_field == null:
		return null
	var props := Node3D.new()
	props.name = "PropsSystem"
	var script = load(script_path)
	if script == null:
		push_warning("WorldAssembly: could not load %s; this scene will have no props." % script_path)
		return null
	props.set_script(script)
	parent.add_child(props)
	if props.has_method("setup"):
		props.setup(snow_field)
	if player != null and "props_system" in player:
		player.props_system = props
	return props
