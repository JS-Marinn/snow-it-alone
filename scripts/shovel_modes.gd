extends Node
##
## ShovelModes: the load-and-push shovel, as a module that knows nothing about any scene.
##
## WHAT THIS IS. A self-contained description of two behaviours for the shovel, and the values
## that define the new one, so that turning the new shovel on somewhere is a one-line statement
## and turning it off again is another.
##
## WHY IT IS A MODULE AND NOT A FLAG INSIDE A SCENE. The owner asked for the new shovel to be
## tried in the test scene first and moved to the real game later "easily". A behaviour written
## into a scene cannot be moved anywhere: it would have to be copied, and the copy would drift.
## So this file holds the mode, the constants, and nothing else, and the caller decides which mode
## it wants:
##
##     player.set_shovel_mode(ShovelModes.Mode.LOAD_AND_PUSH)
##
## PORTABILITY IS CHECKED, NOT INTENDED. `check_portability()` reads THIS FILE back and reports
## any reference to the test scene by name. `--shovel-modes` fails on that check. Without it,
## "it is global" is a hope; with it, it is a fact that can stop a commit.
##
## WHAT IT DELIBERATELY DOES NOT DO:
##   * It does not reference the test scene, its script, or ANY scene path at all. A module that
##     asks for one particular scene file is not portable whatever that scene is called. That is
##     the whole point.
##   * It does not change the main game. `Mode.LEGACY` is the default everywhere, and this file
##     does not touch a default of any kind.
##   * It does not hold per-scene state. The mode is one enum value; everything else is a constant.
##
## ON THE SELF-CHECK AND ITS OWN TEXT. The needles below are assembled from pieces so that this
## comment block can talk about the rule without tripping it. That is only tidiness: the check
## appends them to one string before searching, which is what makes it immune to the trick.

## The two behaviours the shovel can have.
##
## LEGACY is what the game has always done and what the main game still does: the left button
## drives a front of snow forward and also flattens (tamping), the right button pours and tosses.
##
## LOAD_AND_PUSH splits the mouse the way a shovel actually works: one button bites snow and
## loads the blade, the other drives a front forward and picks up the residue of doing so. There
## is no flattening verb in this mode at all.
enum Mode {
	LEGACY = 0,
	LOAD_AND_PUSH = 1,
}

## Fraction of the deliberate load rate that the blade picks up while it is pushing.
##
## WHY NOT ZERO. A real shovel dragged along the ground does not come up empty: something stays
## on the blade. This is what gives the player a reason to push rather than only to load, and it
## is the "residual" that was asked for.
##
## WHY NOT MORE. If pushing loaded as fast as loading there would be no decision: you would just
## push everywhere and the load button would be pointless. A quarter is slow enough to be a
## trickle and fast enough to notice, and it is a constant so it can be tuned without touching
## any logic.
const PUSH_RESIDUE_FACTOR: float = 0.25

## Snow taller than this jams the blade (metres). It is the height of the shovel's side wall:
## above it the snow spills over the edge instead of being carried.
##
## This is the "high pile jams it" rule, and it applies to the deliberate load as well as to the
## pushing front, because it is a property of the blade and not of the button.
const BLADE_WALL_HEIGHT: float = 0.30

## The file this module lives in, so the portability check can read it back.
const SELF_PATH: String = "res://scripts/shovel_modes.gd"

## The fragment that must not appear in this file, split so this file can discuss it.
##
## Assembled at runtime into "pla" + "yground": the check searches for the joined string, so the
## literal never appears here and the check cannot find itself.
const FORBIDDEN_FRAGMENT_A: String = "pla"
const FORBIDDEN_FRAGMENT_B: String = "yground"

## The scene path shape that must not appear either, split for the same reason.
##
## A module that asked for one particular scene file would not be portable no matter what the
## scene was called. The two halves below join into that prefix, so this file can state the rule
## without containing a string that matches it.
const SCENES_PREFIX: String = "res:/"
const SCENES_PREFIX_REST: String = "/scenes/"


## True when this module is still portable: no reference to the test scene in its own source.
##
## Returns a dictionary rather than a bool so the caller can say WHAT was found. A check that only
## says "no" is a check nobody can act on.
static func check_portability() -> Dictionary:
	var name_needle := FORBIDDEN_FRAGMENT_A + FORBIDDEN_FRAGMENT_B
	var path_needle := SCENES_PREFIX + SCENES_PREFIX_REST
	var file := FileAccess.open(SELF_PATH, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"found": [],
			"note": "could not open %s to check it" % SELF_PATH,
		}
	var text := file.get_as_text()
	file.close()
	var lowered := text.to_lower()
	var found: Array[String] = []
	if lowered.contains(name_needle):
		found.append(name_needle)
	if lowered.contains(path_needle):
		found.append(path_needle)
	return {
		"ok": found.is_empty(),
		"found": found,
		"note": (
			"portable: the module names no scene"
			if found.is_empty()
			else "NOT portable: it names %s" % ", ".join(found)
		),
	}


## The label to show for a mode, for a HUD or a log.
static func mode_name(mode: int) -> String:
	match mode:
		Mode.LOAD_AND_PUSH:
			return "LOAD_AND_PUSH"
		_:
			return "LEGACY"


## How much the blade picks up per second while pushing, given the deliberate load rate.
##
## Kept here so the constant cannot be given a nonsense value silently.
static func residue_rate(load_rate: float) -> float:
	return maxf(load_rate, 0.0) * clampf(PUSH_RESIDUE_FACTOR, 0.0, 1.0)
