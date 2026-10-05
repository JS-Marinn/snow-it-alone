extends RefCounted

# Localization manager: handles translation loading, language selection and live switching.
#
# Follows the conventions of SettingsSystem: statics only, extends RefCounted,
# NO class_name (to avoid Godot class cache issues during command-line boots).
# Callers preload this file: const LocalizationManager = preload("res://scripts/localization_manager.gd").

const SettingsSystemScript = preload("res://scripts/settings_system.gd")

static var _loaded: bool = false
static var _listeners: Array[Callable] = []

## Loads once per run, registers translations with TranslationServer and sets the saved locale.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_translations()
	SettingsSystemScript.ensure_loaded()
	var code := SettingsSystemScript.language
	if code.is_empty():
		code = "en"
	TranslationServer.set_locale(code)

static func _load_translations() -> void:
	var path := "res://locale/strings.csv"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var header := file.get_csv_line()
	if header.size() < 2:
		file.close()
		return

	var locales: Array[String] = []
	var translations: Array[Translation] = []
	for col in range(1, header.size()):
		var loc := header[col].strip_edges()
		locales.append(loc)
		var trans := Translation.new()
		trans.locale = loc
		translations.append(trans)

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty() or row.size() < header.size():
			continue
		var key := row[0].strip_edges()
		if key.is_empty():
			continue
		for col in range(1, header.size()):
			var text := row[col]
			translations[col - 1].add_message(key, text)
	file.close()

	for trans in translations:
		TranslationServer.add_translation(trans)

## Returns the list of languages selectable in the settings screen.
static func available_languages() -> Array[Dictionary]:
	return [
		{"code": "en", "label": "English", "name": "English"},
		{"code": "en_XA", "label": "[Éñglïsh (Psêudô)]", "name": "[Éñglïsh (Psêudô)]"},
	]

## Sets the active language, persists it through SettingsSystem, and notifies listeners.
static func set_language(code: String) -> void:
	TranslationServer.set_locale(code)
	SettingsSystemScript.ensure_loaded()
	SettingsSystemScript.language = code
	SettingsSystemScript.save()
	notify_listeners()

## Current active language code (e.g. "en" or "en_XA").
static func current_language() -> String:
	return TranslationServer.get_locale()

## Maps a locale code or alias to the CSV column name.
static func language_column_key(code: String) -> String:
	var c := code.to_lower().replace("-", "_")
	if c.begins_with("en_xa"):
		return "en_XA"
	if c.begins_with("en"):
		return "en"
	return code

## Registers a callback to be called whenever the language changes.
static func add_listener(c: Callable) -> void:
	if not _listeners.has(c):
		_listeners.append(c)

## Unregisters a language change callback.
static func remove_listener(c: Callable) -> void:
	_listeners.erase(c)

## Notifies all listeners that the language changed.
static func notify_listeners() -> void:
	var valid: Array[Callable] = []
	for c in _listeners:
		if c.is_valid():
			valid.append(c)
			c.call()
	_listeners = valid
