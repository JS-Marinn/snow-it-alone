extends Object
## The commit this build came from, printed once at startup as `[BUILD] <hash>`.
##
## WHY THIS EXISTS. "Am I running the code I think I am?" has cost this project real time
## twice, and this bug in particular has been attempted four times with one of those attempts
## showing a reticle that the owner could not see. When a report and a log disagree, the first
## question is which code produced the screenshot, and without this there is no way to answer
## it. One line on startup turns a doubt into a fact.
##
## The hash is written into `build_hash.txt` by the same tool that knows the repository
## (`tools/stamp_build.ps1`), rather than read from git at runtime: a built game does not have
## a `.git` directory, and an exported build should say which commit it is just as loudly as a
## development run does.
##
## Named commit_hash and not hash: hash() is a Godot global function, and a static method
## of the same name is a parse error at the call site, not a warning.
##
## If the file is missing, this says unknown instead of guessing. A build stamp that invents
## a value is worse than no stamp, because it ends the investigation and it is wrong.

const STAMP_PATH: String = "res://build_hash.txt"

static var _hash: String = ""
static var _read: bool = false


## The short commit hash this build was stamped from, or "unknown".
static func commit_hash() -> String:
	if _read:
		return _hash
	_read = true
	if not FileAccess.file_exists(STAMP_PATH):
		_hash = "unknown"
		return _hash
	var file := FileAccess.open(STAMP_PATH, FileAccess.READ)
	if file == null:
		_hash = "unknown"
		return _hash
	_hash = file.get_as_text().strip_edges()
	file.close()
	if _hash.is_empty():
		_hash = "unknown"
	return _hash


## Prints the one line every run starts with. Called from every entry point, because a battery
## run needs it as much as a play session does.
static func announce() -> void:
	print("[BUILD] %s" % commit_hash())
