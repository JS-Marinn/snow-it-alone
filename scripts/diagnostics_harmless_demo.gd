extends Node

# --diagnostics-harmless: acceptance test proving that running any --*-shot diagnostic
# never modifies or corrupts the player's real preferences (settings.json, bindings.json),
# and never leaves leftover scratch files.

const SHOT_FLAGS: Array[String] = [
	"--menu-shot",
	"--pseudo-menu-shot",
	"--pause-shot",
	"--settings-shot",
	"--rebind-shot",
]

var _ok: int = 0
var _fail: int = 0

func _check(label: String, ok: bool) -> void:
	print("[HARMLESS] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _ready() -> void:
	print("[HARMLESS] ==== DIAGNOSTICS SAFETY BATTERY ====")
	_run_all_checks()

func _run_all_checks() -> void:
	var settings_path := "user://settings.json"
	var bindings_path := "user://bindings.json"
	var scratch_settings := "user://scratch_settings.json"
	var scratch_bindings := "user://scratch_bindings.json"

	# 1. Backup existing real preferences if present
	var had_settings: bool = FileAccess.file_exists(settings_path)
	var orig_settings_bytes: PackedByteArray = FileAccess.get_file_as_bytes(settings_path) if had_settings else PackedByteArray()

	var had_bindings: bool = FileAccess.file_exists(bindings_path)
	var orig_bindings_bytes: PackedByteArray = FileAccess.get_file_as_bytes(bindings_path) if had_bindings else PackedByteArray()

	var godot_bin: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")

	# Clean up any leftover scratch files before test
	_remove_file(scratch_settings)
	_remove_file(scratch_bindings)

	# --- PART 1: Fresh install / missing files scenario ---
	_remove_file(settings_path)
	_remove_file(bindings_path)

	for flag in SHOT_FLAGS:
		var output: Array = []
		var code: int = OS.execute(godot_bin, ["--headless", "--path", project_path, "--", flag], output, false)
		_check("%s exits cleanly (code=%d)" % [flag, code], code == 0)
		_check("%s leaves no settings.json when absent" % flag, not FileAccess.file_exists(settings_path))
		_check("%s leaves no bindings.json when absent" % flag, not FileAccess.file_exists(bindings_path))
		_check("%s cleans up scratch_settings.json" % flag, not FileAccess.file_exists(scratch_settings))
		_check("%s cleans up scratch_bindings.json" % flag, not FileAccess.file_exists(scratch_bindings))

	# --- PART 2: Existing preferences canary byte-for-byte scenario ---
	var canary_settings := '{\n\t"version": 1,\n\t"master_volume": 0.88,\n\t"canary": "harmless_test"\n}'
	var canary_bindings := '{\n\t"version": 1,\n\t"canary": "harmless_test"\n}'

	_write_text(settings_path, canary_settings)
	_write_text(bindings_path, canary_bindings)

	var canary_settings_bytes := FileAccess.get_file_as_bytes(settings_path)
	var canary_bindings_bytes := FileAccess.get_file_as_bytes(bindings_path)

	for flag in SHOT_FLAGS:
		var output: Array = []
		var code: int = OS.execute(godot_bin, ["--headless", "--path", project_path, "--", flag], output, false)
		_check("%s exits cleanly with existing files (code=%d)" % [flag, code], code == 0)

		var cur_settings_bytes := FileAccess.get_file_as_bytes(settings_path)
		var cur_bindings_bytes := FileAccess.get_file_as_bytes(bindings_path)

		_check("%s preserves settings.json byte-for-byte" % flag, cur_settings_bytes == canary_settings_bytes)
		_check("%s preserves bindings.json byte-for-byte" % flag, cur_bindings_bytes == canary_bindings_bytes)
		_check("%s cleans up scratch_settings.json with existing files" % flag, not FileAccess.file_exists(scratch_settings))
		_check("%s cleans up scratch_bindings.json with existing files" % flag, not FileAccess.file_exists(scratch_bindings))

	# --- PART 3: Pseudo-locale persistence isolation check ---
	var SettingsSystem = preload("res://scripts/settings_system.gd")
	SettingsSystem.path = settings_path
	SettingsSystem.language = "en_XA"
	SettingsSystem.save()
	var saved_text := FileAccess.get_file_as_string(settings_path)
	_check("en_XA is never written to settings file", not saved_text.contains("en_XA"))

	# Reset static path
	SettingsSystem.path = SettingsSystem.PATH

	# Clean up test canary / scratch files
	_remove_file(scratch_settings)
	_remove_file(scratch_bindings)

	# Restore original preferences state
	if had_settings:
		var sf := FileAccess.open(settings_path, FileAccess.WRITE)
		if sf:
			sf.store_buffer(orig_settings_bytes)
			sf.close()
	else:
		_remove_file(settings_path)

	if had_bindings:
		var bf := FileAccess.open(bindings_path, FileAccess.WRITE)
		if bf:
			bf.store_buffer(orig_bindings_bytes)
			bf.close()
	else:
		_remove_file(bindings_path)

	print("[HARMLESS] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	get_tree().create_timer(0.2).timeout.connect(func():
		get_tree().quit(0 if _fail == 0 else 1))

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _write_text(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()
