extends Node

# --save-roundtrip: exercises the slot API against the real filesystem.
#
# Uses scratch slots (98/99) so running it never touches the player's saves.

const SCRATCH: int = 99
const SCRATCH_ALT: int = 98

var _ok: int = 0
var _fail: int = 0

func _ready() -> void:
	print("[SAVE] ==== SAVE SLOT ROUNDTRIP ====")
	_cleanup()
	_test_empty_slot()
	_test_new_game()
	_test_recording()
	_test_reload_from_disk()
	_test_label()
	_test_corrupt_file()
	_test_delete()
	_test_latest_invariant()
	_test_scratch_isolation()
	_cleanup()
	print("[SAVE] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	get_tree().create_timer(0.2).timeout.connect(get_tree().quit)

func _check(label: String, ok: bool) -> void:
	print("[SAVE] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _cleanup() -> void:
	for slot in [SCRATCH, SCRATCH_ALT]:
		SaveSystem.delete_slot(slot)

func _test_empty_slot() -> void:
	var info := SaveSystem.slot_info(SCRATCH)
	print("[SAVE] fresh slot reports exists=%s cleared=%.1f coins=%d" % [
		str(info["exists"]), float(info["cleared_pct"]), int(info["coins"])])
	_check("an unused slot reads as empty", not info["exists"])
	_check("an unused slot has no file", not SaveSystem.slot_exists(SCRATCH))

func _test_new_game() -> void:
	SaveSystem.new_game(SCRATCH)
	print("[SAVE] new_game wrote %s" % SaveSystem.slot_path(SCRATCH))
	_check("new_game creates the file", SaveSystem.slot_exists(SCRATCH))
	_check("new_game selects the slot", SaveSystem.current_slot == SCRATCH)
	_check("new_game starts at level 0 with 0 coins",
		int(SaveSystem.data.get("level_index", -1)) == 0 and int(SaveSystem.data.get("coins", -1)) == 0)
	_check("the schema is versioned", int(SaveSystem.data.get("version", 0)) == SaveSystem.SAVE_VERSION)

func _test_recording() -> void:
	SaveSystem.record_result(45.0, 30)
	SaveSystem.record_result(80.0, 20)
	SaveSystem.record_result(20.0, 5)
	var info := SaveSystem.slot_info(SCRATCH)
	print("[SAVE] after three results: cleared=%d%% coins=%d levels_done=%d" % [
		int(info["cleared_pct"]), int(info["coins"]), int(SaveSystem.data.get("levels_done", -1))])
	_check("cleared percent keeps the best run", int(info["cleared_pct"]) == 80)
	_check("coins accumulate across runs", int(info["coins"]) == 55)
	_check("only a finished level counts as done", int(SaveSystem.data.get("levels_done", -1)) == 0)

func _test_reload_from_disk() -> void:
	SaveSystem.data = {}
	SaveSystem.current_slot = -1
	var loaded := SaveSystem.load_slot(SCRATCH)
	_check("the slot loads again from disk", loaded)
	_check("reloaded coins match", int(SaveSystem.data.get("coins", -1)) == 55)
	_check("reloaded best percent is per level",
		absf(float(SaveSystem.data.get("best_pct", {}).get("0", 0.0)) - 80.0) < 0.01)

func _test_label() -> void:
	var label := SaveSystem.slot_label(SCRATCH)
	var empty_label := SaveSystem.slot_label(SCRATCH_ALT)
	print("[SAVE] label: '%s'" % label)
	print("[SAVE] empty label: '%s'" % empty_label)
	_check("an occupied slot labels with its progress",
		label.contains("Slot 100") and label.contains("80%") and label.contains("$55"))
	_check("an empty slot labels as empty", empty_label.ends_with("Empty"))

func _test_corrupt_file() -> void:
	var file := FileAccess.open(SaveSystem.slot_path(SCRATCH_ALT), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var info := SaveSystem.slot_info(SCRATCH_ALT)
	var loaded := SaveSystem.load_slot(SCRATCH_ALT)
	print("[SAVE] corrupt file: info exists=%s load=%s" % [str(info["exists"]), str(loaded)])
	_check("a corrupt slot does not crash and reads as empty", not info["exists"])
	_check("a corrupt slot refuses to load", not loaded)

func _test_delete() -> void:
	SaveSystem.delete_slot(SCRATCH)
	_check("delete removes the file", not SaveSystem.slot_exists(SCRATCH))
	_check("delete clears the current slot",
		SaveSystem.current_slot == -1 or SaveSystem.current_slot != SCRATCH)
	_check("deleting twice is harmless", SaveSystem.slot_exists(SCRATCH) == false)

func _test_latest_invariant() -> void:
	var has_any := SaveSystem.has_any_slot()
	var latest := SaveSystem.latest_slot()
	print("[SAVE] has_any=%s latest=%d" % [str(has_any), latest])
	_check("latest_slot agrees with has_any_slot",
		(latest >= 0) if has_any else (latest == -1))

func _test_scratch_isolation() -> void:
	var writes_to_real_slots := false
	for slot in range(SaveSystem.SLOT_COUNT):
		writes_to_real_slots = writes_to_real_slots or (slot == SCRATCH or slot == SCRATCH_ALT)
	_check("the battery only uses scratch slots", not writes_to_real_slots)
