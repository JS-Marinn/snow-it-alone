extends RefCounted

# Session rules: the one place that decides what kind of session this is, and therefore
# whether a snowball to the face is a prank or just snow.
#
# Held as static state deliberately. It is read from the player, from the training dummy
# and from the batteries, and it has to mean the same thing to all of them; a node would
# have to be found first, and the answers would then depend on who was looking.
#
# Deliberately NOT a `class_name`: that registers a global through the editor's class
# cache, and a script started from the command line before that cache knows about it
# fails to parse with "Identifier not declared". Callers preload this file instead, which
# works the moment the file exists.

enum Mode {
	WORK = 0,   ## Just clearing snow. Balls pass through people.
	RUCKUS = 1, ## The default with company: reactions on, nothing scored.
	DUEL = 2,   ## Reactions on and they score.
}

static var mode: int = Mode.RUCKUS

static func reactions_enabled() -> bool:
	return mode != Mode.WORK

static func scoring_enabled() -> bool:
	return mode == Mode.DUEL

static func label(m: int = -1) -> String:
	var which: int = mode if m < 0 else m
	match which:
		Mode.WORK:
			return "Work"
		Mode.DUEL:
			return "Duel"
		_:
			return "Ruckus"

## Parses the value a command line or a save file would carry.
static func from_name(text: String) -> int:
	match text.to_lower():
		"work":
			return Mode.WORK
		"duel":
			return Mode.DUEL
		_:
			return Mode.RUCKUS
