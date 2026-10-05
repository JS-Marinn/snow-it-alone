extends RefCounted

# Player preferences: the values a player expects to set once and have respected.
#
# Kept as static state, like SessionMode, so the player, the HUD and the batteries all
# read the same numbers without hunting for a node. Deliberately NOT a `class_name`:
# that registers a global through the editor's class cache, and a script started from the
# command line before the cache knows about it fails to parse. Callers preload this file.
#
# Everything here is a value some existing system already exposed or already needed. The
# point of this file is that they persist and can be changed without editing a script.

const PATH: String = "user://settings.json"
const VERSION: int = 1

static var path: String = PATH
static var master_volume: float = 1.0
static var mouse_sensitivity: float = 1.0
static var invert_look: bool = false
static var screen_shake: float = 1.0
static var face_snow_auto_clear: bool = true
static var language: String = "en"

static var _loaded: bool = false

## Loads once per run, whichever system asks first. The player and the HUD both need the
## values and neither can be relied on to run before the other.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_from_disk()

static func defaults() -> void:
	master_volume = 1.0
	mouse_sensitivity = 1.0
	invert_look = false
	screen_shake = 1.0
	face_snow_auto_clear = true
	language = "en"

static func to_dictionary() -> Dictionary:
	var lang := language
	if lang == "en_XA":
		lang = "en"
	return {
		"version": VERSION,
		"master_volume": master_volume,
		"mouse_sensitivity": mouse_sensitivity,
		"invert_look": invert_look,
		"screen_shake": screen_shake,
		"face_snow_auto_clear": face_snow_auto_clear,
		"language": lang,
	}

## Missing keys keep their current value, so a settings file written by an older build
## does not reset everything the player has chosen.
static func from_dictionary(data: Dictionary) -> void:
	master_volume = clampf(float(data.get("master_volume", master_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(data.get("mouse_sensitivity", mouse_sensitivity)), 0.05, 4.0)
	invert_look = bool(data.get("invert_look", invert_look))
	screen_shake = clampf(float(data.get("screen_shake", screen_shake)), 0.0, 2.0)
	face_snow_auto_clear = bool(data.get("face_snow_auto_clear", face_snow_auto_clear))
	language = String(data.get("language", language))
	if language == "en_XA":
		language = "en"

static func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: could not write %s" % path)
		return false
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	return true

## Returns false when there was nothing usable to read, in which case the defaults or the
## current values stand. A corrupt file must not stop the game from starting.
static func load_from_disk() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Settings: %s is not readable, keeping current values" % path)
		return false
	from_dictionary(parsed)
	return true

## Pushes the values into the engine. Volume is the one setting the engine owns rather
## than the game.
static func apply_to_engine() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
		AudioServer.set_bus_mute(bus, master_volume <= 0.0001)
	if not language.is_empty():
		TranslationServer.set_locale(language)

## True when the value differs from its default, for a settings screen that highlights
## what has been changed.
static func is_modified() -> bool:
	return absf(master_volume - 1.0) > 0.001 \
		or absf(mouse_sensitivity - 1.0) > 0.001 \
		or invert_look \
		or absf(screen_shake - 1.0) > 0.001 \
		or not face_snow_auto_clear \
		or language != "en"

static func describe() -> String:
	return "volume %.2f, sensitivity %.2f, invert %s, shake %.2f, auto-clear %s, language %s" % [
		master_volume, mouse_sensitivity, str(invert_look), screen_shake,
		str(face_snow_auto_clear), language]
